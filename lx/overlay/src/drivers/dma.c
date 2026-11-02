/**
 * @file dma.c
 * @brief Envoltorios en C del driver de DMA (dma.asm) y ayudas
 * Shaeon (Carlos Palmero).
 */
#include "drivers/dma.h"

void dma_activate_lx(void) __naked {
    __asm
        EXTERN __dma_lx_vtable, __dma_activate_driver
        ld hl, __dma_lx_vtable
        jp __dma_activate_driver
    __endasm;
}

uint8_t dma_detect(void) __naked {
    __asm
        EXTERN __dma_detect
        call __dma_detect
        ld l, a
        ret
    __endasm;
}

uint8_t dma_install(void) __naked {
    __asm
        EXTERN __dma_install
        call __dma_install
        ld l, a
        ret
    __endasm;
}

void* dma_get_info(void) __naked {
    __asm
        EXTERN __dma_get_info
        jp __dma_get_info
    __endasm;
}

void dma_uninstall(void) __naked {
    __asm
        EXTERN __dma_uninstall
        jp __dma_uninstall
    __endasm;
}

void dma_start(const dma_req_t* req) __z88dk_fastcall __naked {
    req;
    __asm
        EXTERN __dma_start
        jp __dma_start
    __endasm;
}

void dma_wait(void) __naked {
    __asm
        EXTERN __dma_wait
        jp __dma_wait
    __endasm;
}

uint8_t dma_busy(void) __naked {
    __asm
        EXTERN __dma_busy
        call __dma_busy
        ld l, a
        ret
    __endasm;
}

uint32_t dma_phys(const void* cpu_addr) __z88dk_fastcall __naked {
    cpu_addr;
    __asm
        EXTERN __dma_phys
        jp __dma_phys
    __endasm;
}

static void set24(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
}

void dma_rect(uint32_t src, uint32_t dst, uint16_t width, uint16_t height,
              int16_t src_stride, int16_t dst_stride, uint8_t mode, uint8_t key) {
    dma_req_t req;                  /* en la pila: tambien se usa desde interrupciones */
    set24(req.src, src);
    set24(req.dst, dst);
    req.width = width;
    req.height = height;
    req.src_stride = src_stride;
    req.dst_stride = dst_stride;
    req.key = key;
    req.mode = mode;
    dma_start(&req);
    dma_wait();
}

void dma_copy(uint32_t src, uint32_t dst, uint16_t len) {
    dma_rect(src, dst, len, 1, 0, 0, DMA_MODE_COPY, 0);
}

void dma_fill(uint32_t dst, uint8_t value, uint16_t len) {
    dma_rect(0, dst, len, 1, 0, 0, DMA_MODE_FILL, value);
}
