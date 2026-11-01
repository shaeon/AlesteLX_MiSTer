/**
 * @file dma.h
 * @brief DMA / blitter (driver polimorfico, modo LX)
 * Shaeon (Carlos Palmero), para el modo LX del core aleste520ex.
 *
 * Las direcciones de la DMA son fisicas (24 bits); dma_phys convierte una
 * direccion de la CPU con el mapa actual de la MMU.
 */
#ifndef __DMA_H__
#define __DMA_H__

#include <stdint.h>

#define DMA_MODE_COPY   0   /* copia */
#define DMA_MODE_FILL   1   /* relleno con key */
#define DMA_MODE_KEY    2   /* copia sin escribir los bytes iguales a key */

/** Peticion: el mismo orden que los registros 02h-10h, mas el modo */
typedef struct {
    uint8_t  src[3];     /**< origen, fisica, byte bajo primero */
    uint8_t  dst[3];     /**< destino */
    uint16_t width;      /**< bytes por linea (0 = 65536) */
    uint16_t height;     /**< lineas (0 = 1) */
    int16_t  src_stride; /**< distancia entre lineas del origen */
    int16_t  dst_stride; /**< distancia entre lineas del destino */
    uint8_t  key;        /**< relleno o color transparente */
    uint8_t  mode;       /**< DMA_MODE_* */
} dma_req_t;

void     dma_activate_lx(void);
uint8_t  dma_detect(void);
uint8_t  dma_install(void);
void*    dma_get_info(void);
void     dma_uninstall(void);
void     dma_start(const dma_req_t* req) __z88dk_fastcall;   /* sin esperar */
void     dma_wait(void);
uint8_t  dma_busy(void);
uint32_t dma_phys(const void* cpu_addr) __z88dk_fastcall;

/* Ayudas (esperan a que acabe) */
void dma_copy(uint32_t src, uint32_t dst, uint16_t len);
void dma_fill(uint32_t dst, uint8_t value, uint16_t len);
void dma_rect(uint32_t src, uint32_t dst, uint16_t width, uint16_t height,
              int16_t src_stride, int16_t dst_stride, uint8_t mode, uint8_t key);

#endif
