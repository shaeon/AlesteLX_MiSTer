; =============================================================================
; FDC.ASM - Driver polimorfico de disquetera (Aleste LX BIOS)
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
;
; Interfaz en registros:
;   __fdc_detect      -> A = 1 si hay controlador
;   __fdc_install     -> A = 0 (SPECIFY sin DMA, motor en marcha, recalibra A:)
;   __fdc_get_info    -> HL = DriverInfo
;   __fdc_command     A = orden, HL = parametro -> HL
;   __fdc_uninstall   para el motor
;   __fdc_read        HL = bufer (512 bytes), A = unidad (0-1), D = pista,
;                     E = cara, C = sector (1-9) -> A = 0 bien, o error
;                     (bit 7: sin respuesta; si no, ST1 | ST2)
;   __fdc_status      -> A = registro de estado principal del 765
;   __fdc_read_multi  como __fdc_read, con B = numero de sectores seguidos de
;                     la misma pista y cara (1-9): una sola orden, sin perder
;                     vueltas entre sectores
;   __fdc_write_multi lo mismo para escribir (HL = datos); error con ST1 bit 1
;                     si el disco esta protegido
; =============================================================================

module fdc_driver

include "../../inc/bios/undefined_method.inc"

SECTION DRV_VTABLE

PUBLIC __fdc_vtable
PUBLIC __fdc_detect, __fdc_install, __fdc_get_info, __fdc_command, __fdc_uninstall
PUBLIC __fdc_read, __fdc_status, __fdc_read_multi, __fdc_write_multi

__fdc_vtable:
__fdc_detect:    jp _undefined_method
__fdc_install:   jp _undefined_method
__fdc_get_info:  jp _undefined_method
__fdc_command:   jp _undefined_method
__fdc_uninstall: jp _undefined_method
__fdc_read:      jp _undefined_method
__fdc_status:    jp _undefined_method
__fdc_read_multi: jp _undefined_method
__fdc_write_multi: jp _undefined_method
__fdc_vtable_end:

SECTION DRV_CODE

PUBLIC __fdc_activate_driver
__fdc_activate_driver:
    ld (current_driver), hl
    ld de, __fdc_vtable
    ld bc, __fdc_vtable_end - __fdc_vtable
    ldir
    ret

SECTION DRV_DATA
current_driver: dw 0
