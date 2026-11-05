/* gfx8.h - Modo 320x200 con 256 colores (8 bpp lineal) del Aleste LX
 * Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
 *
 * VRAM en C50000-C5F9FF (64000 bytes, un byte por pixel, linea a linea).
 * CRTC: R18 = 03h (8 bpp), R19 = C5h, R20 = 07h (lineal, 8 bytes por
 * caracter), R21 = 02h, con la geometria del modo de texto (R1 40, R6 25,
 * R9 7). Paleta de 256 colores de 12 bits (0RGB). Lo que mueve memoria lo hace
 * la DMA.
 *
 * Imagenes .LXI (tools/img2lx.py): "LXI1", ancho y alto (16 bits), numero de
 * colores (16 bits), la paleta (2 bytes por color, 0RGB de 12 bits, byte bajo
 * primero) y los pixeles (un byte cada uno, linea a linea).
 */
#ifndef __GFX8_H__
#define __GFX8_H__

#include <stdint.h>

#define GFX8_W      320
#define GFX8_H      200
#define GFX8_VRAM   0xC50000UL
#define GFX8_TRANSPARENT 0xFF00         /* fondo del texto: no se pinta */

uint8_t gfx8_active(void);
void    gfx8_mode(uint8_t on);          /* 1 = 320x200x256, 0 = texto (como estaba) */
void    gfx8_palette_phys(uint32_t phys, uint16_t first, uint16_t n);   /* n x 2 bytes */
void    gfx8_clear(uint8_t color);
void    gfx8_fill(int16_t x, int16_t y, int16_t w, int16_t h, uint8_t color);
/* Rectangulo de w x h bytes desde la memoria fisica (lineas de 'stride'
   bytes); con transparente, no se copian los pixeles de color 'key' */
void    gfx8_blit(uint32_t src, uint16_t stride, int16_t x, int16_t y, int16_t w, int16_t h,
                  uint8_t transparent, uint8_t key);
void    gfx8_scroll(int16_t lines, uint8_t fill);    /* > 0 sube, < 0 baja */
/* Texto con la fuente 8x8 de la BIOS; bg = GFX8_TRANSPARENT: sin fondo */
void    gfx8_text(int16_t x, int16_t y, const char* s, uint8_t fg, uint16_t bg);

#define GFX8_OK        0
#define GFX8_NOFILE    1
#define GFX8_DISK      2
#define GFX8_FORMAT    3
/* Carga y muestra una imagen .LXI de la unidad 'drive' (pone el modo) */
uint8_t gfx8_view(uint8_t drive, const char* name);

#endif
