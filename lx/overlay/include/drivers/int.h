/**
 * @file int.h
 * @brief Interrupciones (driver polimorfico, PIC del modo LX)
 * Shaeon (Carlos Palmero), para el modo LX del core aleste520ex.
 *
 * Lineas del PIC del modo LX: 0 disquetera, 1 DMA, 2 VBlank, 3 Magic Sound 2,
 * 4 Gate Array (300 Hz), 6 temporizador. Las rutinas se llaman desde la
 * interrupcion (con las interrupciones cerradas): cortas y sin esperar.
 */
#ifndef __INT_H__
#define __INT_H__

#include <stdint.h>

#define INT_LINE_STORAGE  0
#define INT_LINE_DMA      1
#define INT_LINE_VBLANK   2
#define INT_LINE_AUDIO    3
#define INT_LINE_LEGACY   4
#define INT_LINE_TIMER    6

typedef void (*int_handler_t)(void);

void    int_activate_lx(void);                               /* elige el driver del PIC LX */
uint8_t int_detect(void);                                    /* 1 si hay controlador */
uint8_t int_install(void);                                   /* IM 1, todo enmascarado, EI */
void*   int_get_info(void);
void    int_uninstall(void);
void    int_set_handler(uint8_t line, int_handler_t handler);
void    int_enable(uint8_t line) __z88dk_fastcall;
void    int_disable(uint8_t line) __z88dk_fastcall;

#endif
