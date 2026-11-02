; =============================================================================
; SND.ASM - Driver polimorfico de sonido por muestras (Aleste LX BIOS)
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
;
; Voz (16 bytes, HL apunta a ella), en el orden de los registros del canal:
;   +0  canal (0-3)
;   +1  control: bit 1 bucle, bit 2 muestras de 16 bits, bit 3 IRQ al terminar
;   +2  inicio (3 bytes, direccion fisica, byte bajo primero)
;   +5  fin (3 bytes, no incluido)
;   +8  vuelta del bucle (3 bytes)
;   +11 volumen izquierdo, +12 derecho (0-255)
;   +13 paso (3 bytes, 8.16: 010000h = 48 kHz)
;
; Interfaz en registros:
;   __snd_detect       -> A = 1 si hay Magic Sound 2
;   __snd_install      -> A = 0 (todo parado, volumen global al maximo)
;   __snd_get_info     -> HL = DriverInfo
;   __snd_command      A = orden, HL = parametro -> HL
;   __snd_uninstall    todo parado
;   __snd_play         HL = voz: la programa y la hace sonar desde el inicio
;   __snd_stop         A = canal
;   __snd_set_volume   A = canal, D = izquierdo, E = derecho
;   __snd_set_step     A = canal, E:HL = paso 8.16 (cambia el tono al vuelo)
;   __snd_master       D = izquierdo, E = derecho
;   __snd_status       -> A: bits 7-4 sonando, bits 3-0 terminado
;   __snd_set_timer    HL = periodo en muestras de 48 kHz (960 = 50 Hz),
;                      DE = rutina (0 = parar). Linea 3 del PIC (necesita int).
; =============================================================================

module snd_driver

include "../../inc/bios/undefined_method.inc"

SECTION DRV_VTABLE

PUBLIC __snd_vtable
PUBLIC __snd_detect, __snd_install, __snd_get_info, __snd_command, __snd_uninstall
PUBLIC __snd_play, __snd_stop, __snd_set_volume, __snd_set_step, __snd_master
PUBLIC __snd_status, __snd_set_timer

__snd_vtable:
__snd_detect:     jp _undefined_method
__snd_install:    jp _undefined_method
__snd_get_info:   jp _undefined_method
__snd_command:    jp _undefined_method
__snd_uninstall:  jp _undefined_method
__snd_play:       jp _undefined_method
__snd_stop:       jp _undefined_method
__snd_set_volume: jp _undefined_method
__snd_set_step:   jp _undefined_method
__snd_master:     jp _undefined_method
__snd_status:     jp _undefined_method
__snd_set_timer:  jp _undefined_method
__snd_vtable_end:

SECTION DRV_CODE

PUBLIC __snd_activate_driver
__snd_activate_driver:
    ld (current_driver), hl
    ld de, __snd_vtable
    ld bc, __snd_vtable_end - __snd_vtable
    ldir
    ret

PUBLIC __snd_get_current_vtable
__snd_get_current_vtable:
    ld hl, (current_driver)
    ret

SECTION DRV_DATA
current_driver: dw 0
