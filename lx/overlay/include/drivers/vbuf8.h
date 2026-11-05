/* vbuf8.h - Modo 320x200, 256 colores (driver vbuf_64k8b)
 * Shaeon (Carlos Palmero), para la BIOS del Aleste LX.
 *
 * vbuf8_activate pone el driver en la tabla vbuf de la BIOS y el modo en
 * pantalla (VRAM en C50000); vbuf8_text_mode vuelve al modo de texto de la
 * BIOS (16k1b). Todo se dibuja con la DMA/blitter. Los colores son indices de
 * la paleta (palette_set_color_12b). */
#ifndef __VBUF8_H__
#define __VBUF8_H__

#include <stdint.h>

#define VBUF8_W 320
#define VBUF8_H 200

void    vbuf8_activate(void);
void    vbuf8_text_mode(void);

void    vbuf8_clear(uint8_t color);
void    vbuf8_pixel(uint16_t x, uint16_t y, uint8_t color);           /* con recorte */
uint8_t vbuf8_get_pixel(uint16_t x, uint16_t y);
void    vbuf8_hline(uint16_t x, uint16_t y, uint16_t len, uint8_t color);
void    vbuf8_vline(uint16_t x, uint16_t y, uint16_t len, uint8_t color);
void    vbuf8_line(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint8_t color);
void    vbuf8_rect(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint8_t color);
void    vbuf8_fill_rect(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint8_t color);
void    vbuf8_copy(uint16_t sx, uint16_t sy, uint16_t dx, uint16_t dy, uint16_t w, uint16_t h);
void    vbuf8_scroll_up(uint8_t lines);
void    vbuf8_scroll_down(uint8_t lines);
void    vbuf8_clip(uint16_t x, uint16_t y, uint16_t w, uint16_t h);
/* Texto con la fuente de la BIOS (8x8): tinta, fondo y fondo transparente */
void    vbuf8_colors(uint8_t fg, uint8_t bg, uint8_t bg_transparent);
void    vbuf8_char(char c, uint16_t x, uint16_t y);
void    vbuf8_text(const char* s, uint16_t x, uint16_t y);
/* Mapa de bits de 8 bpp en la memoria de la CPU (w x h bytes, por filas);
   con vbuf8_key(color, 1) ese color no se dibuja (sprites) */
void    vbuf8_bitmap(const void* pixels, uint16_t x, uint16_t y, uint16_t w, uint16_t h);
void    vbuf8_key(uint8_t color, uint8_t enable);
/* Doble bufer: se dibuja en la pagina de atras; vbuf8_swap la muestra */
void    vbuf8_double(uint8_t on);
void    vbuf8_swap(void);

#endif
