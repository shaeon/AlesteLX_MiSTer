; =============================================================================
; DOSGATE.ASM - Puertas entre los programas .COM y el LX-DOS (Aleste LX)
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
;
; Mapas de memoria (slot 3 del supervisor):
;   LX-DOS     ventanas 0-2 = bancos 20h, 21h, 22h   ventana 3 = ROM (drivers)
;   programa   ventanas 0-2 = bancos 24h, 25h, 26h   ventana 3 = ROM (drivers)
; La ventana 3 es la unica comun, asi que aqui (DRV_CODE) estan las puertas:
;
;   __dos_exec        (desde el LX-DOS) pone el mapa del programa y salta a
;                     0100h con SP = BF00h y 0000h en la pila. Vuelve cuando
;                     el programa acaba (JP 0, RET a 0000h o BDOS 0).
;   __dos_bdos_gate   CALL 5 -> JP BF00h -> aqui. Guarda C y DE, pone el mapa
;                     del LX-DOS y llama a la rutina que este haya dejado en
;                     __dos_bdos_vec (con la pila del LX-DOS); vuelve con
;                     HL, A = L y B = H, como CP/M.
;   __dos_bios_gate   la tabla del BIOS de CP/M (BF03h) llega aqui con A = n
;                     de funcion y C = caracter; llama a __dos_bios_vec.
;   __dos_isr_gate    IM 1 con el programa en marcha (su 0038h salta aqui):
;                     pone el mapa del LX-DOS, despacha la interrupcion y
;                     vuelve a dejar el mapa como estaba.
;   __dos_wboot_gate  0000h del programa: vuelve al LX-DOS (tras __dos_exec).
; =============================================================================

module dosgate

defc SYS_BANK0  = 0x20
defc SYS_BANK1  = 0x21
defc SYS_BANK2  = 0x22
defc TPA_BANK0  = 0x24
defc TPA_BANK1  = 0x25
defc TPA_BANK2  = 0x26
defc TPA_TOP    = 0xBF00

EXTERN __int_lx_dispatch

PUBLIC __dos_exec, __dos_bdos_gate, __dos_bios_gate, __dos_isr_gate, __dos_wboot_gate
PUBLIC __dos_bdos_vec, __dos_bios_vec, __dos_reg_c, __dos_reg_de, __dos_reg_a
PUBLIC __dos_xret, __dos_ret_a, __dos_ret_bc, __dos_ret_de, __dos_ret_hl, __dos_reg_hl, __dos_reg_b

SECTION DRV_CODE

map_sys:
    ld a, SYS_BANK0
    out (0xFC), a
    ld a, SYS_BANK1
    out (0xFD), a
    ld a, SYS_BANK2
    out (0xFE), a
    ret

; Nota: entre el cambio de mapa y el de SP no se usa la pila (la de un mapa
; no se ve desde el otro).

; ---- desde el LX-DOS: el programa ya esta en los bancos 24h-26h
__dos_exec:
    di
    ld (exec_sp), sp
    ld a, TPA_BANK0
    out (0xFC), a
    ld a, TPA_BANK1
    out (0xFD), a
    ld a, TPA_BANK2
    out (0xFE), a
                                ; (la pila del LX-DOS deja de verse: sin pila aqui)
    ld sp, TPA_TOP
    ld hl, 0
    push hl                     ; RET del programa = 0000h = vuelta al LX-DOS
    ei
    jp 0x0100

; ---- 0000h del programa
__dos_wboot_gate:
    di
    ld a, SYS_BANK0
    out (0xFC), a
    ld a, SYS_BANK1
    out (0xFD), a
    ld a, SYS_BANK2
    out (0xFE), a
    ld sp, (exec_sp)
    ei
    ret                         ; vuelve de __dos_exec

; ---- CALL 5 (via BF00h): C = funcion, DE = parametro
__dos_bdos_gate:
    di
    ld (prog_sp), sp
    ld (__dos_reg_de), de
    ld (__dos_reg_hl), hl
    ld a, b
    ld (__dos_reg_b), a
    ld a, c
    ld (__dos_reg_c), a
    or a
    jp z, __dos_wboot_gate      ; funcion 0: fin del programa
    ld a, SYS_BANK0             ; mapa del LX-DOS, sin tocar la pila
    out (0xFC), a
    ld a, SYS_BANK1
    out (0xFD), a
    ld a, SYS_BANK2
    out (0xFE), a
    ld sp, (exec_sp)            ; pila del LX-DOS, debajo de su llamada a __dos_exec
    ei
    push ix                     ; los del programa (el C del LX-DOS usa IX)
    push iy
    ld hl, (__dos_bdos_vec)
    call jp_hl                  ; -> HL
    pop iy
    pop ix
gate_back:
    di
    ex de, hl                   ; resultado a DE mientras cambia el mapa
    ld a, TPA_BANK0
    out (0xFC), a
    ld a, TPA_BANK1
    out (0xFD), a
    ld a, TPA_BANK2
    out (0xFE), a
    ld sp, (prog_sp)
    ld a, (__dos_xret)
    or a
    jr nz, gate_xret
    ex de, hl
    ld a, l
    ld b, h
    ld de, (__dos_reg_de)       ; DE se conserva (algunos programas lo esperan)
    ei
    ret
; Vuelta con todos los registros (funciones de MSX-DOS que devuelven A, BC,
; DE y HL a la vez): los deja el LX-DOS en __dos_ret_* y pone __dos_xret
gate_xret:
    xor a
    ld (__dos_xret), a
    ld bc, (__dos_ret_bc)
    ld de, (__dos_ret_de)
    ld hl, (__dos_ret_hl)
    ld a, (__dos_ret_a)
    ei
    ret

; ---- tabla del BIOS de CP/M: A = funcion, C = caracter
__dos_bios_gate:
    di
    ld (prog_sp), sp
    ld (__dos_reg_a), a
    ld a, c
    ld (__dos_reg_c), a
    ld a, (__dos_reg_a)
    cp 1
    jp z, __dos_wboot_gate      ; WBOOT
    ld a, SYS_BANK0
    out (0xFC), a
    ld a, SYS_BANK1
    out (0xFD), a
    ld a, SYS_BANK2
    out (0xFE), a
    ld sp, (exec_sp)
    ei
    push ix
    push iy
    ld hl, (__dos_bios_vec)
    call jp_hl
    pop iy
    pop ix
    jr gate_back

; ---- IM 1 con el programa en marcha
__dos_isr_gate:
    ld (isr_sp), sp
    ld sp, isr_stack_top
    push af
    in a, (0xFC)                ; mapa de ahora (el del programa o el del LX-DOS)
    push af
    in a, (0xFD)
    push af
    in a, (0xFE)
    push af
    call map_sys
    call __int_lx_dispatch      ; las rutinas del LX-DOS y de la ROM se ven
    pop af
    out (0xFE), a
    pop af
    out (0xFD), a
    pop af
    out (0xFC), a
    pop af
    ld sp, (isr_sp)
    ei
    reti

jp_hl:
    jp (hl)

SECTION DRV_DATA

__dos_bdos_vec: dw 0
__dos_bios_vec: dw 0
__dos_reg_c:    db 0
__dos_reg_a:    db 0
__dos_reg_de:   dw 0
__dos_reg_hl:   dw 0            ; HL y B del programa (funciones de bloque y absolutas)
__dos_reg_b:    db 0
__dos_xret:     db 0
__dos_ret_a:    db 0
__dos_ret_bc:   dw 0
__dos_ret_de:   dw 0
__dos_ret_hl:   dw 0
exec_sp:        dw 0
prog_sp:        dw 0
isr_sp:         dw 0
isr_stack:      ds 256
isr_stack_top:
