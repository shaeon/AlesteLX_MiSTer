; =============================================================================
; BOOT.ASM - Arranque de un sistema cargado del disco (LXDOS.SYS)
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
;
; La ROM carga el sistema en el slot 3, bancos 20h-22h (C80000-C8AFFF) y
; llama a __boot_jump, que esta en la parte residente (ventana 3, C000-FFFF):
; con las interrupciones cerradas, pone los bancos 20h-22h en las ventanas
; 0-2 y salta a 0000h. La ventana 3 sigue con los drivers, que el sistema usa
; por sus direcciones fijas (ABI). El video no ocupa ninguna ventana (la
; consola dibuja con la DMA).
; =============================================================================

module boot

defc SYS_BANK0 = 0x20
defc SYS_BANK1 = 0x21
defc SYS_BANK2 = 0x22

SECTION DRV_CODE

PUBLIC __boot_jump
__boot_jump:
    di
    ld a, SYS_BANK0
    out (0xFC), a               ; ventana 0
    ld a, SYS_BANK1
    out (0xFD), a               ; ventana 1
    ld a, SYS_BANK2
    out (0xFE), a               ; ventana 2 (la pila del sistema, arriba)
    jp 0x0000

; Vuelve a la ROM (el monitor): ventanas 0-2 a los bancos 0-2 de la BIOS y
; salta a 0000h, como un reset
PUBLIC __boot_rom
__boot_rom:
    di
    xor a
    out (0xFC), a
    inc a
    out (0xFD), a
    inc a
    out (0xFE), a
    jp 0x0000
