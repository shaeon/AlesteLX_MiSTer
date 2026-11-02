/* bdos.h - Programas .COM en el LX-DOS (bdos.c)
 * Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer. */
#ifndef __BDOS_H__
#define __BDOS_H__

#include <stdint.h>

#define DOS_RUN_OK       0
#define DOS_RUN_NOTFOUND 1
#define DOS_RUN_DISK     2
#define DOS_RUN_TOOBIG   3

extern uint8_t dos_drive;           /* unidad actual: 0 = A:, 1 = B: */

/** Carga NOMBRE[.COM] de la unidad actual y lo ejecuta con esos argumentos */
uint8_t dos_run(const char* name, const char* args);

#endif
