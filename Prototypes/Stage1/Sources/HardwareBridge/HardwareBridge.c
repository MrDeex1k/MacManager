#include "HardwareBridge.h"
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

// Undocumented AppleSMC user-client ABI. Reference and limitations in README.
// C layout avoids relying on Swift struct ABI; no write command is implemented.
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

static int32_t smc_call(io_connect_t connection, MMTransaction *request,
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

int32_t mm_power_candidate_read(double *watts, uint32_t *data_type) {
    *watts = NAN;
    *data_type = 0;
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return kIOReturnNotFound;
    io_connect_t connection = 0;
    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (status != KERN_SUCCESS) return status;

    MMTransaction request = {0}, response = {0};
    request.key = 0x50535452; // PSTR only
    request.command = 9; // read metadata
    status = smc_call(connection, &request, &response);
    if (status == 0) {
        request.info = response.info;
        *data_type = response.info.type;
        if (request.info.length == 0 || request.info.length > sizeof(response.bytes)) {
            status = kIOReturnUnsupported;
        } else {
            request.command = 5; // read bytes
            status = smc_call(connection, &request, &response);
        }
    }
    IOServiceClose(connection);
    if (status != 0) return status;
    if (request.info.type == 0x666c7420 && request.info.length == 4) { // flt
        float value;
        memcpy(&value, response.bytes, sizeof(value)); // Apple Silicon, little-endian
        *watts = value;
    } else if (request.info.type == 0x73703738 && request.info.length == 2) { // sp78
        uint16_t bits = ((uint16_t)response.bytes[0] << 8) | response.bytes[1];
        *watts = (int16_t)bits / 256.0;
    } else {
        return kIOReturnUnsupported;
    }
    if (!isfinite(*watts) || *watts < 0) return kIOReturnBadArgument;
    return 0;
}
