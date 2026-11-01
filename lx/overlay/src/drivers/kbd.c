/**
 * @file kbd.c
 * @brief Envoltorios en C del driver de teclado (kbd.asm)
 * Shaeon (Carlos Palmero).
 */
#include "drivers/kbd.h"

void kbd_activate_lx(void) __naked {
    __asm
        EXTERN __kbd_lx_vtable, __kbd_activate_driver
        ld hl, __kbd_lx_vtable
        jp __kbd_activate_driver
    __endasm;
}

uint8_t kbd_detect(void) __naked {
    __asm
        EXTERN __kbd_detect
        call __kbd_detect
        ld l, a
        ret
    __endasm;
}

uint8_t kbd_install(void) __naked {
    __asm
        EXTERN __kbd_install
        call __kbd_install
        ld l, a
        ret
    __endasm;
}

uint8_t kbd_hit(void) __naked {
    __asm
        EXTERN __kbd_hit
        call __kbd_hit
        ld l, a
        ret
    __endasm;
}

uint8_t kbd_getc(void) __naked {
    __asm
        EXTERN __kbd_getc
        call __kbd_getc
        ld l, a
        ret
    __endasm;
}

uint8_t kbd_shift_state(void) __naked {
    __asm
        EXTERN __kbd_shift_state
        call __kbd_shift_state
        ld l, a
        ret
    __endasm;
}

void* kbd_get_info(void) __naked {
    __asm
        EXTERN __kbd_get_info
        jp __kbd_get_info
    __endasm;
}

void kbd_uninstall(void) __naked {
    __asm
        EXTERN __kbd_uninstall
        jp __kbd_uninstall
    __endasm;
}

uint8_t kbd_row(uint8_t row) __z88dk_fastcall __naked {
    row;
    __asm
        EXTERN __kbd_row
        ld a, l
        call __kbd_row
        ld l, a
        ret
    __endasm;
}
