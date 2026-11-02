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
#define FAT_ERR_EOF     4   /* lectura pasado el final */
#define FAT_ERR_FULL    5   /* disco lleno */

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

#ifdef FAT_WRITE
/* ---- Escritura (LX-DOS). Los nombres van en 11 caracteres ("NOMBRE  EXT"). */
uint8_t fat_use(uint8_t drive);         /* monta si no es la unidad montada */
void    fat_invalidate(void);           /* sincroniza y fuerza volver a montar */
uint8_t fat_sync(void);                 /* sector en cache y FAT, al disco */
/** Lee (write = 0) o escribe len bytes en el desplazamiento off del fichero
    cuyo primer cluster es *cl0 (0 = vacio: se reserva al escribir); los
    clusteres que faltan se reservan al escribir */
uint8_t fat_io(uint16_t* cl0, uint32_t off, uint16_t len, uint32_t phys, uint8_t write);
/** Busca desde la entrada from un nombre ('?' = cualquiera); copia la entrada
    (32 bytes) si ent no es 0. Devuelve la entrada o -1 */
int16_t fat_find11(const uint8_t* pat, int16_t from, uint8_t* ent);
int16_t fat_create11(const uint8_t* name);          /* entrada nueva vacia o -1 */
uint8_t fat_set_entry(int16_t idx, uint16_t cl, uint32_t size);
uint8_t fat_delete_idx(int16_t idx);                /* y libera sus clusteres */
uint8_t fat_rename_idx(int16_t idx, const uint8_t* name);
uint8_t fat_name11(const char* s, uint8_t* n11);   /* 1 si lleva comodines */
uint8_t fat_info(uint8_t* spc, uint16_t* total, uint16_t* free_cl); /* clusteres */
/** Lee o escribe count sectores desde lba (absolutos) en memoria fisica */
uint8_t fat_abs(uint16_t lba, uint8_t count, uint32_t phys, uint8_t write);
#endif

#endif
