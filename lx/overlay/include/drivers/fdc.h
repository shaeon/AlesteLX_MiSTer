/**
 * @file fdc.h
 * @brief Disquetera (driver polimorfico, uPD765 del Aleste LX)
 * Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
 *
 * Discos de 720 KB: 80 pistas, 2 caras, 9 sectores de 512 bytes. Las
 * imagenes se montan en el OSD (Mount Drive A:/B:).
 */
#ifndef __FDC_H__
#define __FDC_H__

#include <stdint.h>

#define FDC_SECTOR      512
#define FDC_SPT         9
#define FDC_HEADS       2
#define FDC_ERR_TIMEOUT 0x80

void    fdc_activate_765(void);
uint8_t fdc_detect(void);
uint8_t fdc_install(void);
void*   fdc_get_info(void);
void    fdc_uninstall(void);
uint8_t fdc_status(void);
/** Lee un sector: 0 bien; FDC_ERR_TIMEOUT sin respuesta; si no, ST1 | ST2 */
uint8_t fdc_read(uint8_t drive, uint8_t track, uint8_t head, uint8_t sector, void* buf);
/** Lee el sector logico lba (0 = pista 0, cara 0, sector 1) */
uint8_t fdc_read_lba(uint8_t drive, uint16_t lba, void* buf);

#endif
