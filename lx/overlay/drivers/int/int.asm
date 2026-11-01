; =============================================================================
; INT.ASM - Driver polimorfico de interrupciones (Aleste LX BIOS)
; Shaeon (Carlos Palmero), para el modo LX del core aleste520ex.
;
; Mismo esquema que los drivers de hww: la VTable polimorfica esta en una
; direccion fija (DRV_VTABLE) y __int_activate_driver copia encima la del
; driver concreto. El vector de IM 1 (0038h, crt0) salta a __int_isr.
;
; Interfaz en registros:
;   __int_detect          -> A = 1 si hay controlador
;   __int_install         -> A = 0 (IM 1, todo enmascarado, EI)
;   __int_get_info        -> HL = DriverInfo
;   __int_command         A = orden, HL = parametro -> HL
;   __int_uninstall       DI, todo enmascarado
;   __int_set_handler     A = linea (0-15), HL = rutina (0 = ninguna)
;   __int_enable          A = linea
;   __int_disable         A = linea
;   __int_isr             punto de entrada de IM 1
; Las rutinas se llaman con A = linea, con la pagina MMIO ya guardada (el
; despachador la restaura) y pueden usar todos los registros salvo SP.
; =============================================================================

module int_driver

include "../../inc/bios/undefined_method.inc"

SECTION DRV_VTABLE
ALIGN 32

PUBLIC __int_vtable
PUBLIC __int_detect, __int_install, __int_get_info, __int_command, __int_uninstall
PUBLIC __int_set_handler, __int_enable, __int_disable, __int_isr

__int_vtable:
__int_detect:      jp _undefined_method
__int_install:     jp _undefined_method
__int_get_info:    jp _undefined_method
__int_command:     jp _undefined_method
__int_uninstall:   jp _undefined_method
__int_set_handler: jp _undefined_method
__int_enable:      jp _undefined_method
__int_disable:     jp _undefined_method
__int_isr:         jp int_null_isr       ; sin driver: vuelve sin hacer nada
__int_vtable_end:

SECTION DRV_CODE

int_null_isr:
    ei
    reti

; HL = VTable del driver concreto
PUBLIC __int_activate_driver
__int_activate_driver:
    ld (current_driver), hl
    ld de, __int_vtable
    ld bc, __int_vtable_end - __int_vtable
    ldir
    ret

PUBLIC __int_get_current_vtable
__int_get_current_vtable:
    ld hl, (current_driver)
    ret

SECTION DRV_DATA
current_driver: dw 0
