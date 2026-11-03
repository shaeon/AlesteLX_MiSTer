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
 * Ficheros por FCB (CP/M 2.2): abrir, cerrar, buscar, borrar, leer y
 * escribir secuencial y aleatorio, crear, renombrar, tamano. El estado del
 * fichero abierto va en los bytes 16-31 del FCB (reservados para el DOS), en
 * los sitios de MSX-DOS 1: 16-19 tamano, 24 marcas, 25 entrada del
 * directorio, 26-27 primer cluster.
 *
 * Funciones de MSX-DOS 1 ademas de las de CP/M: 07h/08h (entrada sin eco),
 * 1Bh (asignacion del disco), 26h/27h (bloques con tamano de registro en los
 * bytes 14-15 del FCB y registro aleatorio de 4 bytes en 33-36), 2Ah-2Dh
 * (fecha y hora, del reloj MC146818 en FF0060/61), 2Eh (verificacion) y
 * 2Fh/30h (sectores absolutos). Las que devuelven varios registros a la vez
 * los dejan en __dos_ret_* (vuelta completa de la pasarela).
 */
#include <stdint.h>
#include "drivers/dma.h"
#include "drivers/kbd.h"
#include "console.h"
#include "fat.h"
#include "bdos.h"
#include "mod.h"

static uint8_t music_play(uint16_t a);
static void    music_info(uint16_t a);

#define TPA_PHYS  0xC90000UL
#define TPA_TOP   0xBF00
#define BIOS_TAB  0xBF03
#define BIOS_STUB 0xBF40
#define BIOS_N    17

/* Puertas y registros de bios/dosgate.asm (ROM, ventana 3) */
extern uint8_t  _dos_reg_c, _dos_reg_a, _dos_reg_b;
extern uint16_t _dos_reg_de, _dos_reg_hl;
extern uint8_t  _dos_reg_hl_b[2];            /* el mismo HL, byte a byte (L, H) */
extern uint8_t  _dos_xret, _dos_ret_a;
extern uint16_t _dos_ret_bc, _dos_ret_de, _dos_ret_hl;
extern uint16_t _dos_bdos_vec, _dos_bios_vec;
extern uint8_t  _dos_bdos_gate[], _dos_bios_gate[], _dos_isr_gate[];

uint8_t dos_drive;                  /* 0 = A:, 1 = B: */
static uint16_t dma_addr = 0x80;

/* ---- FCB */
#define F_DR    0
#define F_NAME  1
#define F_EX    12
#define F_S2    14
#define F_RC    15
#define F_SIZE  16
#define F_FLAGS 24
#define F_DIR   25
#define F_CL    26
#define F_CR    32
#define F_R0    33
#define FL_OPEN  0x80
#define FL_DIRTY 0x01

static uint8_t fcb[37];
static int16_t search_idx = -1;
static uint8_t search_pat[11], search_drv;

/* ---- memoria del programa por la DMA */
static void to_tpa(uint16_t a, const void* p, uint16_t n) { dma_copy(dma_phys(p), TPA_PHYS + a, n); }
static void from_tpa(uint16_t a, void* p, uint16_t n)     { dma_copy(TPA_PHYS + a, dma_phys(p), n); }

static uint32_t get32(const uint8_t* p) { return p[0] | ((uint16_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static void put32(uint8_t* p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }

/* unidad del FCB (0 = la actual) y montarla */
static uint8_t fcb_drive(void) {
    uint8_t d = fcb[F_DR];
    d = (d == 0 || d == '?') ? dos_drive : (d - 1) & 1;
    return fat_use(d) == FAT_OK;
}

/* registro secuencial del FCB: (s2 * 32 + ex) * 128 + cr */
static uint32_t seq_rec(void) {
    return ((uint32_t)((fcb[F_S2] & 0x3F) * 32 + (fcb[F_EX] & 31)) << 7) | (fcb[F_CR] & 0x7F);
}

static void set_rec(uint32_t rec) {
    fcb[F_CR] = rec & 0x7F;
    fcb[F_EX] = (rec >> 7) & 31;
    fcb[F_S2] = (rec >> 12) & 0x3F;
}

/* registros de la extension actual (rc) segun el tamano */
static void update_rc(void) {
    uint32_t recs = (get32(&fcb[F_SIZE]) + 127) >> 7;
    uint32_t first = ((uint32_t)((fcb[F_S2] & 0x3F) * 32 + (fcb[F_EX] & 31))) << 7;
    fcb[F_RC] = recs <= first ? 0 : (recs - first >= 128 ? 128 : (uint8_t)(recs - first));
}

static void fcb_open_from(int16_t idx, const uint8_t* ent) {
    uint8_t k;
    for (k = 0; k < 11; k++) fcb[F_NAME + k] = ent[k];
    for (k = 0; k < 4; k++) fcb[F_SIZE + k] = ent[28 + k];
    fcb[F_FLAGS] = FL_OPEN;
    fcb[F_DIR] = (uint8_t)idx;
    fcb[F_CL] = ent[26]; fcb[F_CL + 1] = ent[27];
    update_rc();
}

static uint8_t f_open(void) {
    uint8_t ent[32];
    int16_t idx;
    if (!fcb_drive()) return 0xFF;
    idx = fat_find11(&fcb[F_NAME], 0, ent);
    if (idx < 0) return 0xFF;
    fcb[F_S2] = 0;
    fcb_open_from(idx, ent);
    return 0;
}

static uint8_t f_close(void) {
    if (!fcb_drive()) return 0xFF;
    if ((fcb[F_FLAGS] & (FL_OPEN | FL_DIRTY)) == (FL_OPEN | FL_DIRTY)) {
        if (fat_set_entry(fcb[F_DIR], fcb[F_CL] | (fcb[F_CL + 1] << 8), get32(&fcb[F_SIZE]))) return 0xFF;
        fcb[F_FLAGS] &= ~FL_DIRTY;
    }
    return fat_sync() ? 0xFF : 0;
}

static uint8_t f_make(void) {
    int16_t idx;
    uint8_t k;
    if (!fcb_drive()) return 0xFF;
    while ((idx = fat_find11(&fcb[F_NAME], 0, 0)) >= 0) fat_delete_idx(idx);
    idx = fat_create11(&fcb[F_NAME]);
    if (idx < 0) return 0xFF;
    for (k = 0; k < 4; k++) fcb[F_SIZE + k] = 0;
    fcb[F_FLAGS] = FL_OPEN | FL_DIRTY;
    fcb[F_DIR] = (uint8_t)idx;
    fcb[F_CL] = 0; fcb[F_CL + 1] = 0;
    fcb[F_S2] = 0; fcb[F_RC] = 0;
    return 0;
}

static uint8_t f_delete(void) {
    int16_t idx = 0;
    uint8_t any = 0;
    if (!fcb_drive()) return 0xFF;
    while ((idx = fat_find11(&fcb[F_NAME], idx, 0)) >= 0) { fat_delete_idx(idx); any = 1; idx++; }
    fat_sync();
    return any ? 0 : 0xFF;
}

static uint8_t f_rename(void) {
    int16_t idx;
    if (!fcb_drive()) return 0xFF;
    if (fat_find11(&fcb[17], 0, 0) >= 0) return 0xFF;       /* el nombre nuevo ya existe */
    idx = fat_find11(&fcb[F_NAME], 0, 0);
    if (idx < 0) return 0xFF;
    fat_rename_idx(idx, &fcb[17]);
    fat_sync();
    return 0;
}

/* Busca y deja la entrada, al estilo CP/M, en el DMA: 0 o FFh */
static uint8_t f_search(uint8_t first) {
    uint8_t ent[32], out[32], k;
    uint32_t recs;
    if (first) {
        if (!fcb_drive()) return 0xFF;
        for (k = 0; k < 11; k++) search_pat[k] = fcb[F_DR] == '?' ? '?' : fcb[F_NAME + k];
        search_drv = fcb[F_DR];
        search_idx = 0;
    }
    if (search_idx < 0) return 0xFF;
    search_idx = fat_find11(search_pat, search_idx, ent);
    if (search_idx < 0) return 0xFF;
    search_idx++;
    for (k = 0; k < 32; k++) out[k] = 0;
    for (k = 0; k < 11; k++) out[1 + k] = ent[k];
    recs = (get32(&ent[28]) + 127) >> 7;
    out[12] = recs ? (uint8_t)((recs - 1) >> 7) & 31 : 0;         /* ultima extension */
    out[15] = recs ? (uint8_t)(((recs - 1) & 127) + 1) : 0;
    for (k = 0; k < 4; k++) out[16 + k] = ent[28 + k];          /* tamano, como MSX-DOS */
    to_tpa(dma_addr, out, 32);
    return 0;
}

/* Lee o escribe el registro rec en el DMA: 0 bien, 1 fin, 2 lleno, FFh error */
static uint8_t f_rw(uint32_t rec, uint8_t write) {
    uint32_t off = rec << 7, size = get32(&fcb[F_SIZE]);
    uint32_t dst = TPA_PHYS + dma_addr;
    uint16_t cl = fcb[F_CL] | (fcb[F_CL + 1] << 8), n;
    uint8_t r;
    if (!(fcb[F_FLAGS] & FL_OPEN) || !fcb_drive()) return 0xFF;
    if (!write) {
        if (off >= size) return 1;
        n = (size - off) >= 128 ? 128 : (uint16_t)(size - off);
        r = fat_io(&cl, off, n, dst, 0);
        if (r == FAT_ERR_EOF) return 1;
        if (r) return 0xFF;
        if (n < 128) dma_fill(dst + n, 0x1A, 128 - n);
        return 0;
    }
    r = fat_io(&cl, off, 128, dst, 1);
    if (r == FAT_ERR_FULL) return 2;
    if (r) return 0xFF;
    fcb[F_CL] = (uint8_t)cl; fcb[F_CL + 1] = cl >> 8;
    if (off + 128 > size) put32(&fcb[F_SIZE], off + 128);
    fcb[F_FLAGS] |= FL_DIRTY;
    return 0;
}

static uint8_t f_seq(uint8_t write) {
    uint32_t rec = seq_rec();
    uint8_t r = f_rw(rec, write);
    if (r == 0) set_rec(rec + 1);
    update_rc();
    return r;
}

static uint8_t f_random(uint8_t write) {
    uint32_t rec = fcb[F_R0] | ((uint16_t)fcb[F_R0 + 1] << 8) | ((uint32_t)(fcb[F_R0 + 2] & 3) << 16);
    uint8_t r = f_rw(rec, write);
    set_rec(rec);                                   /* la secuencial sigue de aqui */
    update_rc();
    return r;
}

static void f_size(void) {
    uint32_t recs = (get32(&fcb[F_SIZE]) + 127) >> 7;
    if (fcb_drive()) {
        uint8_t ent[32];
        int16_t idx = fat_find11(&fcb[F_NAME], 0, ent);
        if (idx >= 0 && !(fcb[F_FLAGS] & FL_OPEN)) recs = (get32(&ent[28]) + 127) >> 7;
    }
    fcb[F_R0] = recs; fcb[F_R0 + 1] = recs >> 8; fcb[F_R0 + 2] = recs >> 16;
}

/* ---- vuelta con A, BC, DE y HL (MSX-DOS) */
static uint16_t xret(uint8_t a, uint16_t bc, uint16_t de, uint16_t hl) {
    _dos_ret_a = a; _dos_ret_bc = bc; _dos_ret_de = de; _dos_ret_hl = hl;
    _dos_xret = 1;
    return hl;
}

/* ---- reloj MC146818 en modo nativo: FF0060 indice, FF0061 dato */
static uint8_t rtc_rd(uint8_t reg) __z88dk_fastcall __naked {
    reg;
    __asm
        in a, (0xF1)
        ld h, a
        xor a
        out (0xF1), a           ; pagina MMIO 0
        ld a, l
        out (0x60), a
        in a, (0x61)
        ld l, a
        ld a, h
        out (0xF1), a
        ret
    __endasm;
}

static void rtc_wr(uint8_t reg, uint8_t v) __naked {
    reg; v;
    __asm
        ld hl, #2
        add hl, sp
        in a, (0xF1)
        ld b, a
        xor a
        out (0xF1), a
        ld a, (hl)
        out (0x60), a
        inc hl
        ld a, (hl)
        out (0x61), a
        ld a, b
        out (0xF1), a
        ret
    __endasm;
}

static uint8_t rtc_bin(void) { return rtc_rd(0x0B) & 0x04; }
static uint8_t from_rtc(uint8_t v) { return rtc_bin() ? v : (v >> 4) * 10 + (v & 15); }
static uint8_t to_rtc(uint8_t v)   { return rtc_bin() ? v : ((v / 10) << 4) | (v % 10); }

static uint16_t get_year(void) {
    uint8_t y = rtc_rd(9);
    return rtc_bin() ? 1980 + y : 2000 + from_rtc(y);   /* como lo pone el core */
}

static uint8_t days_in(uint8_t m, uint16_t y) {
    static const uint8_t d[12] = { 31,28,31,30,31,30,31,31,30,31,30,31 };
    if (m == 2 && (y & 3) == 0) return 29;
    return d[m - 1];
}

/* dia de la semana (0 = domingo), Zeller */
static uint8_t weekday(uint16_t y, uint8_t m, uint8_t d) {
    uint16_t k;
    if (m < 3) { m += 12; y--; }
    k = d + (13 * (m + 1)) / 5 + y + y / 4 - y / 100 + y / 400;
    return (k + 6) % 7;
}

static uint8_t verify_flag;

/* ---- bloques (26h/27h): HL registros de fcb[14..15] bytes desde el
   registro aleatorio fcb[33..36] */
static uint16_t f_block(uint16_t count, uint8_t write) {
    uint16_t rs = fcb[14] | (fcb[15] << 8);
    uint32_t rr = get32(&fcb[F_R0]);
    uint32_t off, size, bytes;
    uint16_t cl, done = 0;
    uint8_t r = 0;
    if (!rs) rs = 128;
    if (rs < 64) rr &= 0xFFFFFFUL;
    if (!(fcb[F_FLAGS] & FL_OPEN) || !fcb_drive()) return xret(0xFF, 0, _dos_reg_de, 0);
    off = rr * rs; size = get32(&fcb[F_SIZE]);
    cl = fcb[F_CL] | (fcb[F_CL + 1] << 8);
    if (write) {
        if (count == 0) {                           /* HL = 0: el tamano pasa a ser off */
            put32(&fcb[F_SIZE], off);
            fcb[F_FLAGS] |= FL_DIRTY;
            return xret(0, 0, _dos_reg_de, 0);
        }
        bytes = (uint32_t)count * rs;
        while (done < count) {
            uint16_t n = bytes > 0x4000 ? 0x4000 : (uint16_t)bytes;
            r = fat_io(&cl, off, n, TPA_PHYS + dma_addr + (uint16_t)(off - rr * rs), 1);
            if (r) break;
            off += n; bytes -= n;
            if (!bytes) done = count;
        }
        fcb[F_CL] = (uint8_t)cl; fcb[F_CL + 1] = cl >> 8;
        if (off > size) put32(&fcb[F_SIZE], off);
        fcb[F_FLAGS] |= FL_DIRTY;
        if (r) return xret(r == FAT_ERR_FULL ? 1 : 0xFF, 0, _dos_reg_de, 0);
        put32(&fcb[F_R0], rr + count);
        return xret(0, 0, _dos_reg_de, count);
    }
    /* lectura */
    if (off >= size) return xret(1, 0, _dos_reg_de, 0);
    bytes = (uint32_t)count * rs;
    if (bytes > size - off) bytes = size - off;
    {
        uint32_t left = bytes, o = off;
        while (left) {
            uint16_t n = left > 0x4000 ? 0x4000 : (uint16_t)left;
            r = fat_io(&cl, o, n, TPA_PHYS + dma_addr + (uint16_t)(o - off), 0);
            if (r) break;
            o += n; left -= n;
        }
    }
    done = (uint16_t)((bytes + rs - 1) / rs);
    if (bytes % rs) dma_fill(TPA_PHYS + dma_addr + (uint16_t)bytes, 0, rs - (uint16_t)(bytes % rs));
    put32(&fcb[F_R0], rr + done);
    return xret(done < count ? 1 : 0, 0, _dos_reg_de, done);
}

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
    case 3:  return 0x1A;                       /* AUX: nada (fin de fichero) */
    case 4:  return 0;                          /* AUX: salida */
    case 5:  return 0;                          /* impresora */
    case 7:  return (uint8_t)con_getc();    /* MSX-DOS: entrada directa sin eco */
    case 8:  return (uint8_t)con_getc();    /* MSX-DOS: entrada sin eco */
    case 9:  print_dollar(de); return 0;
    case 10: read_line(de); return 0;
    case 11: return kbd_hit() ? 0xFF : 0;
    case 12: return 0x0022;                     /* CP/M 2.2 */
    case 13: dma_addr = 0x80; fat_invalidate(); return 0;
    case 14: dos_drive = e & 1; return 0;
    case 24: return 0x0003;                     /* unidades A: y B: */
    case 25: return dos_drive;
    case 26: dma_addr = de; return 0;
    case 32: return 0;                          /* numero de usuario */
    case 15: case 16: case 17: case 19: case 20: case 21: case 22: case 23:
    case 33: case 34: case 35: case 36: case 40: {
        uint8_t res = 0, len = (fn >= 33) ? 36 : 33;
        from_tpa(de, fcb, len);
        switch (fn) {
        case 15: res = f_open(); break;
        case 16: res = f_close(); break;
        case 17: res = f_search(1); break;
        case 19: res = f_delete(); break;
        case 20: res = f_seq(0); break;
        case 21: res = f_seq(1); break;
        case 22: res = f_make(); break;
        case 23: res = f_rename(); break;
        case 33: res = f_random(0); break;
        case 34: case 40: res = f_random(1); break;
        case 35: f_size(); break;
        case 36: { uint32_t rec = seq_rec(); fcb[F_R0] = rec; fcb[F_R0 + 1] = rec >> 8; fcb[F_R0 + 2] = rec >> 16; } break;
        }
        if (fn != 17) to_tpa(de, fcb, len);
        return res;
    }
    case 18: return f_search(0);
    case 37: return 0;                          /* reiniciar unidades */
    case 0x1B: {                                /* asignacion: A spc, BC 512, DE total, HL libres */
        uint8_t spc_o = 0;
        uint16_t total = 0, freec = 0;
        uint8_t d = e ? (e - 1) & 1 : dos_drive;
        if (fat_use(d) || fat_info(&spc_o, &total, &freec)) return xret(0xFF, 0, 0, 0);
        return xret(spc_o, 512, total, freec);
    }
    case 0x26: case 0x27: {
        uint16_t res;
        from_tpa(de, fcb, 37);
        res = f_block(_dos_reg_hl, fn == 0x26);
        to_tpa(de, fcb, 37);
        return res;
    }
    case 0x2A: {                                /* fecha: HL ano, D mes, E dia, A dia de la semana */
        uint16_t y = get_year();
        uint8_t m = from_rtc(rtc_rd(8)), d = from_rtc(rtc_rd(7));
        return xret(weekday(y, m, d), 0, ((uint16_t)m << 8) | d, y);
    }
    case 0x2B: {                                /* poner fecha: HL ano, D mes, E dia */
        uint16_t y = _dos_reg_hl;
        uint8_t m = de >> 8, d = e;
        if (y < 1980 || y > 2079 || m < 1 || m > 12 || d < 1 || d > days_in(m, y)) return 0xFF;
        rtc_wr(9, rtc_bin() ? (uint8_t)(y - 1980) : to_rtc((uint8_t)(y % 100)));
        rtc_wr(8, to_rtc(m));
        rtc_wr(7, to_rtc(d));
        rtc_wr(6, weekday(y, m, d) + 1);
        return 0;
    }
    case 0x2C: {                                /* hora: H horas, L minutos, D segundos, E centesimas */
        uint8_t h = from_rtc(rtc_rd(4)), mi = from_rtc(rtc_rd(2)), se = from_rtc(rtc_rd(0));
        return xret(0, 0, (uint16_t)se << 8, ((uint16_t)h << 8) | mi);
    }
    case 0x2D: {                                /* poner hora: H horas, L minutos, D segundos */
        uint8_t h = _dos_reg_hl_b[1], mi = _dos_reg_hl_b[0], se = de >> 8;
        if (h > 23 || mi > 59 || se > 59) return 0xFF;
        rtc_wr(4, to_rtc(h)); rtc_wr(2, to_rtc(mi)); rtc_wr(0, to_rtc(se));
        return 0;
    }
    case 0x2E: verify_flag = e; return 0;       /* verificacion (no hace falta) */
    case 0x2F: case 0x30: {                     /* sectores absolutos: DE sector, H cuantos, L unidad */
        uint8_t d = _dos_reg_hl_b[0], n = _dos_reg_hl_b[1];
        if (fat_use(d & 1) || fat_abs(de, n, TPA_PHYS + dma_addr, fn == 0x30)) return 0xFF;
        return 0;
    }
    case 28: case 29: case 30: case 31: return 0;
    case 0xA0: return music_play(de);
    case 0xA1: music_info(de); return 0;
    default:
        return 0;
    }
}

/* ---- Musica del LX-DOS (extension propia del BDOS, para MODPLAY.COM)
   A0h  DE = nombre del fichero (ASCIIZ en la TPA): lo carga y lo toca de
        fondo; DE = 0: para la musica. A = 0 bien, 1 no esta, 2 error de
        disco, 3 no es un MOD de 4 canales ni un STM, 4 demasiado grande
   A1h  DE = 32 bytes en la TPA: [0] sonando, [1] posicion, [2] posiciones,
        [3] patrones, [4] fila, [5..8] "MOD"/"STM", [9..29] titulo (ASCIIZ)
   El fichero se carga en la fisica 100000h (slot 0, fuera de todo lo demas)
   y suena desde la interrupcion del temporizador de la MS2, aunque se
   ejecuten otros programas. */
#define MUSIC_PHYS 0x100000UL
#define MUSIC_MAX  0x200000UL
static uint8_t music_on;

static uint8_t music_play(uint16_t a) {
    char name[16];
    fat_entry_t e;
    uint8_t i;
    mod_stop();
    music_on = 0;
    if (!a) return 0;
    from_tpa(a, name, sizeof(name));
    name[sizeof(name) - 1] = 0;
    for (i = 0; name[i]; i++) if (name[i] >= 'a' && name[i] <= 'z') name[i] -= 32;
    {   /* "B:NOMBRE" */
        uint8_t d = dos_drive;
        char* n = name;
        if (n[0] && n[1] == ':') { d = (n[0] - 'A') & 1; n += 2; }
        if (fat_use(d)) return 2;
        if (fat_find(n, &e)) return 1;
    }
    if (e.size > MUSIC_MAX) return 4;
    if (fat_load(&e, MUSIC_PHYS, 0)) return 2;
    if (mod_load(MUSIC_PHYS) != MOD_OK) return 3;
    mod_play();
    music_on = 1;
    return 0;
}

static void music_info(uint16_t a) {
    uint8_t buf[32], i;
    const char* t = mod_title();
    const char* k = mod_kind();
    for (i = 0; i < 32; i++) buf[i] = 0;
    buf[0] = music_on;
    buf[1] = mod_position();
    buf[2] = mod_length();
    buf[3] = mod_patterns();
    buf[4] = mod_row();
    for (i = 0; i < 3 && k[i]; i++) buf[5 + i] = k[i];
    for (i = 0; i < 20 && t[i]; i++) buf[9 + i] = t[i];
    to_tpa(a, buf, sizeof(buf));
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
    fat_sync();                                 /* lo que el programa dejo a medias */
    if (con_getx()) con_putc('\n');
    return DOS_RUN_OK;
}
