/**
 * @file tune.h
 * @brief Demostracion de la Magic Sound 2: el Himno de la alegria (Beethoven)
 * a cuatro canales, secuenciado con el temporizador de la MS2 a 50 Hz.
 * Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
 */
#ifndef __TUNE_H__
#define __TUNE_H__

#include <stdint.h>

void    tune_start(void);
void    tune_stop(void);
uint8_t tune_row(void);     /* fila actual (0-63), para mostrarla */

#endif
