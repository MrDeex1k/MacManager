#include "MMHardware.h"
#include <stdio.h>
#include <math.h>

int main(void) {
    uint32_t connection = 0;
    int32_t status = mm_smc_open(&connection);
    if (status) { fprintf(stderr, "SMC unavailable: %d\n", status); return 1; }
    double total = NAN;
    status = mm_smc_read_number(connection, 0x234b4559, &total); // #KEY
    if (status || total < 0 || total > 16384 || floor(total) != total) {
        fprintf(stderr, "SMC inventory unavailable\n");
        mm_smc_close(connection);
        return 1;
    }
    for (uint32_t i = 0; i < (uint32_t)total; ++i) {
        uint32_t key = 0;
        if (mm_smc_key_at(connection, i, &key)) continue;
        char name[5] = {key >> 24, key >> 16, key >> 8, key, 0};
        // Inventory only: do not infer CPU/GPU semantics from the prefix.
        if (name[0] != 'T' && key != 0x464e756d
            && !(name[0] == 'F' && name[2] == 'A' && name[3] == 'c')) continue;
        double value = NAN;
        status = mm_smc_read_number(connection, key, &value);
        if (!status) printf("%s\t%.2f\n", name, value);
        else printf("%s\tunavailable (%d)\n", name, status);
    }
    mm_smc_close(connection);
    return 0;
}
