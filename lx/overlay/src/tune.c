/**
 * @file tune.c
 * @brief Himno de la alegria a cuatro canales por la Magic Sound 2
 * Shaeon (Carlos Palmero).
 *
 *   canal 0  melodia, onda cuadrada, al centro, con caida de volumen
 *   canal 1  bajo, senoidal, al centro
 *   canal 2  arpegio del acorde, diente de sierra, a la izquierda
 *   canal 3  charles (ruido que se apaga), a la derecha, en cada negra
 * El temporizador de la MS2 llama a tick() 50 veces por segundo, desde la
 * interrupcion; cada fila (corchea) dura SPEED ticks.
 */
#include "tune.h"
#include "drivers/snd.h"
#include "drivers/dma.h"
#include "tune_data.h"

#define SPEED 8

static snd_voice_t v;
static uint8_t tick_n, row, arp_i;
static uint8_t mel_vol, bass_vol;
static uint32_t noise_phys;

static uint32_t step_of(uint8_t note) {
    if (note < NOTE_LO) note = NOTE_LO;
    if (note > NOTE_HI) note = NOTE_HI;
    return note_step[note - NOTE_LO];
}

static void start_wave(uint8_t ch, const signed char* wave, uint8_t vl, uint8_t vr) {
    snd_voice_set(&v, ch, dma_phys(wave), 32, 0, 32, 0);
    v.vol_l = vl; v.vol_r = vr;
    v.step[0] = 0; v.step[1] = 0; v.step[2] = 0;     /* callado hasta la primera nota */
    snd_play(&v);
}

static void hihat(void) {
    snd_voice_set(&v, 3, noise_phys, sizeof(wave_noise), 0, 0, 0);
    v.vol_l = 40; v.vol_r = 110;
    v.step[0] = 0; v.step[1] = 0; v.step[2] = 1;
    snd_play(&v);
}

static void tick(void) {
    uint8_t n;
    if (tick_n == 0) {
        n = song_melody[row];
        if (n) { snd_set_step(0, step_of(n)); mel_vol = 230; }
        n = song_bass[row];
        if (n) { snd_set_step(1, step_of(n)); bass_vol = 220; }
        if (!(row & 1)) hihat();
    }
    /* arpegio: una nota del acorde cada 2 ticks */
    if (!(tick_n & 1)) {
        static const uint8_t ch_c[3] = { 72, 76, 79 }, ch_g[3] = { 67, 71, 74 };
        const uint8_t* c = song_chord[row] == 'G' ? ch_g : ch_c;
        snd_set_step(2, step_of(c[arp_i]));
        if (++arp_i == 3) arp_i = 0;
    }
    /* caida del volumen */
    snd_set_volume(0, mel_vol, mel_vol);
    snd_set_volume(1, bass_vol, bass_vol);
    if (mel_vol > 70) mel_vol -= 6;
    if (bass_vol > 90) bass_vol -= 3;

    if (++tick_n == SPEED) {
        tick_n = 0;
        if (++row == SONG_ROWS) row = 0;
    }
}

void tune_start(void) {
    tick_n = 0; row = 0; arp_i = 0; mel_vol = 0; bass_vol = 0;
    noise_phys = dma_phys(wave_noise);
    snd_master(255, 255);
    start_wave(0, wave_square, 0, 0);
    start_wave(1, wave_sine, 0, 0);
    start_wave(2, wave_saw, 70, 20);
    snd_set_timer(960, tick);           /* 48000 / 960 = 50 Hz */
}

void tune_stop(void) {
    uint8_t ch;
    snd_set_timer(0, 0);
    for (ch = 0; ch < SND_CHANNELS; ch++) snd_stop(ch);
}

uint8_t tune_row(void) { return row; }
