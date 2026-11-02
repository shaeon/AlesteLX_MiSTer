/**
 * @file console.c
 * @brief Consola de texto de 80x25 (ver console.h)
 * Shaeon (Carlos Palmero).
 */
#include "console.h"
#include "drivers/dma.h"
#include "drivers/kbd.h"

#define VRAM_PHYS   0xC40000UL      /* 16k1b: lineal, 80 bytes por linea */
#define LINE_BYTES  80
#define ROW_BYTES   (LINE_BYTES * 8)

static uint8_t cx, cy, win_top, win_bot = CON_ROWS - 1;

/* La fuente (FONT_DATA, ventana 3) empieza en el caracter 20h, 8 bytes por
   caracter; cada uno se copia con la DMA a sus 8 lineas de video: la consola
   no mapea la memoria de video en ninguna ventana. */
extern uint8_t _scr_font_data[];
static uint32_t font_phys;

static void draw(char c, uint8_t x, uint8_t y) {
    uint8_t ch = (uint8_t)c;
    uint32_t dst = VRAM_PHYS + (uint16_t)y * ROW_BYTES + x;
    if (!font_phys) font_phys = dma_phys(_scr_font_data);
    if (ch < 0x20) ch = 0x20;
    dma_rect(font_phys + (uint16_t)(ch - 0x20) * 8, dst, 1, 8, 1, LINE_BYTES, DMA_MODE_COPY, 0);
}

static void clear_rows(uint8_t from, uint8_t to) {
    dma_fill(VRAM_PHYS + (uint32_t)from * ROW_BYTES, 0x00, (uint16_t)(to - from + 1) * ROW_BYTES);
}

static void scroll(void) {
    if (win_bot > win_top)
        dma_copy(VRAM_PHYS + (uint32_t)(win_top + 1) * ROW_BYTES,
                 VRAM_PHYS + (uint32_t)win_top * ROW_BYTES,
                 (uint16_t)(win_bot - win_top) * ROW_BYTES);
    clear_rows(win_bot, win_bot);
}

void con_set_window(uint8_t top, uint8_t bottom) {
    if (bottom >= CON_ROWS) bottom = CON_ROWS - 1;
    if (top > bottom) top = bottom;
    win_top = top; win_bot = bottom;
    if (cy < top || cy > bottom) { cx = 0; cy = top; }
}

void con_clear(void) {
    clear_rows(win_top, win_bot);
    cx = 0; cy = win_top;
}

void con_init(void) {
    win_top = 0; win_bot = CON_ROWS - 1;
    con_clear();
}

void con_gotoxy(uint8_t x, uint8_t y) {
    cx = x < CON_COLS ? x : CON_COLS - 1;
    cy = y < CON_ROWS ? y : CON_ROWS - 1;
}

uint8_t con_getx(void) { return cx; }
uint8_t con_gety(void) { return cy; }

static void newline(void) {
    cx = 0;
    if (cy >= win_bot) scroll();
    else cy++;
}

void con_putc(char c) __z88dk_fastcall {
    switch (c) {
    case '\n': newline(); return;
    case '\r': cx = 0; return;
    case '\b': if (cx) { cx--; draw(' ', cx, cy); } return;
    case '\t': do con_putc(' '); while (cx & 7); return;
    default:
        draw(c, cx, cy);
        if (++cx >= CON_COLS) newline();
    }
}

void con_puts(const char* s) __z88dk_fastcall {
    while (*s) con_putc(*s++);
}

void con_putu(uint16_t v) __z88dk_fastcall {
    char buf[6];
    int8_t i = 5;
    buf[5] = 0;
    do { buf[--i] = '0' + (v % 10); v /= 10; } while (v);
    con_puts(&buf[i]);
}

void con_puthex(uint8_t v) __z88dk_fastcall {
    static const char hx[] = "0123456789ABCDEF";
    con_putc(hx[v >> 4]);
    con_putc(hx[v & 15]);
}

static void (*idle_fn)(void);
void con_set_idle(void (*idle)(void)) { idle_fn = idle; }

char con_getc(void) {
    char c;
    uint8_t x = cx, y = cy;
    draw('_', x, y);
    while (!kbd_hit())
        if (idle_fn) { idle_fn(); cx = x; cy = y; }
    c = kbd_getc();
    cx = x; cy = y;
    draw(' ', x, y);
    return c;
}

uint8_t con_gets(char* buf, uint8_t max) {
    uint8_t n = 0;
    while (1) {
        char c = con_getc();
        if (c == '\r') { buf[n] = 0; con_putc('\n'); return n; }
        if (c == '\b') { if (n) { n--; con_putc('\b'); } continue; }
        if ((uint8_t)c >= 0x20 && (uint8_t)c < 0x7F && n + 1 < max) { buf[n++] = c; con_putc(c); }
    }
}
