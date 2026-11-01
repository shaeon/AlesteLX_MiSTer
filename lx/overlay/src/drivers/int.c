/**
 * @file int.c
 * @brief Envoltorios en C del driver de interrupciones (int.asm)
 * Shaeon (Carlos Palmero). Los valores de 8 bits se devuelven en L.
 */
#include "drivers/int.h"

void int_activate_lx(void) __naked {
    __asm
        EXTERN __int_lx_vtable, __int_activate_driver
        ld hl, __int_lx_vtable
        jp __int_activate_driver
    __endasm;
}

uint8_t int_detect(void) __naked {
    __asm
        EXTERN __int_detect
        call __int_detect
        ld l, a
        ret
    __endasm;
}

uint8_t int_install(void) __naked {
    __asm
        EXTERN __int_install
        call __int_install
        ld l, a
        ret
    __endasm;
}

void* int_get_info(void) __naked {
    __asm
        EXTERN __int_get_info
        jp __int_get_info
    __endasm;
}

void int_uninstall(void) __naked {
    __asm
        EXTERN __int_uninstall
        jp __int_uninstall
    __endasm;
}

/* pila: +2 linea (1 byte), +3 rutina (2 bytes) */
void int_set_handler(uint8_t line, int_handler_t handler) __naked {
    line; handler;
    __asm
        EXTERN __int_set_handler
        ld hl, #2
        add hl, sp
        ld a, (hl)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl
        jp __int_set_handler
    __endasm;
}

void int_enable(uint8_t line) __z88dk_fastcall __naked {
    line;
    __asm
        EXTERN __int_enable
        ld a, l
        jp __int_enable
    __endasm;
}

void int_disable(uint8_t line) __z88dk_fastcall __naked {
    line;
    __asm
        EXTERN __int_disable
        ld a, l
        jp __int_disable
    __endasm;
}
