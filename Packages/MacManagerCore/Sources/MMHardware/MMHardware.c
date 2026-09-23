#include "MMHardware.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <mach/machine.h>
#include <sys/sysctl.h>
#include <stddef.h>
#include <string.h>
#include <math.h>

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

int32_t mm_memory_read(MMMemory *memory) {
    vm_statistics64_data_t value = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    vm_size_t page_size = 0;
    kern_return_t status = host_page_size(host, &page_size);
    if (status == KERN_SUCCESS)
        status = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&value, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS) return status;
    if (count < HOST_VM_INFO64_COUNT) return kIOReturnUnderrun;
    uint64_t physical = 0;
    size_t length = sizeof(physical);
    if (sysctlbyname("hw.memsize", &physical, &length, NULL, 0) != 0)
        return kIOReturnError;
    *memory = (MMMemory){
        physical, page_size, value.internal_page_count, value.wire_count,
        value.compressor_page_count, value.purgeable_count,
        value.external_page_count, value.free_count
    };
    return 0;
}

int32_t mm_gpu_read(double *percent) {
    io_iterator_t iterator = 0;
    kern_return_t status = IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &iterator);
    if (status != KERN_SUCCESS) return status;
    unsigned matches = 0;
    double result = NAN;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        CFTypeRef raw = IORegistryEntryCreateCFProperty(
            service, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
        if (raw && CFGetTypeID(raw) == CFDictionaryGetTypeID()) {
            CFTypeRef number = CFDictionaryGetValue(raw, CFSTR("Device Utilization %"));
            double candidate = NAN;
            if (number && CFGetTypeID(number) == CFNumberGetTypeID()
                && CFNumberGetValue(number, kCFNumberDoubleType, &candidate)) {
                ++matches;
                result = candidate;
            }
        }
        if (raw) CFRelease(raw);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (matches != 1 || !isfinite(result) || result < 0 || result > 100)
        return kIOReturnUnsupported;
    *percent = result;
    return 0;
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

int32_t mm_power_read(double *watts) {
    if (!watts) return kIOReturnBadArgument;
    *watts = NAN;
    uint32_t connection = 0;
    int32_t status = mm_smc_open(&connection);
    if (status) return status;
    status = mm_smc_read_number(connection, 0x50535452, watts); // PSTR
    mm_smc_close(connection);
    if (status) return status;
    if (*watts < 0) { *watts = NAN; return kIOReturnBadArgument; }
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

int32_t mm_smc_read_number(uint32_t connection, uint32_t key, double *value) {
    if (!value) return kIOReturnBadArgument;
    *value = NAN;
    if (!connection) return kIOReturnBadArgument;
    MMTransaction request = {0}, response = {0};
    request.key = key;
    request.command = 9;
    int32_t status = mm_smc_call(connection, &request, &response);
    if (status) return status;
    request.info = response.info;
    if (!request.info.length || request.info.length > sizeof(response.bytes)) return kIOReturnUnsupported;
    request.command = 5; // Read only; never expose SMC write commands
    status = mm_smc_call(connection, &request, &response);
    if (status) return status;
    return mm_smc_decode_number(request.info.type, response.bytes, request.info.length, value);
}
