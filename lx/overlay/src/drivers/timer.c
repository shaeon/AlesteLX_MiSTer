/**
 * @file timer.c
 * @brief Envoltorios en C del driver del temporizador (timer.asm)
 * Shaeon (Carlos Palmero).
 */
#include "drivers/timer.h"

void timer_activate_lx(void) __naked {
    __asm
        EXTERN __timer_lx_vtable, __timer_activate_driver
        ld hl, __timer_lx_vtable
        jp __timer_activate_driver
    __endasm;
}

uint8_t timer_detect(void) __naked {
    __asm
        EXTERN __timer_detect
        call __timer_detect
        ld l, a
        ret
    __endasm;
}

uint8_t timer_install(void) __naked {
    __asm
        EXTERN __timer_install
        call __timer_install
        ld l, a
        ret
    __endasm;
}

void* timer_get_info(void) __naked {
    __asm
        EXTERN __timer_get_info
        jp __timer_get_info
    __endasm;
}

void timer_uninstall(void) __naked {
    __asm
        EXTERN __timer_uninstall
        jp __timer_uninstall
    __endasm;
}

uint16_t timer_get_ms(void) __naked {
    __asm
        EXTERN __timer_get_ms
        jp __timer_get_ms
    __endasm;
}

void timer_delay_ms(uint16_t ms) __z88dk_fastcall __naked {
    ms;
    __asm
        EXTERN __timer_delay_ms
        jp __timer_delay_ms
    __endasm;
}

/* pila: +2 periodo (2 bytes), +4 rutina (2 bytes) */
void timer_set_periodic(uint16_t period_us, int_handler_t handler) __naked {
    period_us; handler;
    __asm
        EXTERN __timer_set_periodic
        ld hl, #2
        add hl, sp
        ld c, (hl)
        inc hl
        ld b, (hl)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        ld h, b
        ld l, c
        jp __timer_set_periodic
    __endasm;
}

uint16_t timer_get_count(void) __naked {
    __asm
        EXTERN __timer_get_count
        jp __timer_get_count
    __endasm;
}
