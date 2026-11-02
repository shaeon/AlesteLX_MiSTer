/*
 * LX-DOS - sistema de disco del Aleste LX (LXDOS.SYS)
 * Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
 *
 * La ROM lo carga de la unidad A en las ventanas 0 y 1 del supervisor y salta
 * a 0000h. Usa los drivers residentes de la ROM (ventana 3) por sus
 * direcciones fijas (lx/build/bios_abi.asm). Interprete de ordenes y
 * programas .COM de CP/M / MSX-DOS 1 (bdos.c; por ahora, solo la consola).
 * Los textos que ve el usuario van en ingles.
 */
#include <stdint.h>
#include "drivers/int.h"
#include "drivers/timer.h"
#include "drivers/dma.h"
#include "drivers/kbd.h"
#include "drivers/snd.h"
#include "drivers/fdc.h"
#include "console.h"
#include "fat.h"
#include "bdos.h"

#define LXDOS_VERSION "0.2"
#define VRAM_PHYS   0xC40000UL
#define VRAM_STRIDE 80

#define drive dos_drive         /* unidad actual (bdos.c) */
static char line[80];

/* ---- vuelta a la ROM (monitor) */
static void to_rom(void) __naked {
    __asm
        EXTERN __boot_rom
        jp __boot_rom
    __endasm;
}

/* ---- utilidades */
static uint8_t lower(uint8_t c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }
static uint8_t upper(uint8_t c) { return (c >= 'a' && c <= 'z') ? c - 32 : c; }

static uint8_t streq(const char* a, const char* b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

static const char* skip_word(const char* s) {
    while (*s && *s != ' ') s++;
    while (*s == ' ') s++;
    return s;
}

static void word(char* dst, const char* src, uint8_t max, uint8_t to_lower) {
    uint8_t n = 0;
    while (*src && *src != ' ' && n + 1 < max) {
        uint8_t c = *src++;
        dst[n++] = to_lower ? lower(c) : upper(c);
    }
    dst[n] = 0;
}

static void disk_error(uint8_t r) {
    if (r == FAT_ERR_DISK)        { con_puts("Disk error in drive "); con_putc('A' + drive); con_puts(": (no disk?)\n"); }
    else if (r == FAT_ERR_FORMAT) con_puts("Not an MSX-DOS (FAT12) disk.\n");
    else if (r == FAT_ERR_NOFILE) con_puts("File not found.\n");
}

static uint8_t mount(void) {
    uint8_t r = fat_mount(drive);
    if (r) disk_error(r);
    return r == FAT_OK;
}

/* ---- DIR */
static uint8_t dir_n;
static uint32_t dir_total;
static uint8_t dir_cb(const fat_entry_t* e) {
    uint8_t i;
    con_puts(e->name);
    for (i = 0; e->name[i]; i++) ;
    for (; i < 13; i++) con_putc(' ');
    if (e->attr & 0x10) con_puts("  <DIR>");
    else { con_putu((uint16_t)((e->size + 1023) >> 10)); con_puts("K"); }
    if (++dir_n % 3) { uint8_t x = con_getx(); uint8_t to = (dir_n % 3) * 26; while (x < to) { con_putc(' '); x++; } }
    else con_putc('\n');
    dir_total += e->size;
    return 0;
}

static void cmd_dir(void) {
    if (!mount()) return;
    dir_n = 0; dir_total = 0;
    fat_dir(dir_cb);
    if (dir_n % 3) con_putc('\n');
    con_putu(dir_n); con_puts(" files, ");
    con_putu((uint16_t)(dir_total >> 10)); con_puts("K; ");
    con_putu(fat_free_kb()); con_puts("K free\n");
}

/* ---- TYPE: el fichero a 010000 (fisica, RAM libre) y de ahi a la consola */
#define TYPE_PHYS 0x010000UL
static uint8_t tbuf[128];
static void cmd_type(const char* arg) {
    char name[13];
    fat_entry_t e;
    uint32_t pos;
    uint8_t r;
    if (!*arg) { con_puts("TYPE file\n"); return; }
    word(name, arg, sizeof(name), 0);
    if (!mount()) return;
    r = fat_find(name, &e);
    if (!r && e.size > 0x30000UL) { con_puts("File too big.\n"); return; }
    if (!r) r = fat_load(&e, TYPE_PHYS, 0);
    if (r) { disk_error(r); return; }
    for (pos = 0; pos < e.size; pos += sizeof(tbuf)) {
        uint8_t n = (e.size - pos) > sizeof(tbuf) ? sizeof(tbuf) : (uint8_t)(e.size - pos), i;
        dma_copy(TYPE_PHYS + pos, dma_phys(tbuf), n);
        for (i = 0; i < n; i++) {
            uint8_t c = tbuf[i];
            if (c == 0x1A) return;                       /* fin de texto de CP/M */
            if (c == '\r') continue;
            if (c == '\n' || c == '\t' || (c >= 0x20 && c < 0x7F)) con_putc(c);
        }
        if (kbd_hit() && kbd_getc() == KBD_ESC) { con_puts("\n^C\n"); return; }
    }
    if (con_getx()) con_putc('\n');
}

static void cmd_help(void) {
    con_puts("A: B:              select the current drive\n");
    con_puts("DIR                list the files on the current drive\n");
    con_puts("TYPE file          show a text file (ESC stops)\n");
    con_puts("CLS                clear the screen\n");
    con_puts("VER                LX-DOS version\n");
    con_puts("MONITOR            back to the ROM monitor\n");
    con_puts("HELP               this help\n");
    con_puts("name [args]        run NAME.COM (CP/M / MSX-DOS 1; console only for now)\n");
}

static void cmd_ver(void) {
    con_puts("LX-DOS " LXDOS_VERSION " for the Aleste LX (MiSTer)\n");
}

/* ---- reloj de la linea de estado */
static uint16_t last_ms, acc_ms, secs;
static void status_idle(void) {
    uint8_t x = con_getx(), y = con_gety();
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
        con_gotoxy(x, y);
    }
}

void main(void) {
    /* los drivers siguen instalados; se reinstalan los que tenian rutinas de
       la ROM (interrupciones) y los que dependen de ellas */
    int_install();
    kbd_install();
    snd_install();
    dma_install();

    con_init();
    con_puts("LX-DOS " LXDOS_VERSION " - Aleste LX");
    dma_fill(VRAM_PHYS + 11 * VRAM_STRIDE, 0xFF, VRAM_STRIDE);
    con_set_window(2, CON_ROWS - 1);
    con_puts("Loaded from drive A:. Type HELP for the list of commands.\n\n");
    last_ms = timer_get_ms();
    con_set_idle(status_idle);

    while (1) {
        char cmd[10];
        const char* arg;
        con_putc('A' + drive);
        con_puts("> ");
        con_gets(line, sizeof(line));
        word(cmd, line, sizeof(cmd), 1);
        arg = skip_word(line);
        if (!cmd[0]) continue;
        if (cmd[1] == ':' && cmd[2] == 0 && (cmd[0] == 'a' || cmd[0] == 'b')) {
            drive = cmd[0] - 'a';
            continue;
        }
        if (streq(cmd, "dir")) cmd_dir();
        else if (streq(cmd, "type")) cmd_type(arg);
        else if (streq(cmd, "cls")) con_clear();
        else if (streq(cmd, "ver")) cmd_ver();
        else if (streq(cmd, "help")) cmd_help();
        else if (streq(cmd, "monitor")) to_rom();
        else {
            char name[13];
            uint8_t r;
            word(name, line, sizeof(name), 0);
            r = dos_run(name, arg);
            if (r == DOS_RUN_NOTFOUND) con_puts("Bad command or file name\n");
            else if (r == DOS_RUN_TOOBIG) con_puts("Program too big\n");
            else if (r == DOS_RUN_DISK) disk_error(FAT_ERR_DISK);
        }
    }
}
