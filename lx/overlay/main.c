/*
 * main.c - Arranque de la BIOS del Aleste LX en el modo LX del core
 * Shaeon (Carlos Palmero), a partir del main.c de aleste-xi-bios (hww).
 *
 * Instala los drivers (MMU, CRTC, video 640x200, paleta, interrupciones,
 * temporizador, DMA, teclado y sonido) y arranca un pequeno monitor de ordenes en
 * una consola de texto de 80x25.
 */
#include <stdint.h>
#include "drivers/mmu.h"
#include "drivers/crtc.h"
#include "drivers/vbuf.h"
#include "drivers/palette.h"
#include "drivers/int.h"
#include "drivers/timer.h"
#include "drivers/dma.h"
#include "drivers/kbd.h"
#include "drivers/snd.h"
#include "tune.h"
#include "con.h"

#define VRAM_PHYS   0xC40000UL
#define VRAM_STRIDE 80

/* ---- Pitido por la Magic Sound 2: onda cuadrada de 16 muestras (3 kHz) */
static const signed char beep_wave[16] = { 90,90,90,90,90,90,90,90, -90,-90,-90,-90,-90,-90,-90,-90 };
static snd_voice_t beep_voice;
static void beep(uint16_t ms) {
    snd_voice_set(&beep_voice, 3, dma_phys(beep_wave), sizeof(beep_wave), 0, sizeof(beep_wave), 0);
    beep_voice.vol_l = 0x60; beep_voice.vol_r = 0x60;
    beep_voice.step[0] = 0; beep_voice.step[1] = 0; beep_voice.step[2] = 1;
    snd_play(&beep_voice);
    timer_delay_ms(ms);
    snd_stop(3);
}

/* ---- Interrupciones */
static volatile uint16_t vbl_count;
static volatile uint8_t  vbl_flag;
static void on_vblank(void) { vbl_count++; vbl_flag = 1; }

/* ---- Reloj de la linea de estado (desde el idle de la consola) */
static uint16_t last_ms, acc_ms, secs;
static void status_idle(void) {
    uint16_t now = timer_get_ms();
    acc_ms += now - last_ms;
    last_ms = now;
    if (acc_ms >= 1000) {
        acc_ms -= 1000;
        secs++;
        con_gotoxy(62, 0);
        con_puts("UPTIME ");
        con_putu(secs);
        con_puts(" s ");
    }
}

/* ---- Utilidades */
static uint8_t streq(const char* a, const char* b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

static const char* skip_word(const char* s) {
    while (*s && *s != ' ') s++;
    while (*s == ' ') s++;
    return s;
}

static uint32_t parse_hex(const char* s) {
    uint32_t v = 0;
    while (1) {
        char c = *s++;
        if (c >= '0' && c <= '9') c -= '0';
        else if (c >= 'a' && c <= 'f') c -= 'a' - 10;
        else if (c >= 'A' && c <= 'F') c -= 'A' - 10;
        else return v;
        v = (v << 4) | (uint8_t)c;
    }
}

static void word(char* dst, const char* src, uint8_t max) {
    uint8_t n = 0;
    while (*src && *src != ' ' && n + 1 < max) {
        char c = *src++;
        if (c >= 'A' && c <= 'Z') c += 32;
        dst[n++] = c;
    }
    dst[n] = 0;
}

/* ---- Ordenes */
static void cmd_help(void) {
    con_puts("HELP          esta ayuda\n");
    con_puts("CLS           borra la consola\n");
    con_puts("TIME          milisegundos y VBlanks\n");
    con_puts("BEEP          pitido por la Magic Sound 2\n");
    con_puts("PLAY          musica a cuatro canales por la Magic Sound 2\n");
    con_puts("STOP          para la musica\n");
    con_puts("DUMP dir      64 bytes de memoria fisica (direccion hex de 24 bits)\n");
    con_puts("KEYS          matriz del teclado (ESC sale)\n");
    con_puts("DEMO          bloque que rebota con el blitter (una tecla sale)\n");
}

static void cmd_time(void) {
    con_puts("ms: "); con_putu(timer_get_ms());
    con_puts("  VBlanks: "); con_putu(vbl_count);
    con_putc('\n');
}

/* Memoria fisica: la DMA la copia a un bufer de la BIOS */
static uint8_t dump_buf[64];
static void cmd_dump(const char* arg) {
    uint32_t a = parse_hex(arg);
    uint8_t i, j;
    dma_copy(a, dma_phys(dump_buf), sizeof(dump_buf));
    for (i = 0; i < 64; i += 16) {
        uint32_t la = a + i;
        con_puthex((uint8_t)(la >> 16)); con_puthex((uint8_t)(la >> 8)); con_puthex((uint8_t)la);
        con_putc(' ');
        for (j = 0; j < 16; j++) { con_putc(' '); con_puthex(dump_buf[i + j]); }
        con_puts("  ");
        for (j = 0; j < 16; j++) {
            uint8_t c = dump_buf[i + j];
            con_putc(c >= 0x20 && c < 0x7F ? c : '.');
        }
        con_putc('\n');
    }
}

static void cmd_keys(void) {
    uint8_t y, r, b;
    con_puts("Filas 0-10 de la matriz (1 = pulsada). ESC sale.\n");
    if (con_gety() > CON_ROWS - 12) con_clear();
    y = con_gety();
    while (1) {
        for (r = 0; r <= 10; r++) {
            uint8_t v = ~kbd_row(r);
            con_gotoxy(0, y + r);
            con_putu(r); con_puts(r < 10 ? "  " : " ");
            for (b = 0; b < 8; b++) con_putc((v & (0x80 >> b)) ? '1' : '0');
        }
        status_idle();
        if (kbd_hit() && kbd_getc() == KBD_ESC) break;
    }
    con_gotoxy(0, y + 11);
}

#define BALL_W 4
#define BALL_H 24
static uint8_t ball[BALL_W * BALL_H];
static void cmd_demo(void) {
    uint8_t y, x;
    uint8_t top = 2 * 8, bot = 199;
    for (y = 0; y < BALL_H; y++)
        for (x = 0; x < BALL_W; x++)
            ball[y * BALL_W + x] = (y == 0 || y == BALL_H - 1) ? 0xFF :
                                   (x == 0) ? (0x80 | ((y & 2) ? 0x55 : 0x2A)) :
                                   (x == BALL_W - 1) ? (0x01 | ((y & 2) ? 0x54 : 0xAA)) :
                                   ((y & 2) ? 0x55 : 0xAA);
    con_clear();
    {
        uint32_t bp = dma_phys(ball);
        int16_t bx = 0, by = top, dx = 1, dy = 1;
        while (!kbd_hit()) {
            while (!vbl_flag) ;
            vbl_flag = 0;
            dma_rect(0, VRAM_PHYS + (uint16_t)by * VRAM_STRIDE + bx, BALL_W, BALL_H, 0, VRAM_STRIDE, DMA_MODE_FILL, 0x00);
            bx += dx; by += dy;
            if (bx <= 0 || bx >= VRAM_STRIDE - BALL_W) dx = -dx;
            if (by <= top || by >= bot - BALL_H) dy = -dy;
            dma_rect(bp, VRAM_PHYS + (uint16_t)by * VRAM_STRIDE + bx, BALL_W, BALL_H, BALL_W, VRAM_STRIDE, DMA_MODE_COPY, 0);
            status_idle();
        }
        kbd_getc();
    }
    con_clear();
}

static char line[64];

void main(void) {
    uint8_t ok;

    mmu_install();
    crtc_install();
    vbuf_activate_driver(&_drv_16k1b_vtable);
    vbuf_init();
    palette_activate_12bit();
    palette_install();
    palette_set_color_12b(0, 0x0026);   /* fondo: azul oscuro */
    palette_set_color_12b(1, 0x0FFF);   /* tinta: blanco */

    int_activate_lx();
    timer_activate_lx();
    dma_activate_lx();
    kbd_activate_lx();
    snd_activate_ms2();
    ok = int_detect() && timer_detect() && dma_detect() && kbd_detect() && snd_detect();
    if (!ok) {
        vbuf_clear(0x00);
        vbuf_draw_char(&_scr_font_data, '?', 0, 0);
        while (1) ;                     /* sin los perifericos del modo LX */
    }
    int_install();
    timer_install();
    dma_install();
    kbd_install();
    snd_install();
    int_set_handler(INT_LINE_VBLANK, on_vblank);
    int_enable(INT_LINE_VBLANK);

    con_init();
    con_puts("ALESTE LX BIOS - MiSTer");
    dma_fill(VRAM_PHYS + 11 * VRAM_STRIDE, 0xFF, VRAM_STRIDE);   /* raya bajo el titulo */
    con_set_window(2, CON_ROWS - 1);
    con_puts("Drivers: INT (PIC LX), TIMER, DMA (blitter), KBD (PS/2), SND (Magic Sound 2)\n");
    last_ms = timer_get_ms();
    con_set_idle(status_idle);
    beep(150);
    con_puts("Escribe HELP para ver las ordenes.\n\n");

    while (1) {
        char cmd[8];
        const char* arg;
        con_puts("LX> ");
        con_gets(line, sizeof(line));
        word(cmd, line, sizeof(cmd));
        arg = skip_word(line);
        if (!cmd[0]) continue;
        if (streq(cmd, "help")) cmd_help();
        else if (streq(cmd, "cls")) con_clear();
        else if (streq(cmd, "time")) cmd_time();
        else if (streq(cmd, "beep")) beep(150);
        else if (streq(cmd, "play")) { tune_start(); con_puts("Himno de la alegria (Beethoven). STOP para parar.\n"); }
        else if (streq(cmd, "stop")) tune_stop();
        else if (streq(cmd, "dump")) cmd_dump(arg);
        else if (streq(cmd, "keys")) cmd_keys();
        else if (streq(cmd, "demo")) cmd_demo();
        else { con_puts("No conozco esa orden: "); con_puts(cmd); con_putc('\n'); }
    }
}
