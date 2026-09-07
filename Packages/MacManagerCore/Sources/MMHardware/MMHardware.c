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
