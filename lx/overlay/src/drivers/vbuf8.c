/* vbuf8.c - Modo 320x200x256 (driver vbuf_64k8b): llamadas en C
 * Shaeon (Carlos Palmero), para la BIOS del Aleste LX.
 * Cada funcion deja los registros del metodo en g_* y vcall salta a la
 * entrada de la tabla vbuf fija (las direcciones son las de la ROM). */
#include "drivers/vbuf8.h"
#include "drivers/crtc.h"

extern uint8_t _drv_64k8b_vtable[], _vbuf_vtable_start[], _scr_font_data[];
extern uint8_t _vbuf_init[], _vbuf_command[], _vbuf_clear[], _vbuf_scroll_up[], _vbuf_scroll_down[];
extern uint8_t _vbuf_set_clip_rect[], _vbuf_copy_rect[], _vbuf_put_pixel[], _vbuf_get_pixel[];
extern uint8_t _vbuf_draw_hline[], _vbuf_draw_vline[], _vbuf_draw_line[], _vbuf_draw_rect[];
extern uint8_t _vbuf_fill_rect[], _vbuf_draw_char[], _vbuf_draw_bitmap[], _vbuf_swap_buffers[];

static uint16_t g_bc, g_de, g_hl, g_fn;
static uint8_t  g_a;
static uint16_t g_box[6];

static void vcall(void) __naked {
    __asm
        push ix
        push iy
        ld bc, (_g_bc)
        ld de, (_g_de)
        ld hl, (_g_hl)
        ld a, (_g_a)
        call vjump
        ld (_g_a), a
        ld (_g_hl), hl
        pop iy
        pop ix
        ret
    vjump:
        push hl
        ld hl, (_g_fn)
        ex (sp), hl
        ret
    __endasm;
}

static void call_box(uint8_t* fn, uint8_t a) {
    g_de = (uint16_t)g_box; g_a = a; g_fn = (uint16_t)fn;
    vcall();
}

void vbuf8_activate(void) {
    /* la tabla del driver a la tabla vbuf fija */
    uint8_t* s = _drv_64k8b_vtable;
    uint8_t* d = _vbuf_vtable_start;
    uint8_t i;
    for (i = 0; i < 25 * 3; i++) d[i] = s[i];
    g_fn = (uint16_t)_vbuf_init;
    vcall();
}

void vbuf8_text_mode(void) {
    crtc_set_mode(3);                   /* 16k1b: 640x200, 1 bpp, C40000 */
}

void vbuf8_clear(uint8_t color) { g_a = color; g_fn = (uint16_t)_vbuf_clear; vcall(); }

void vbuf8_pixel(uint16_t x, uint16_t y, uint8_t color) {
    g_bc = x; g_de = y; g_a = color; g_fn = (uint16_t)_vbuf_put_pixel; vcall();
}

uint8_t vbuf8_get_pixel(uint16_t x, uint16_t y) {
    g_bc = x; g_de = y; g_fn = (uint16_t)_vbuf_get_pixel; vcall();
    return g_a;
}

void vbuf8_hline(uint16_t x, uint16_t y, uint16_t len, uint8_t color) {
    g_bc = x; g_de = y; g_hl = len; g_a = color; g_fn = (uint16_t)_vbuf_draw_hline; vcall();
}

void vbuf8_vline(uint16_t x, uint16_t y, uint16_t len, uint8_t color) {
    g_bc = x; g_de = y; g_hl = len; g_a = color; g_fn = (uint16_t)_vbuf_draw_vline; vcall();
}

void vbuf8_line(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint8_t color) {
    g_box[0] = x1; g_box[1] = y1; g_box[2] = x2; g_box[3] = y2;
    call_box(_vbuf_draw_line, color);
}

void vbuf8_rect(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint8_t color) {
    g_box[0] = x; g_box[1] = y; g_box[2] = w; g_box[3] = h;
    call_box(_vbuf_draw_rect, color);
}

void vbuf8_fill_rect(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint8_t color) {
    g_box[0] = x; g_box[1] = y; g_box[2] = w; g_box[3] = h;
    call_box(_vbuf_fill_rect, color);
}

void vbuf8_clip(uint16_t x, uint16_t y, uint16_t w, uint16_t h) {
    g_box[0] = x; g_box[1] = y; g_box[2] = w; g_box[3] = h;
    call_box(_vbuf_set_clip_rect, 0);
}

void vbuf8_copy(uint16_t sx, uint16_t sy, uint16_t dx, uint16_t dy, uint16_t w, uint16_t h) {
    g_box[0] = sx; g_box[1] = sy; g_box[2] = dx; g_box[3] = dy; g_box[4] = w; g_box[5] = h;
    call_box(_vbuf_copy_rect, 0);
}

void vbuf8_scroll_up(uint8_t lines)   { g_a = lines; g_fn = (uint16_t)_vbuf_scroll_up; vcall(); }
void vbuf8_scroll_down(uint8_t lines) { g_a = lines; g_fn = (uint16_t)_vbuf_scroll_down; vcall(); }

static void command(uint8_t cmd, uint16_t param) {
    g_a = cmd; g_de = param; g_fn = (uint16_t)_vbuf_command; vcall();
}

void vbuf8_colors(uint8_t fg, uint8_t bg, uint8_t bg_transparent) {
    command(0x10, fg);
    command(0x11, bg);
    command(0x12, bg_transparent);
}

void vbuf8_key(uint8_t color, uint8_t enable) { command(0x13, ((uint16_t)enable << 8) | color); }
void vbuf8_double(uint8_t on) { command(on ? 0x01 : 0x02, 0); }
void vbuf8_swap(void) { g_fn = (uint16_t)_vbuf_swap_buffers; vcall(); }

void vbuf8_char(char c, uint16_t x, uint16_t y) {
    g_hl = (uint16_t)_scr_font_data; g_a = (uint8_t)c; g_bc = x; g_de = y;
    g_fn = (uint16_t)_vbuf_draw_char; vcall();
}

void vbuf8_text(const char* s, uint16_t x, uint16_t y) {
    while (*s) { vbuf8_char(*s++, x, y); x += 8; }
}

void vbuf8_bitmap(const void* pixels, uint16_t x, uint16_t y, uint16_t w, uint16_t h) {
    g_box[0] = x; g_box[1] = y; g_box[2] = w; g_box[3] = h;
    g_hl = (uint16_t)pixels;
    call_box(_vbuf_draw_bitmap, 0);
}
