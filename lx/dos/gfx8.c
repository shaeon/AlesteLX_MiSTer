/* gfx8.c - Modo 320x200 con 256 colores del Aleste LX (ver gfx8.h)
 * Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer. */
#include <stdint.h>
#include "drivers/dma.h"
#include "fat.h"
#include "gfx8.h"

/* Puertos: pagina MMIO 2 = paleta (00-06) y CRTC (20/21). Las interrupciones
   guardan y restauran la pagina, asi que basta con elegirla antes. */
__sfr __at 0xF1 io_page;
__sfr __at 0x00 io_pal_idx;
__sfr __at 0x01 io_pal_lo;
__sfr __at 0x02 io_pal_hi;
__sfr __at 0x05 io_pal_ctrl;
__sfr __at 0x20 io_crtc_idx;
__sfr __at 0x21 io_crtc_dat;

#define FONT_PHYS 0xC0E000UL            /* fuente de la BIOS (ventana 3, banco 3) */
#define LXI_TMP   0x0E0000UL            /* fisica libre para cargar la imagen */

static uint8_t on, saved[22], pal_saved[4], pal_ctrl_saved;
static const uint8_t mode_regs[] = { 12, 0, 13, 0, 0x13, 0xC5, 0x14, 0x07, 0x15, 0x02, 0x12, 0x03 };

uint8_t gfx8_active(void) { return on; }

void gfx8_mode(uint8_t m) {
    uint8_t i;
    io_page = 2;
    if (m && !on) {
        for (i = 0; i < 22; i++) { io_crtc_idx = i; saved[i] = io_crtc_dat; }
        pal_ctrl_saved = io_pal_ctrl;
        io_pal_idx = 0; pal_saved[0] = io_pal_lo; pal_saved[1] = io_pal_hi;
        io_pal_idx = 1; pal_saved[2] = io_pal_lo; pal_saved[3] = io_pal_hi;
        for (i = 0; i < sizeof(mode_regs); i += 2) { io_crtc_idx = mode_regs[i]; io_crtc_dat = mode_regs[i + 1]; }
        on = 1;
    } else if (!m && on) {
        for (i = 0; i < 22; i++) { io_crtc_idx = i; io_crtc_dat = saved[i]; }
        io_pal_ctrl = 0;
        io_pal_idx = 0; io_pal_lo = pal_saved[0]; io_pal_hi = pal_saved[1];
        io_pal_idx = 1; io_pal_lo = pal_saved[2]; io_pal_hi = pal_saved[3];
        io_pal_ctrl = pal_ctrl_saved;
        on = 0;
    }
}

void gfx8_palette_phys(uint32_t phys, uint16_t first, uint16_t n) {
    static uint8_t buf[64];
    uint16_t done = 0;
    while (done < n) {
        uint8_t k, cnt = (n - done) > 32 ? 32 : (uint8_t)(n - done);
        dma_copy(phys + done * 2, dma_phys(buf), cnt * 2);
        io_page = 2;
        for (k = 0; k < cnt; k++) {
            io_pal_idx = (uint8_t)(first + done + k);
            io_pal_lo = buf[k * 2];
            io_pal_hi = buf[k * 2 + 1];
        }
        done += cnt;
    }
}

/* recorta el rectangulo a la pantalla; 0 si no queda nada */
static uint8_t clip(int16_t* x, int16_t* y, int16_t* w, int16_t* h, int16_t* sx, int16_t* sy) {
    if (*x < 0) { *w += *x; *sx -= *x; *x = 0; }
    if (*y < 0) { *h += *y; *sy -= *y; *y = 0; }
    if (*x + *w > GFX8_W) *w = GFX8_W - *x;
    if (*y + *h > GFX8_H) *h = GFX8_H - *y;
    return *w > 0 && *h > 0;
}

static uint32_t at(int16_t x, int16_t y) { return GFX8_VRAM + (uint16_t)y * GFX8_W + (uint16_t)x; }

void gfx8_clear(uint8_t color) { dma_fill(GFX8_VRAM, color, GFX8_W * GFX8_H); }

void gfx8_fill(int16_t x, int16_t y, int16_t w, int16_t h, uint8_t color) {
    int16_t sx = 0, sy = 0;
    if (!clip(&x, &y, &w, &h, &sx, &sy)) return;
    dma_rect(0, at(x, y), w, h, 0, GFX8_W, DMA_MODE_FILL, color);
}

void gfx8_blit(uint32_t src, uint16_t stride, int16_t x, int16_t y, int16_t w, int16_t h,
               uint8_t transparent, uint8_t key) {
    int16_t sx = 0, sy = 0;
    if (!clip(&x, &y, &w, &h, &sx, &sy)) return;
    src += (uint32_t)sy * stride + sx;
    dma_rect(src, at(x, y), w, h, stride, GFX8_W, transparent ? DMA_MODE_KEY : DMA_MODE_COPY, key);
}

void gfx8_scroll(int16_t lines, uint8_t fill) {
    int16_t n;
    if (lines >= GFX8_H || lines <= -GFX8_H) { gfx8_clear(fill); return; }
    if (lines > 0) {                    /* hacia arriba: la DMA copia hacia delante */
        n = GFX8_H - lines;
        dma_copy(at(0, lines), GFX8_VRAM, (uint16_t)n * GFX8_W);
        gfx8_fill(0, n, GFX8_W, lines, fill);
    } else if (lines < 0) {             /* hacia abajo: linea a linea desde el final */
        lines = -lines;
        for (n = GFX8_H - 1; n >= lines; n--) dma_copy(at(0, n - lines), at(0, n), GFX8_W);
        gfx8_fill(0, 0, GFX8_W, lines, fill);
    }
}

void gfx8_text(int16_t x, int16_t y, const char* s, uint8_t fg, uint16_t bg) {
    static uint8_t glyph[8], cell[64];
    uint8_t t = (bg == GFX8_TRANSPARENT);
    uint8_t key = t ? (uint8_t)(fg ^ 0xFF) : 0;          /* un color distinto de fg */
    for (; *s; s++, x += 8) {
        uint8_t c = (uint8_t)*s, r, b;
        if (c < 32) c = '?';
        dma_copy(FONT_PHYS + (uint16_t)(c - 32) * 8, dma_phys(glyph), 8);
        for (r = 0; r < 8; r++)
            for (b = 0; b < 8; b++)
                cell[r * 8 + b] = (glyph[r] & (0x80 >> b)) ? fg : (t ? key : (uint8_t)bg);
        gfx8_blit(dma_phys(cell), 8, x, y, 8, 8, t, key);
    }
}

uint8_t gfx8_view(uint8_t drive, const char* name) {
    static uint8_t hdr[10];
    fat_entry_t e;
    uint16_t w, h, n;
    if (fat_use(drive)) return GFX8_DISK;
    if (fat_find(name, &e)) return GFX8_NOFILE;
    if (e.size < 10 || e.size > 0x20000UL) return GFX8_FORMAT;
    if (fat_load(&e, LXI_TMP, 0)) return GFX8_DISK;
    dma_copy(LXI_TMP, dma_phys(hdr), 10);
    w = hdr[4] | (hdr[5] << 8); h = hdr[6] | (hdr[7] << 8); n = hdr[8] | (hdr[9] << 8);
    if (hdr[0] != 'L' || hdr[1] != 'X' || hdr[2] != 'I' || hdr[3] != '1' || !n || n > 256 ||
        w > GFX8_W || h > GFX8_H || e.size < 10UL + n * 2 + (uint32_t)w * h) return GFX8_FORMAT;
    gfx8_mode(1);
    gfx8_palette_phys(LXI_TMP + 10, 0, n);
    if (w < GFX8_W || h < GFX8_H) gfx8_clear(0);
    gfx8_blit(LXI_TMP + 10 + n * 2, w, (GFX8_W - w) / 2, (GFX8_H - h) / 2, w, h, 0, 0);
    return GFX8_OK;
}
