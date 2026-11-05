; crt0_dos.asm - Arranque de LXDOS.SYS (Aleste LX)
; Shaeon (Carlos Palmero). La ROM lo carga en los bancos 20h-21h y salta a
; 0000h con los bancos 20h-22h en las ventanas 0-2 y las interrupciones
; cerradas. La pila va arriba de la ventana 2; la 3 son los drivers residentes.
EXTERN _main
EXTERN __int_isr
INCLUDE "abi_id.inc"
SECTION code_crt_start
    di
    ld sp, 0xC000
    jp start
    defm "LXDS"                 ; 0007h: cabecera que comprueba la ROM
    defw ABI_ID                 ; 000Bh: huella de la ABI de la ROM (build.sh)
    defs 0x0038 - $
    jp __int_isr                ; IM 1: el despachador de interrupciones de la ROM
    defs 0x0066 - $
    retn
start:
    call _main
    halt
