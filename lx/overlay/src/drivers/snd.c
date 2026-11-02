/**
 * @file snd.c
 * @brief Envoltorios en C del driver de sonido (snd.asm) y ayudas
 * Shaeon (Carlos Palmero).
 */
#include "drivers/snd.h"

void snd_activate_ms2(void) __naked {
    __asm
        EXTERN __snd_ms2_vtable, __snd_activate_driver
        ld hl, __snd_ms2_vtable
        jp __snd_activate_driver
    __endasm;
}

uint8_t snd_detect(void) __naked {
    __asm
        EXTERN __snd_detect
        call __snd_detect
        ld l, a
        ret
    __endasm;
}

uint8_t snd_install(void) __naked {
    __asm
        EXTERN __snd_install
        call __snd_install
        ld l, a
        ret
    __endasm;
}

void* snd_get_info(void) __naked {
    __asm
        EXTERN __snd_get_info
        jp __snd_get_info
    __endasm;
}

void snd_uninstall(void) __naked {
    __asm
        EXTERN __snd_uninstall
        jp __snd_uninstall
    __endasm;
}

void snd_play(const snd_voice_t* voice) __z88dk_fastcall __naked {
    voice;
    __asm
        EXTERN __snd_play
        jp __snd_play
    __endasm;
}

void snd_stop(uint8_t channel) __z88dk_fastcall __naked {
    channel;
    __asm
        EXTERN __snd_stop
        ld a, l
        jp __snd_stop
    __endasm;
}

/* pila: +2 canal, +3 izquierdo, +4 derecho (1 byte cada uno) */
void snd_set_volume(uint8_t channel, uint8_t left, uint8_t right) __naked {
    channel; left; right;
    __asm
        EXTERN __snd_set_volume
        ld hl, #2
        add hl, sp
        ld a, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld e, (hl)
        jp __snd_set_volume
    __endasm;
}

/* pila: +2 canal (1 byte), +3 paso (4 bytes) */
void snd_set_step(uint8_t channel, uint32_t step) __naked {
    channel; step;
    __asm
        EXTERN __snd_set_step
        ld hl, #2
        add hl, sp
        ld a, (hl)
        inc hl
        ld c, (hl)
        inc hl
        ld b, (hl)
        inc hl
        ld e, (hl)
        ld h, b
        ld l, c
        jp __snd_set_step
    __endasm;
}

/* pila: +2 izquierdo, +3 derecho */
void snd_master(uint8_t left, uint8_t right) __naked {
    left; right;
    __asm
        EXTERN __snd_master
        ld hl, #2
        add hl, sp
        ld d, (hl)
        inc hl
        ld e, (hl)
        jp __snd_master
    __endasm;
}

uint8_t snd_status(void) __naked {
    __asm
        EXTERN __snd_status
        call __snd_status
        ld l, a
        ret
    __endasm;
}

/* pila: +2 periodo (2 bytes), +4 rutina (2 bytes) */
void snd_set_timer(uint16_t period_samples, int_handler_t handler) __naked {
    period_samples; handler;
    __asm
        EXTERN __snd_set_timer
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
        jp __snd_set_timer
    __endasm;
}

void snd_set_timer_period(uint16_t period_samples) __z88dk_fastcall __naked {
    period_samples;
    __asm
        EXTERN __snd_command
        ld a, 1
        jp __snd_command
    __endasm;
}

uint32_t snd_step_rate(uint16_t sample_rate) __z88dk_fastcall {
    return ((uint32_t)sample_rate << 16) / SND_RATE;
}

/* reloj de Paula (PAL) 3546895 Hz: paso = 3546895 * 65536 / 48000 / periodo */
uint32_t snd_step_period(uint16_t amiga_period) __z88dk_fastcall {
    if (amiga_period == 0) return 0;
    return 4842694UL / amiga_period;
}

static void put24(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
}

void snd_voice_set(snd_voice_t* v, uint8_t channel, uint32_t start, uint16_t length,
                   uint16_t loop_start, uint16_t loop_length, uint8_t flags) {
    v->channel = channel;
    if (loop_length > 2) {
        flags |= SND_LOOP;
        put24(v->end, start + loop_start + loop_length);
    } else {
        flags &= ~SND_LOOP;
        put24(v->end, start + length);
    }
    v->flags = flags;
    put24(v->start, start);
    put24(v->loop, start + loop_start);
}
