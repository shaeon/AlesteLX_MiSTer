/**
 * @file fat.h
 * @brief Ficheros de discos MSX-DOS (FAT12) por la disquetera
 * Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
 *
 * Solo el directorio raiz y lectura. Los ficheros se cargan en memoria
 * fisica (24 bits) con la DMA.
 */
#ifndef __FAT_H__
#define __FAT_H__

#include <stdint.h>

#define FAT_OK          0
#define FAT_ERR_DISK    1   /* error de la disquetera */
#define FAT_ERR_FORMAT  2   /* no es un disco FAT12 */
#define FAT_ERR_NOFILE  3   /* no existe */

typedef struct {
    char     name[13];      /* "NOMBRE.EXT" */
    uint8_t  attr;
    uint16_t cluster;
    uint32_t size;
} fat_entry_t;

uint8_t fat_mount(uint8_t drive);
/** Recorre el directorio raiz; la rutina devuelve 0 para seguir */
uint8_t fat_dir(uint8_t (*cb)(const fat_entry_t* e));
uint8_t fat_find(const char* name, fat_entry_t* e);
/** Carga el fichero en memoria fisica; progress (puede ser 0) recibe los KB */
uint8_t fat_load(const fat_entry_t* e, uint32_t phys, void (*progress)(uint16_t kb));
uint16_t fat_free_kb(void);
/** Lee len bytes desde el desplazamiento off del fichero que empieza en el
    cluster cl0 y los deja en memoria fisica */
uint8_t fat_read_at(uint16_t cl0, uint32_t off, uint16_t len, uint32_t phys);

#endif
