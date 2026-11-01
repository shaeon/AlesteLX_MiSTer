; =============================================================================
; TIMER.ASM - Driver polimorfico del temporizador (Aleste LX BIOS)
; Shaeon (Carlos Palmero), para el modo LX del core aleste520ex.
;
; Interfaz en registros:
;   __timer_detect        -> A = 1 si hay temporizador
;   __timer_install       -> A = 0
;   __timer_get_info      -> HL = DriverInfo
;   __timer_command       A = orden, HL = parametro -> HL
;   __timer_uninstall     para el temporizador periodico
;   __timer_get_ms        -> HL = milisegundos desde el arranque (16 bits, da la vuelta)
;   __timer_delay_ms      HL = milisegundos que espera
;   __timer_set_periodic  HL = periodo en microsegundos, DE = rutina
;                         (se llama desde la interrupcion; DE = 0 la para).
;                         Necesita el driver de interrupciones instalado.
;   __timer_get_count     -> HL = veces que ha saltado el periodico
; =============================================================================

module timer_driver

include "../../inc/bios/undefined_method.inc"

SECTION DRV_VTABLE
ALIGN 32

PUBLIC __timer_vtable
PUBLIC __timer_detect, __timer_install, __timer_get_info, __timer_command, __timer_uninstall
PUBLIC __timer_get_ms, __timer_delay_ms, __timer_set_periodic, __timer_get_count

__timer_vtable:
__timer_detect:       jp _undefined_method
__timer_install:      jp _undefined_method
__timer_get_info:     jp _undefined_method
__timer_command:      jp _undefined_method
__timer_uninstall:    jp _undefined_method
__timer_get_ms:       jp _undefined_method
__timer_delay_ms:     jp _undefined_method
__timer_set_periodic: jp _undefined_method
__timer_get_count:    jp _undefined_method
__timer_vtable_end:

SECTION DRV_CODE

PUBLIC __timer_activate_driver
__timer_activate_driver:
    ld (current_driver), hl
    ld de, __timer_vtable
    ld bc, __timer_vtable_end - __timer_vtable
    ldir
    ret

PUBLIC __timer_get_current_vtable
__timer_get_current_vtable:
    ld hl, (current_driver)
    ret

SECTION DRV_DATA
current_driver: dw 0
