; =============================================================================
; KBD.ASM - Driver polimorfico de teclado (Aleste LX BIOS)
; Shaeon (Carlos Palmero), para el modo LX del core aleste520ex.
;
; Interfaz en registros:
;   __kbd_detect      -> A = 1 si hay teclado
;   __kbd_install     -> A = 0 (interrupcion por la linea 7; necesita int)
;   __kbd_get_info    -> HL = DriverInfo
;   __kbd_command     A = orden, HL = parametro -> HL
;   __kbd_uninstall
;   __kbd_hit         -> A = 1 si hay caracteres esperando
;   __kbd_getc        -> A = caracter (espera a que haya)
;   __kbd_shift_state -> A: bit 0 mayusculas (shift), 1 control, 2 bloq mayus
;   __kbd_row         A = fila 0-10 de la matriz del 520EX/CPC -> A (activo a 0)
; Caracteres: ASCII; 80h-88h cursores e inicio/fin/paginas/insert, 7Fh
; suprimir, 90h-99h F1-F10. Control+letra da 01h-1Ah.
; =============================================================================

module kbd_driver

include "../../inc/bios/undefined_method.inc"

SECTION DRV_VTABLE

PUBLIC __kbd_vtable
PUBLIC __kbd_detect, __kbd_install, __kbd_get_info, __kbd_command, __kbd_uninstall
PUBLIC __kbd_hit, __kbd_getc, __kbd_shift_state, __kbd_row

__kbd_vtable:
__kbd_detect:      jp _undefined_method
__kbd_install:     jp _undefined_method
__kbd_get_info:    jp _undefined_method
__kbd_command:     jp _undefined_method
__kbd_uninstall:   jp _undefined_method
__kbd_hit:         jp _undefined_method
__kbd_getc:        jp _undefined_method
__kbd_shift_state: jp _undefined_method
__kbd_row:         jp _undefined_method
__kbd_vtable_end:

SECTION DRV_CODE

PUBLIC __kbd_activate_driver
__kbd_activate_driver:
    ld (current_driver), hl
    ld de, __kbd_vtable
    ld bc, __kbd_vtable_end - __kbd_vtable
    ldir
    ret

PUBLIC __kbd_get_current_vtable
__kbd_get_current_vtable:
    ld hl, (current_driver)
    ret

SECTION DRV_DATA
current_driver: dw 0
