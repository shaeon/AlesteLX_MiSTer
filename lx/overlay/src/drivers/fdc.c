/**
 * @file fdc.c
 * @brief Envoltorios en C del driver de disquetera (fdc.asm)
 * Shaeon (Carlos Palmero).
 */
#include "drivers/fdc.h"

void fdc_activate_765(void) __naked {
    __asm
        EXTERN __fdc_765_vtable, __fdc_activate_driver
        ld hl, __fdc_765_vtable
        jp __fdc_activate_driver
    __endasm;
}

uint8_t fdc_detect(void) __naked {
    __asm
        EXTERN __fdc_detect
        call __fdc_detect
        ld l, a
        ret
    __endasm;
}

uint8_t fdc_install(void) __naked {
    __asm
        EXTERN __fdc_install
        call __fdc_install
        ld l, a
        ret
    __endasm;
}

void* fdc_get_info(void) __naked {
    __asm
        EXTERN __fdc_get_info
        jp __fdc_get_info
    __endasm;
}

void fdc_uninstall(void) __naked {
    __asm
        EXTERN __fdc_uninstall
        jp __fdc_uninstall
    __endasm;
}

uint8_t fdc_status(void) __naked {
    __asm
        EXTERN __fdc_status
        call __fdc_status
        ld l, a
        ret
    __endasm;
}

/* pila: +2 unidad, +3 pista, +4 cara, +5 sector (1 byte), +6 bufer (2) */
uint8_t fdc_read(uint8_t drive, uint8_t track, uint8_t head, uint8_t sector, void* buf) __naked {
    drive; track; head; sector; buf;
    __asm
        EXTERN __fdc_read
        push ix
        ld ix, #4
        add ix, sp
        ld d, (ix + 1)
        ld e, (ix + 2)
        ld c, (ix + 3)
        ld l, (ix + 4)
        ld h, (ix + 5)
        ld a, (ix + 0)
        call __fdc_read
        pop ix
        ld l, a
        ret
    __endasm;
}

/* pila: +2 unidad, +3 pista, +4 cara, +5 sector, +6 cuenta (1 byte), +7 bufer (2) */
uint8_t fdc_read_multi(uint8_t drive, uint8_t track, uint8_t head, uint8_t sector, uint8_t count, void* buf) __naked {
    drive; track; head; sector; count; buf;
    __asm
        EXTERN __fdc_read_multi
        push ix
        ld ix, #4
        add ix, sp
        ld d, (ix + 1)
        ld e, (ix + 2)
        ld c, (ix + 3)
        ld b, (ix + 4)
        ld l, (ix + 5)
        ld h, (ix + 6)
        ld a, (ix + 0)
        call __fdc_read_multi
        pop ix
        ld l, a
        ret
    __endasm;
}

uint8_t fdc_read_lba(uint8_t drive, uint16_t lba, void* buf) {
    uint8_t track = lba / (FDC_SPT * FDC_HEADS);
    uint8_t rest  = lba % (FDC_SPT * FDC_HEADS);
    uint8_t head  = rest >= FDC_SPT;
    uint8_t sec   = (head ? rest - FDC_SPT : rest) + 1;
    uint8_t r, tries;
    for (tries = 0; tries < 3; tries++) {
        r = fdc_read(drive, track, head, sec, buf);
        if (!r) break;
    }
    return r;
}
