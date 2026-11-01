/**
 * @file timer.h
 * @brief Temporizador del sistema (driver polimorfico, modo LX)
 * Shaeon (Carlos Palmero), para el modo LX del core aleste520ex.
 *
 * timer_get_ms y timer_delay_ms no necesitan interrupciones. El periodico
 * usa el driver de interrupciones (int_install antes).
 */
#ifndef __TIMER_H__
#define __TIMER_H__

#include <stdint.h>
#include "drivers/int.h"

void     timer_activate_lx(void);
uint8_t  timer_detect(void);
uint8_t  timer_install(void);
void*    timer_get_info(void);
void     timer_uninstall(void);
uint16_t timer_get_ms(void);                                  /* da la vuelta cada 65,5 s */
void     timer_delay_ms(uint16_t ms) __z88dk_fastcall;
void     timer_set_periodic(uint16_t period_us, int_handler_t handler); /* handler 0 = parar */
uint16_t timer_get_count(void);                               /* saltos del periodico */

#endif
