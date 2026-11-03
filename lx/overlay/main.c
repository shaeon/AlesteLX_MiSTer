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
#include "drivers/palette.h"
#include "drivers/int.h"
#include "drivers/timer.h"
#include "drivers/dma.h"
#include "drivers/kbd.h"
#include "drivers/snd.h"
#include "tune.h"
#include "mod.h"
#include "drivers/fdc.h"
#include "fat.h"
#include "console.h"

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
        if (mod_playing()) {
            con_gotoxy(36, 0);
            con_puts(mod_kind()); con_putc(' ');
            con_puthex(mod_position()); con_putc('/'); con_puthex(mod_length());
            con_puts(" row "); con_puthex(mod_row()); con_puts("   ");
        } else {
            con_gotoxy(36, 0);
            con_puts("                    ");
        }
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
    con_puts("HELP              this help\n");
    con_puts("CLS               clear the console\n");
    con_puts("TIME              milliseconds and VBlanks\n");
    con_puts("BEEP              beep on the Magic Sound 2\n");
    con_puts("KEYB [US|ES]      keyboard layout (the OSD sets it at boot)\n");
    con_puts("PLAY              four-channel tune on the Magic Sound 2\n");
    con_puts("DIR               files on the disk in drive A (MSX-DOS, 720 KB)\n");
    con_puts("LOAD file [addr]  load a file from disk into physical memory (000000)\n");
    con_puts("MOD [file/addr]   play a MOD or STM from disk, or from physical memory\n");
    con_puts("                  (000000: the one loaded with \"Load MOD\" in the OSD)\n");
    con_puts("STOP              stop the music\n");
    con_puts("DUMP addr         64 bytes of physical memory (24-bit hex address)\n");
    con_puts("KEYS              keyboard matrix (ESC exits)\n");
    con_puts("DEMO              bouncing block drawn by the blitter (any key exits)\n");
    con_puts("BOOT              boot LXDOS.SYS from the disk in drive A\n");
    con_puts("520EX             start the Aleste 520EX compatible mode (AlesteDOS,\n");
    con_puts("                  MSX-DOS and CPC software); OSD reset returns here\n");
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
    con_puts("Matrix rows 0-10 (1 = pressed). ESC exits.\n");
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

/* ---- Disco */
static void disk_error(uint8_t r) {
    if (r == FAT_ERR_DISK)        con_puts("Disk error: mount a 720 KB image in the OSD (Mount Drive A:).\n");
    else if (r == FAT_ERR_FORMAT) con_puts("Not an MSX-DOS (FAT12) disk.\n");
    else if (r == FAT_ERR_NOFILE) con_puts("File not found.\n");
}

static uint8_t dir_n;
static uint32_t dir_total;
static uint8_t dir_cb(const fat_entry_t* e) {
    uint8_t i;
    con_puts(e->name);
    for (i = 0; e->name[i]; i++) ;
    for (; i < 13; i++) con_putc(' ');
    if (e->attr & 0x10) con_puts("  <DIR>");
    else { con_putu((uint16_t)((e->size + 1023) >> 10)); con_puts(" KB"); }
    con_putc((++dir_n & 1) ? '\t' : '\n');
    if (dir_n & 1) { uint8_t x = con_getx(); while (x < 40) { con_putc(' '); x++; } }
    dir_total += e->size;
    return 0;
}

static void cmd_dir(void) {
    uint8_t r = fat_mount(0);
    if (r) { disk_error(r); return; }
    dir_n = 0; dir_total = 0;
    fat_dir(dir_cb);
    if (dir_n & 1) con_putc('\n');
    con_putu(dir_n); con_puts(" files, ");
    con_putu((uint16_t)(dir_total >> 10)); con_puts(" KB; ");
    con_putu(fat_free_kb()); con_puts(" KB free\n");
}

static void progress(uint16_t kb) {
    con_putc('\r'); con_puts("  "); con_putu(kb); con_puts(" KB");
}

/* Carga 'name' del disco en 'phys'; 1 si va bien */
static uint8_t load_file(const char* name, uint32_t phys) {
    fat_entry_t e;
    uint8_t r = fat_mount(0);
    if (!r) r = fat_find(name, &e);
    if (!r) {
        con_puts("Loading "); con_puts(e.name); con_puts(" at ");
        con_puthex((uint8_t)(phys >> 16)); con_puthex((uint8_t)(phys >> 8)); con_puthex((uint8_t)phys);
        con_puts(" ("); con_putu((uint16_t)((e.size + 1023) >> 10)); con_puts(" KB)\n");
        r = fat_load(&e, phys, progress);
        con_putc('\r'); con_puts("         \r");
    }
    if (r) { disk_error(r); return 0; }
    return 1;
}

static uint8_t has_dot(const char* a) {
    while (*a && *a != ' ') if (*a++ == '.') return 1;
    return 0;
}

static void first_word(char* dst, const char* src, uint8_t max) {
    uint8_t n = 0;
    while (*src && *src != ' ' && n + 1 < max) dst[n++] = *src++;
    dst[n] = 0;
}

static void cmd_load(const char* arg) {
    char name[13];
    const char* rest;
    if (!*arg) { con_puts("LOAD file [address]\n"); return; }
    first_word(name, arg, sizeof(name));
    rest = skip_word(arg);
    load_file(name, *rest ? parse_hex(rest) : 0);
}

static void cmd_mod(const char* arg) {
    uint32_t a = 0;
    tune_stop();
    mod_stop();
    if (*arg && has_dot(arg)) {
        char name[13];
        first_word(name, arg, sizeof(name));
        if (!load_file(name, 0)) return;
    } else if (*arg) a = parse_hex(arg);
    if (mod_load(a) != MOD_OK) {
        con_puts("No 4-channel MOD or STM at ");
        con_puthex((uint8_t)(a >> 16)); con_puthex((uint8_t)(a >> 8)); con_puthex((uint8_t)a);
        con_puts(" (load one with \"Load MOD\" in the OSD, or MOD FILE.STM).\n");
        return;
    }
    con_puts(mod_kind()); con_puts(" \""); con_puts(mod_title()); con_puts("\": ");
    con_putu(mod_length()); con_puts(" positions, ");
    con_putu(mod_patterns()); con_puts(" patterns. STOP to stop.\n");
    mod_play();
}

/* ---- Modo compatible Aleste 520EX
   boot.rom = LX.ROM + AL512.BIN: el cargador deja AL512 en 400000, donde la
   busca el modo legacy (CPC/520EX). Se hace lo mismo que el arranque del core
   del 520EX (BOOT520): LD BC,7F89h; XOR A; y en FFFEh OUT (0F0h),A, que pasa
   la MMU a modo legacy; la CPU da la vuelta a 0000h y sigue en la ROM baja
   del 520EX como tras un reset. El reset del OSD vuelve al LX. */
#define AL512_PHYS 0x400000UL
static void jump_520ex(void) __naked {
    __asm
        di
        ld a, #0xD3             ; OUT (0F0h),A en FFFEh
        ld (0xFFFE), a
        ld a, #0xF0
        ld (0xFFFF), a
        ld bc, #0x7F89
        xor a
        jp 0xFFFE
    __endasm;
}

static uint8_t al512_hdr[4];
static void cmd_520ex(void) {
    dma_copy(AL512_PHYS, dma_phys(al512_hdr), sizeof(al512_hdr));
    if (al512_hdr[0] != 0x01 || al512_hdr[1] != 0x89 || al512_hdr[2] != 0x7F) {
        con_puts("Aleste 520EX ROM not found at 400000: boot.rom must be\n");
        con_puts("LX.ROM followed by AL512.BIN (copy /b LX.ROM + AL512.BIN boot.rom).\n");
        return;
    }
    con_puts("Starting the Aleste 520EX (OSD reset returns to the LX)...\n");
    timer_delay_ms(300);
    tune_stop();
    mod_stop();
    snd_uninstall();
    timer_uninstall();
    kbd_uninstall();
    dma_wait();
    int_uninstall();
    jump_520ex();
}

/* ---- Arranque del sistema del disco (LXDOS.SYS)
   Se carga en el slot 3, bancos 20h-22h (C80000, hasta 44 KB: la pila va arriba) y
   __boot_jump (bios/boot.asm, residente) lo pone en las ventanas 0 y 1 y
   salta a 0000h. Vuelve si no hay disco o no esta el fichero. */
#define SYS_PHYS 0xC80000UL
#define SYS_MAX  0xB000UL
static void boot_jump_asm(void) __naked {
    __asm
        EXTERN __boot_jump
        jp __boot_jump
    __endasm;
}

static uint8_t try_boot(uint8_t verbose) {
    fat_entry_t e;
    uint8_t r = fat_mount(0);
    if (!r) r = fat_find("LXDOS.SYS", &e);
    if (r) {
        if (verbose) disk_error(r);
        return 0;
    }
    if (e.size == 0 || e.size > SYS_MAX) { con_puts("LXDOS.SYS is too big (44 KB max).\n"); return 0; }
    con_puts("Booting LXDOS.SYS...\n");
    tune_stop();
    mod_stop();
    if (fat_load(&e, SYS_PHYS, 0)) { con_puts("Disk error while loading LXDOS.SYS.\n"); return 0; }
    int_uninstall();                    /* las rutinas de la ROM dejan de valer */
    timer_uninstall();
    snd_uninstall();
    dma_wait();
    boot_jump_asm();
    return 1;
}

/* ---- KEYB [US|ES]: distribucion del teclado (la del OSD al arrancar) */
static void cmd_keyb(const char* arg) {
    char a = arg[0] | 0x20, b = arg[1] | 0x20;
    if (a == 'e' && b == 's') kbd_set_layout(KBD_LAYOUT_ES);
    else if (a == 'u' && b == 's') kbd_set_layout(KBD_LAYOUT_US);
    else if (*arg) { con_puts("KEYB [US|ES]\n"); return; }
    con_puts("Keyboard: ");
    con_puts(kbd_get_layout() == KBD_LAYOUT_ES ? "Spanish (ES)\n" : "US\n");
}

static char line[64];

void main(void) {
    uint8_t ok;

    mmu_install();
    crtc_install();
    crtc_set_mode(3);                   /* 640x200, 1 bit, lineal, video en C40000 */
    palette_activate_12bit();
    palette_install();
    palette_set_color_12b(0, 0x0026);   /* fondo: azul oscuro */
    palette_set_color_12b(1, 0x0FFF);   /* tinta: blanco */

    int_activate_lx();
    timer_activate_lx();
    dma_activate_lx();
    kbd_activate_lx();
    snd_activate_ms2();
    fdc_activate_765();
    ok = int_detect() && timer_detect() && dma_detect() && kbd_detect() && snd_detect() && fdc_detect();
    if (!ok) {
        while (1) ;                     /* sin los perifericos del modo LX */
    }
    int_install();
    timer_install();
    dma_install();
    kbd_install();
    snd_install();
    fdc_install();
    int_set_handler(INT_LINE_VBLANK, on_vblank);
    int_enable(INT_LINE_VBLANK);

    con_init();
    con_puts("ALESTE LX BIOS - MiSTer");
    dma_fill(VRAM_PHYS + 11 * VRAM_STRIDE, 0xFF, VRAM_STRIDE);   /* raya bajo el titulo */
    con_set_window(2, CON_ROWS - 1);
    con_puts("Drivers: INT (PIC LX), TIMER, DMA (blitter), KBD (PS/2), SND (MS2), FDC\n");
    last_ms = timer_get_ms();
    con_set_idle(status_idle);
    beep(150);
    if (!try_boot(0)) con_puts("No system disk in drive A.\n");
    con_puts("Type HELP for the list of commands.\n\n");

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
        else if (streq(cmd, "keyb")) cmd_keyb(arg);
        else if (streq(cmd, "mod")) cmd_mod(arg);
        else if (streq(cmd, "dir")) cmd_dir();
        else if (streq(cmd, "520ex")) cmd_520ex();
        else if (streq(cmd, "boot")) try_boot(1);
        else if (streq(cmd, "load")) cmd_load(arg);
        else if (streq(cmd, "play")) { mod_stop(); tune_start(); con_puts("Ode to Joy (Beethoven). STOP to stop.\n"); }
        else if (streq(cmd, "stop")) { tune_stop(); mod_stop(); }
        else if (streq(cmd, "dump")) cmd_dump(arg);
        else if (streq(cmd, "keys")) cmd_keys();
        else if (streq(cmd, "demo")) cmd_demo();
        else { con_puts("Unknown command: "); con_puts(cmd); con_putc('\n'); }
    }
}
