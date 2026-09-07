#ifndef MM_HARDWARE_BRIDGE_H
#define MM_HARDWARE_BRIDGE_H
#include <stdint.h>

typedef struct {
    uint32_t user, system, idle, nice;
} MMCPUTicks;

typedef struct {
    uint64_t physical_bytes;
    uint64_t page_size;
    uint64_t anonymous_pages, wired_pages, compressor_pages, purgeable_pages;
    uint64_t file_backed_pages, free_pages;
} MMMemory;

// All functions read only, returning zero on success.
int32_t mm_cpu_read(MMCPUTicks *ticks);
int32_t mm_memory_read(MMMemory *memory);
int32_t mm_gpu_read(double *percent);

// Reads ONLY PSTR (candidate total power), not arbitrary SMC keys.
// Does not claim the value represents whole-device power.
int32_t mm_power_candidate_read(double *watts, uint32_t *data_type);
#endif
