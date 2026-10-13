#include <assert.h>
#include <stdlib.h>
#include "memslot.h"

/* Retain the production logger's fatal-level contract without requiring
 * the rest of the server. Any remaining spice_critical call fails the test. */
static unsigned warnings;
void spice_log(GLogLevelFlags level, const char *where, const char *function,
               const char *format, ...) {
    (void)where; (void)function; (void)format;
    if (level & (G_LOG_LEVEL_CRITICAL | G_LOG_LEVEL_ERROR)) abort();
    if (level & G_LOG_LEVEL_WARNING) warnings++;
}

int main(void) {
    RedMemSlotInfo info;
    memslot_info_init(&info, 1, 1, 2, 1, 0);
    memslot_info_add_slot(&info, 0, 0, 0, 0x1000, 0x2000, 1);
    QXLPHYSICAL valid = ((QXLPHYSICAL)1 << info.memslot_gen_shift) | 0x1500;
    assert(memslot_get_virt(&info, valid, 32, 0) == (void *)0x1500);
    assert(memslot_get_virt(&info, valid, 32, 1) == NULL);
    assert(memslot_get_virt(&info, valid, 32, -1) == NULL);
    assert(memslot_get_virt(&info, valid | ((QXLPHYSICAL)1 << info.memslot_id_shift), 32, 0) == NULL);
    QXLPHYSICAL stale = ((QXLPHYSICAL)2 << info.memslot_gen_shift) | 0x1500;
    assert(memslot_get_virt(&info, stale, 32, 0) == NULL);
    assert(memslot_get_virt(&info, valid, 0x1000, 0) == NULL);
    assert(!memslot_validate_virt(&info, 0x1500, -1, 32, 0));
    assert(!memslot_validate_virt(&info, 0x1500, 1, 32, 0));
    assert(!memslot_validate_virt(&info, 0x1500, 0, 32, UINT32_MAX));
    assert(!memslot_validate_virt(&info, UINTPTR_MAX - 2, 0, 8, 0));
    assert(!memslot_validate_virt(&info, 0x0fff, 0, 32, 0));
    assert(warnings == 10);
    memslot_info_destroy(&info);
    puts("SPICE memory-slot crash regression checks passed");
    return 0;
}
