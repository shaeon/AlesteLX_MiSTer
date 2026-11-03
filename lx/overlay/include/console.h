/**
 * @file console.h
 * @brief Consola de texto de 80x25 sobre el video 16k1b (640x200)
 * Shaeon (Carlos Palmero), para el modo LX del core aleste520ex.
 *
 * Dibuja con vbuf_draw_char y hace el scroll y el borrado con la DMA.
 * Necesita los drivers vbuf (16k1b), dma y, para leer, kbd.
 */
#ifndef __CONSOLE_H__
#define __CONSOLE_H__

#include <stdint.h>

#define CON_COLS 80
#define CON_ROWS 25

void    con_init(void);                         /* borra y pone el cursor arriba */
void    con_clear(void);
void    con_gotoxy(uint8_t x, uint8_t y);
uint8_t con_getx(void);
uint8_t con_top(void);                         /* primera fila de la ventana de scroll */
void    con_draw(char c, uint8_t x, uint8_t y); /* un caracter, sin mover el cursor */
uint8_t con_gety(void);
void    con_putc(char c) __z88dk_fastcall;      /* \n, \r, \b, \t y caracteres */
void    con_puts(const char* s) __z88dk_fastcall;
void    con_putu(uint16_t v) __z88dk_fastcall;  /* numero sin signo */
void    con_puthex(uint8_t v) __z88dk_fastcall; /* dos cifras hexadecimales */
void    con_set_window(uint8_t top, uint8_t bottom); /* filas que hacen scroll */
char    con_getc(void);                         /* espera una tecla con cursor */
void    con_set_idle(void (*idle)(void));       /* se llama mientras con_getc espera */
uint8_t con_gets(char* buf, uint8_t max);       /* lee una linea; devuelve su longitud */

#endif
