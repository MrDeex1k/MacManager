#include "MMHardware.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <mach/machine.h>
#include <sys/sysctl.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include <pthread.h>

int32_t mm_cpu_read(MMCPUTicks *ticks) {
    host_cpu_load_info_data_t value = {0};
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    mach_port_t host = mach_host_self();
    kern_return_t status = host_statistics(host, HOST_CPU_LOAD_INFO,
                                          (host_info_t)&value, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS) return status;
    if (count != HOST_CPU_LOAD_INFO_COUNT) return kIOReturnUnderrun;
    *ticks = (MMCPUTicks){
        value.cpu_ticks[CPU_STATE_USER], value.cpu_ticks[CPU_STATE_SYSTEM],
        value.cpu_ticks[CPU_STATE_IDLE], value.cpu_ticks[CPU_STATE_NICE]
    };
    return 0;
}

static pthread_once_t memory_constants_once = PTHREAD_ONCE_INIT;
static uint64_t physical_memory = 0;
static void read_memory_constants(void) {
    size_t length = sizeof(physical_memory);
    if (sysctlbyname("hw.memsize", &physical_memory, &length, NULL, 0) != 0)
        physical_memory = 0;
}

int32_t mm_memory_read(MMMemory *memory) {
    vm_statistics64_data_t value = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    kern_return_t status = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&value, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS) return status;
    if (count < HOST_VM_INFO64_COUNT) return kIOReturnUnderrun;
    pthread_once(&memory_constants_once, read_memory_constants);
    if (!physical_memory || !vm_page_size) return kIOReturnError;
    *memory = (MMMemory){
        physical_memory, vm_page_size, value.internal_page_count, value.wire_count,
        value.compressor_page_count, value.purgeable_count,
        value.external_page_count, value.free_count
    };
    return 0;
}

static int32_t mm_gpu_value(io_service_t service, double *percent) {
    CFTypeRef raw = IORegistryEntryCreateCFProperty(
        service, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
    double result = NAN;
    if (raw && CFGetTypeID(raw) == CFDictionaryGetTypeID()) {
        CFTypeRef number = CFDictionaryGetValue(raw, CFSTR("Device Utilization %"));
        if (number && CFGetTypeID(number) == CFNumberGetTypeID())
            CFNumberGetValue(number, kCFNumberDoubleType, &result);
    }
    if (raw) CFRelease(raw);
    if (!isfinite(result) || result < 0 || result > 100) return kIOReturnUnsupported;
    *percent = result;
    return 0;
}

void mm_gpu_close(uint32_t service) {
    if (service) IOObjectRelease(service);
}

static int32_t mm_gpu_find(uint32_t *selected) {
    io_iterator_t iterator = 0;
    kern_return_t status = IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &iterator);
    if (status != KERN_SUCCESS) return status;
    unsigned matches = 0;
    io_service_t service, candidate = 0;
    while ((service = IOIteratorNext(iterator))) {
        double value = NAN;
        if (mm_gpu_value(service, &value) == 0) {
            ++matches;
            if (!candidate) { candidate = service; continue; }
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (matches != 1) { mm_gpu_close(candidate); return kIOReturnUnsupported; }
    *selected = candidate;
    return 0;
}

int32_t mm_gpu_read_cached(uint32_t *service, double *percent) {
    if (!service || !percent) return kIOReturnBadArgument;
    *percent = NAN;
    if (*service) {
        int32_t status = mm_gpu_value(*service, percent);
        if (!status) return 0;
        mm_gpu_close(*service); *service = 0;
    }
    int32_t status = mm_gpu_find(service);
    if (status) return status;
    status = mm_gpu_value(*service, percent);
    if (status) { mm_gpu_close(*service); *service = 0; }
    return status;
}

// Undocumented, read-only AppleSMC user-client ABI.
typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} MMFirmware;

typedef struct {
    uint16_t version, length;
    uint32_t cpu, gpu, memory;
} MMLimits;

typedef struct {
    uint32_t length, type;
    uint8_t attributes;
} MMKeyInfo;

typedef struct {
    uint32_t key;
    MMFirmware firmware;
    MMLimits limits;
    MMKeyInfo info;
    uint8_t result, status, command;
    uint32_t argument;
    uint8_t bytes[32];
} MMTransaction;

_Static_assert(sizeof(MMTransaction) == 80, "Unexpected SMC ABI size");
_Static_assert(offsetof(MMTransaction, bytes) == 48, "Unexpected SMC data offset");

static int32_t mm_smc_call(io_connect_t connection, MMTransaction *request,
                           MMTransaction *response) {
    size_t length = sizeof(*response);
    memset(response, 0, sizeof(*response));
    kern_return_t status = IOConnectCallStructMethod(
        connection, 2, request, sizeof(*request), response, &length);
    if (status != KERN_SUCCESS) return status;
    if (length != sizeof(*response)) return kIOReturnUnderrun;
    if (response->result != 0) return kIOReturnNotFound;
    return 0;
}

int32_t mm_smc_open(uint32_t *connection) {
    if (!connection) return kIOReturnBadArgument;
    *connection = 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return kIOReturnNotFound;
    int32_t status = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return status;
}

void mm_smc_close(uint32_t connection) {
    if (connection) IOServiceClose(connection);
}

int32_t mm_smc_key_at(uint32_t connection, uint32_t index, uint32_t *key) {
    if (!key || !connection) return kIOReturnBadArgument;
    *key = 0;
    MMTransaction request = {0}, response = {0};
    request.command = 8; // Read key at index
    request.argument = index;
    int32_t status = mm_smc_call(connection, &request, &response);
    if (!status) *key = response.key;
    return status;
}

int32_t mm_smc_decode_number(uint32_t type, const uint8_t *bytes, uint32_t length, double *value) {
    if (!value) return kIOReturnBadArgument;
    *value = NAN;
    if (!bytes) return kIOReturnBadArgument;
    switch (type) {
        case 0x666c7420: { // flt : native little-endian IEEE float on Apple Silicon
            if (length != 4) return kIOReturnUnsupported;
            float raw;
            memcpy(&raw, bytes, 4);
            *value = raw;
            break;
        }
        case 0x73703738: // sp78: signed big-endian 8.8 temperature
            if (length != 2) return kIOReturnUnsupported;
            *value = (int16_t)(((uint16_t)bytes[0] << 8) | bytes[1]) / 256.0;
            break;
        case 0x66706532: // fpe2: unsigned big-endian 14.2 RPM
            if (length != 2) return kIOReturnUnsupported;
            *value = (((uint16_t)bytes[0] << 8) | bytes[1]) / 4.0;
            break;
        case 0x75693820: // ui8
            if (length != 1) return kIOReturnUnsupported;
            *value = bytes[0];
            break;
        case 0x75693136: // ui16
            if (length != 2) return kIOReturnUnsupported;
            *value = ((uint16_t)bytes[0] << 8) | bytes[1];
            break;
        case 0x75693332: // ui32
            if (length != 4) return kIOReturnUnsupported;
            *value = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16)
                | ((uint32_t)bytes[2] << 8) | bytes[3];
            break;
        default: return kIOReturnUnsupported;
    }
    if (!isfinite(*value)) { *value = NAN; return kIOReturnBadArgument; }
    return 0;
}

int32_t mm_smc_read_number_cached(uint32_t connection, uint32_t key, MMSMCKeyInfo *info, double *value) {
    if (!value || !info) return kIOReturnBadArgument;
    *value = NAN;
    if (!connection) return kIOReturnBadArgument;
    MMTransaction request = {0}, response = {0};
    request.key = key;
    if (!info->length) {
        request.command = 9;
        int32_t status = mm_smc_call(connection, &request, &response);
        if (status) return status;
        if (!response.info.length || response.info.length > sizeof(response.bytes)) return kIOReturnUnsupported;
        *info = (MMSMCKeyInfo){response.info.length, response.info.type, response.info.attributes};
    }
    if (info->length > sizeof(response.bytes)) { info->length = 0; return kIOReturnUnsupported; }
    request.info = (MMKeyInfo){info->length, info->type, info->attributes};
    request.command = 5; // Read only; never expose SMC write commands
    int32_t status = mm_smc_call(connection, &request, &response);
    if (!status) status = mm_smc_decode_number(info->type, response.bytes, info->length, value);
    if (status) info->length = 0; // Rediscover metadata after a failed read.
    return status;
}

int32_t mm_smc_read_number(uint32_t connection, uint32_t key, double *value) {
    MMSMCKeyInfo info = {0};
    return mm_smc_read_number_cached(connection, key, &info, value);
}
