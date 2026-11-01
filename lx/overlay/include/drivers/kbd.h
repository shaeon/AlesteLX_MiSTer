/**
 * @file kbd.h
 * @brief Teclado (driver polimorfico, teclado PS/2 del modo LX)
 * Shaeon (Carlos Palmero), para el modo LX del core aleste520ex.
 *
 * Teclado de EE. UU. Caracteres ASCII; KBD_* para las teclas especiales;
 * control+letra da 01h-1Ah. kbd_install necesita int_install antes.
 */
#ifndef __KBD_H__
#define __KBD_H__

#include <stdint.h>

#define KBD_UP      0x80
#define KBD_DOWN    0x81
#define KBD_LEFT    0x82
#define KBD_RIGHT   0x83
#define KBD_HOME    0x84
#define KBD_END     0x85
#define KBD_PGUP    0x86
#define KBD_PGDN    0x87
#define KBD_INSERT  0x88
#define KBD_DELETE  0x7F
#define KBD_F1      0x90   /* F1-F10: 90h-99h */
#define KBD_ENTER   0x0D
#define KBD_BS      0x08
#define KBD_ESC     0x1B

#define KBD_SH_SHIFT 0x01
#define KBD_SH_CTRL  0x02
#define KBD_SH_CAPS  0x04

void    kbd_activate_lx(void);
uint8_t kbd_detect(void);
uint8_t kbd_install(void);
void*   kbd_get_info(void);
void    kbd_uninstall(void);
uint8_t kbd_hit(void);                          /* 1 si hay caracteres */
uint8_t kbd_getc(void);                         /* espera un caracter */
uint8_t kbd_shift_state(void);                  /* KBD_SH_* */
uint8_t kbd_row(uint8_t row) __z88dk_fastcall;  /* fila 0-10 de la matriz, activo a 0 */

#endif
