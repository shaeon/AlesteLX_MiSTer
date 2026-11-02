/*
 * bdos.c - Programas .COM en el LX-DOS: carga, pagina cero, BDOS y BIOS de
 * CP/M 2.2 (y lo comun de MSX-DOS 1)
 * Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
 *
 * El programa va en los bancos 24h-26h del slot 3 (fisica C90000-C9BFFF), que
 * __dos_exec (bios/dosgate.asm, en la ventana 3 de la ROM) pone en las
 * ventanas 0-2; el LX-DOS lo ve solo por la DMA (fisica = TPA_PHYS + dir).
 *
 *   0000h  JP BF06h (WBOOT del BIOS)     0005h  JP BF00h (BDOS)
 *   0038h  JP __dos_isr_gate             005Ch/006Ch  FCB 1 y 2
 *   0080h  linea de ordenes              0100h  el programa
 *   BF00h  JP __dos_bdos_gate            BF03h  tabla del BIOS de CP/M
 *   BF40h  una entrada por funcion del BIOS: LD A,n / JP __dos_bios_gate
 * La TPA llega hasta BF00h (lo que dice 0006h) y la pila empieza ahi.
 *
 * Fase 2: consola. Las funciones de ficheros (15-40) devuelven error (FFh)
 * hasta la fase siguiente.
 */
#include <stdint.h>
#include "drivers/dma.h"
#include "drivers/kbd.h"
#include "console.h"
#include "fat.h"
#include "bdos.h"

#define TPA_PHYS  0xC90000UL
#define TPA_TOP   0xBF00
#define BIOS_TAB  0xBF03
#define BIOS_STUB 0xBF40
#define BIOS_N    17

/* Puertas y registros de bios/dosgate.asm (ROM, ventana 3) */
extern uint8_t  _dos_reg_c, _dos_reg_a;
extern uint16_t _dos_reg_de;
extern uint16_t _dos_bdos_vec, _dos_bios_vec;
extern uint8_t  _dos_bdos_gate[], _dos_bios_gate[], _dos_isr_gate[];

uint8_t dos_drive;                  /* 0 = A:, 1 = B: */
static uint16_t dma_addr = 0x80;

/* ---- memoria del programa por la DMA */
static void to_tpa(uint16_t a, const void* p, uint16_t n) { dma_copy(dma_phys(p), TPA_PHYS + a, n); }
static void from_tpa(uint16_t a, void* p, uint16_t n)     { dma_copy(TPA_PHYS + a, dma_phys(p), n); }

/* ---- consola */
static void out_char(uint8_t c) {
    if (c >= 0x20 || c == '\r' || c == '\n' || c == '\b' || c == '\t') con_putc(c);
    else if (c == 0x0C) con_clear();            /* salto de pagina: borra */
}

static void print_dollar(uint16_t a) {
    static uint8_t chunk[32];
    uint16_t n = 0;
    while (n < 4096) {
        uint8_t i;
        from_tpa(a + n, chunk, sizeof(chunk));
        for (i = 0; i < sizeof(chunk); i++) {
            if (chunk[i] == '$') return;
            out_char(chunk[i]);
        }
        n += sizeof(chunk);
    }
}

/* Funcion 10: buffer = [maximo][longitud][caracteres]. Como CP/M, no pasa de
   linea al terminar. */
static void read_line(uint16_t a) {
    static uint8_t buf[256];
    uint8_t max, n = 0;
    from_tpa(a, &max, 1);
    while (1) {
        uint8_t c = (uint8_t)con_getc();
        if (c == '\r' || c == '\n') break;
        if (c == '\b' || c == 0x7F) { if (n) { n--; con_putc('\b'); } continue; }
        if (c == 0x03 && n == 0) break;            /* ^C con la linea vacia */
        if (c >= 0x20 && c < 0x7F && n < max) { buf[2 + n++] = c; con_putc(c); }
    }
    con_putc('\r');
    buf[1] = n;
    to_tpa(a + 1, buf + 1, n + 1);
}

/* ---- BDOS: C = funcion, DE = parametro -> HL (A = L, B = H) */
static uint16_t bdos_c(void) {
    uint8_t  fn = _dos_reg_c;
    uint16_t de = _dos_reg_de;
    uint8_t  e  = (uint8_t)de;
    switch (fn) {
    case 1:  { uint8_t c = (uint8_t)con_getc(); out_char(c); return c; }
    case 2:  out_char(e); return 0;
    case 6:
        if (e == 0xFF) return kbd_hit() ? kbd_getc() : 0;
        if (e == 0xFE) return kbd_hit() ? 0xFF : 0;
        if (e == 0xFD) return kbd_getc();
        out_char(e); return 0;
    case 7:  return 0x1A;                       /* lector: fin de fichero */
    case 8:  return 0;                          /* perforadora */
    case 9:  print_dollar(de); return 0;
    case 10: read_line(de); return 0;
    case 11: return kbd_hit() ? 0xFF : 0;
    case 12: return 0x0022;                     /* CP/M 2.2 */
    case 13: dma_addr = 0x80; return 0;
    case 14: dos_drive = e & 1; return 0;
    case 24: return 0x0003;                     /* unidades A: y B: */
    case 25: return dos_drive;
    case 26: dma_addr = de; return 0;
    case 32: return 0;                          /* numero de usuario */
    default:
        if (fn >= 15 && fn <= 40) return 0xFF;  /* ficheros: en la fase siguiente */
        return 0;
    }
}

/* ---- BIOS de CP/M: A = funcion, C = caracter */
static uint16_t bios_c(void) {
    switch (_dos_reg_a) {
    case 2:  return kbd_hit() ? 0xFF : 0;       /* CONST */
    case 3:  return (uint8_t)con_getc();        /* CONIN (sin eco) */
    case 4:  out_char(_dos_reg_c); return 0;    /* CONOUT */
    case 7:  return 0x1A;                       /* READER */
    default: return 0;
    }
}

/* ---- ejecucion */
static void exec_asm(void) __naked {
    __asm
        EXTERN __dos_exec
        push ix
        push iy
        call __dos_exec             ; vuelve cuando el programa acaba
        pop iy
        pop ix
        ret
    __endasm;
}

static uint8_t up(uint8_t c) { return (c >= 'a' && c <= 'z') ? c - 32 : c; }

/* NOMBRE.EXT -> FCB (unidad, 8 + 3 con espacios) */
static void make_fcb(uint8_t* f, const char* s) {
    uint8_t i;
    for (i = 0; i < 11; i++) f[1 + i] = ' ';
    f[0] = 0;
    if (s[0] && s[1] == ':') { f[0] = up(s[0]) - 'A' + 1; s += 2; }
    for (i = 0; *s && *s != '.' && *s != ' '; s++) if (i < 8) f[1 + i++] = up(*s);
    if (*s == '.') for (s++, i = 0; *s && *s != ' '; s++) if (i < 3) f[9 + i++] = up(*s);
}

static uint8_t zero[256];
static uint8_t top[BIOS_STUB - TPA_TOP + 5 * BIOS_N];

uint8_t dos_run(const char* name, const char* args) {
    char fname[13];
    fat_entry_t e;
    uint8_t i, r, dot = 0;
    uint16_t a;

    /* NOMBRE -> NOMBRE.COM */
    for (i = 0; name[i] && i < 8 + 4; i++) { fname[i] = up(name[i]); if (name[i] == '.') dot = 1; }
    fname[i] = 0;
    if (!dot) {
        if (i > 8) return DOS_RUN_NOTFOUND;
        fname[i++] = '.'; fname[i++] = 'C'; fname[i++] = 'O'; fname[i++] = 'M'; fname[i] = 0;
    }
    r = fat_mount(dos_drive);
    if (r) return DOS_RUN_DISK;
    if (fat_find(fname, &e)) return DOS_RUN_NOTFOUND;
    if (e.size > TPA_TOP - 0x100 - 2) return DOS_RUN_TOOBIG;
    if (fat_load(&e, TPA_PHYS + 0x100, 0)) return DOS_RUN_DISK;

    /* pagina cero */
    for (a = 0; a < sizeof(zero); a++) zero[a] = 0;
    zero[0] = 0xC3; zero[1] = (uint8_t)(BIOS_TAB + 3); zero[2] = (BIOS_TAB + 3) >> 8;
    zero[4] = dos_drive;
    zero[5] = 0xC3; zero[6] = (uint8_t)TPA_TOP; zero[7] = TPA_TOP >> 8;
    zero[0x38] = 0xC3; zero[0x39] = (uint8_t)(uint16_t)_dos_isr_gate; zero[0x3A] = (uint16_t)_dos_isr_gate >> 8;
    {
        const char* a2 = args;
        while (*a2 == ' ') a2++;
        make_fcb(&zero[0x5C], a2);
        while (*a2 && *a2 != ' ') a2++;
        while (*a2 == ' ') a2++;
        make_fcb(&zero[0x6C], a2);
        /* linea de ordenes: " ARGUMENTOS" en mayusculas */
        i = 0;
        if (*args) {
            zero[0x81] = ' '; i = 1;
            while (*args == ' ') args++;
            while (*args && i < 126) zero[0x81 + i++] = up(*args++);
        }
        zero[0x80] = i;
    }
    to_tpa(0, zero, sizeof(zero));

    /* BDOS, tabla del BIOS y sus entradas, arriba de la TPA */
    top[0] = 0xC3; top[1] = (uint8_t)(uint16_t)_dos_bdos_gate; top[2] = (uint16_t)_dos_bdos_gate >> 8;
    for (i = 0; i < BIOS_N; i++) {
        uint16_t stub = BIOS_STUB + 5 * i;
        uint8_t* t = &top[3 + 3 * i];
        uint8_t* s = &top[BIOS_STUB - TPA_TOP + 5 * i];
        t[0] = 0xC3; t[1] = (uint8_t)stub; t[2] = stub >> 8;
        s[0] = 0x3E; s[1] = i;                      /* LD A,n */
        s[2] = 0xC3; s[3] = (uint8_t)(uint16_t)_dos_bios_gate; s[4] = (uint16_t)_dos_bios_gate >> 8;
    }
    to_tpa(TPA_TOP, top, sizeof(top));

    _dos_bdos_vec = (uint16_t)bdos_c;
    _dos_bios_vec = (uint16_t)bios_c;
    dma_addr = 0x80;
    exec_asm();
    if (con_getx()) con_putc('\n');
    return DOS_RUN_OK;
}
