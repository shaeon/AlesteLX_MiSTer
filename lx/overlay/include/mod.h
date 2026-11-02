/**
 * @file mod.h
 * @brief Reproductor de MOD de ProTracker (4 canales) y STM de Scream Tracker 2
 *        por la Magic Sound 2
 * Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
 *
 * El MOD esta en memoria fisica (por ejemplo, cargado desde el OSD en
 * 000000). Suena en segundo plano desde la interrupcion del temporizador de
 * la MS2; lee cada fila del patron por DMA.
 */
#ifndef __MOD_H__
#define __MOD_H__

#include <stdint.h>

#define MOD_OK          0
#define MOD_ERR_FORMAT  1   /* ni MOD de 4 canales (M.K., M!K!, 4CHN, FLT4) ni STM */

uint8_t     mod_load(uint32_t phys);     /* lee la cabecera y prepara la cancion */
void        mod_play(void);
void        mod_stop(void);
uint8_t     mod_playing(void);
const char* mod_title(void);
uint8_t     mod_position(void);           /* posicion en la lista de orden */
uint8_t     mod_length(void);
uint8_t     mod_row(void);
uint8_t     mod_patterns(void);
const char* mod_kind(void);              /* "MOD" o "STM" */

#endif
