; =============================================================================
; DMA.ASM - Driver polimorfico de DMA / blitter (Aleste LX BIOS)
; Shaeon (Carlos Palmero), para el modo LX del core aleste520ex.
;
; Peticion (16 bytes, HL apunta a ella), en el orden de los registros:
;   +0  src   (3 bytes, direccion fisica, byte bajo primero)
;   +3  dst   (3 bytes)
;   +6  ancho en bytes (2), +8 alto en lineas (2)
;   +10 paso de linea del origen (2, con signo), +12 del destino (2)
;   +14 key: byte de relleno o color transparente
;   +15 modo: 0 copia, 1 relleno, 2 copia con transparente
;
; Interfaz en registros:
;   __dma_detect      -> A = 1 si hay DMA
;   __dma_install     -> A = 0
;   __dma_get_info    -> HL = DriverInfo
;   __dma_command     A = orden, HL = parametro -> HL
;   __dma_uninstall
;   __dma_start       HL = peticion; arranca sin esperar (espera antes a que
;                     acabe la anterior)
;   __dma_wait        espera a que acabe
;   __dma_busy        -> A = 1 si esta trabajando
;   __dma_phys        HL = direccion de la CPU -> DEHL = direccion fisica
;                     (con el mapa actual de la MMU, slots del supervisor)
; Se puede usar desde una rutina de interrupcion: start programa con las
; interrupciones cerradas y espera antes a que acabe la transferencia en curso.
; =============================================================================

module dma_driver

include "../../inc/bios/undefined_method.inc"

SECTION DRV_VTABLE
ALIGN 32

PUBLIC __dma_vtable
PUBLIC __dma_detect, __dma_install, __dma_get_info, __dma_command, __dma_uninstall
PUBLIC __dma_start, __dma_wait, __dma_busy, __dma_phys

__dma_vtable:
__dma_detect:    jp _undefined_method
__dma_install:   jp _undefined_method
__dma_get_info:  jp _undefined_method
__dma_command:   jp _undefined_method
__dma_uninstall: jp _undefined_method
__dma_start:     jp _undefined_method
__dma_wait:      jp _undefined_method
__dma_busy:      jp _undefined_method
__dma_phys:      jp _undefined_method
__dma_vtable_end:

SECTION DRV_CODE

PUBLIC __dma_activate_driver
__dma_activate_driver:
    ld (current_driver), hl
    ld de, __dma_vtable
    ld bc, __dma_vtable_end - __dma_vtable
    ldir
    ret

PUBLIC __dma_get_current_vtable
__dma_get_current_vtable:
    ld hl, (current_driver)
    ret

SECTION DRV_DATA
current_driver: dw 0
