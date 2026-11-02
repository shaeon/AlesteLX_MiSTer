/**
 * @file snd.h
 * @brief Sonido por muestras (driver polimorfico, Magic Sound 2 del Aleste LX)
 * Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
 *
 * Cuatro canales que leen muestras con signo (8 o 16 bits) de la memoria por
 * DMA, a 48 kHz, con volumen izquierdo/derecho, bucle y un temporizador para
 * secuenciar musica. Las direcciones son fisicas (dma_phys).
 */
#ifndef __SND_H__
#define __SND_H__

#include <stdint.h>
#include "drivers/int.h"

#define SND_CHANNELS   4
#define SND_RATE       48000UL

#define SND_LOOP   0x02    /* vuelve a 'loop' al llegar al final */
#define SND_16BIT  0x04    /* muestras de 16 bits (little endian) */
#define SND_IRQ    0x08    /* interrupcion al terminar */

/** Voz: el mismo orden que los registros del canal */
typedef struct {
    uint8_t channel;       /**< 0-3 */
    uint8_t flags;         /**< SND_LOOP, SND_16BIT, SND_IRQ */
    uint8_t start[3];      /**< direccion fisica de la primera muestra */
    uint8_t end[3];        /**< direccion fisica del final (no incluido) */
    uint8_t loop[3];       /**< donde vuelve con SND_LOOP */
    uint8_t vol_l;         /**< 0-255 */
    uint8_t vol_r;
    uint8_t step[3];       /**< 8.16: 010000h = una muestra por salida (48 kHz) */
} snd_voice_t;

void    snd_activate_ms2(void);
uint8_t snd_detect(void);
uint8_t snd_install(void);
void*   snd_get_info(void);
void    snd_uninstall(void);
void    snd_play(const snd_voice_t* voice) __z88dk_fastcall;
void    snd_stop(uint8_t channel) __z88dk_fastcall;
void    snd_set_volume(uint8_t channel, uint8_t left, uint8_t right);
void    snd_set_step(uint8_t channel, uint32_t step);
void    snd_master(uint8_t left, uint8_t right);
uint8_t snd_status(void);                       /* bits 7-4 sonando, 3-0 terminado */
void    snd_set_timer(uint16_t period_samples, int_handler_t handler); /* 960 = 50 Hz */

/* Ayudas */
uint32_t snd_step_rate(uint16_t sample_rate) __z88dk_fastcall; /* muestras/s -> paso */
uint32_t snd_step_period(uint16_t amiga_period) __z88dk_fastcall; /* periodo de Amiga (PAL) -> paso */
void     snd_voice_set(snd_voice_t* v, uint8_t channel, uint32_t start, uint16_t length,
                       uint16_t loop_start, uint16_t loop_length, uint8_t flags);

#endif
