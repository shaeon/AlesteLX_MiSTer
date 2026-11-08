; user.asm - Programa en MODO USUARIO de SUPTEST.COM (prueba de RST 6)
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
; Corre en la pagina 0 del mapa de usuario (slot 2, banco 30h), desde 0100h
; como un programa de CP/M: la pagina cero es del sistema. Las trampas de la
; MMU saltan en CUALQUIER lectura de instruccion en 0030h/0038h/0066h en modo
; usuario, no solo en las de RST 6 o las interrupciones. Llama al
; sistema con el formato que proponemos a hww:
;     RST 30h / DB 0FFh / DW numero_de_funcion   (argumentos en registros)
; Deja los resultados en la pagina 1, compartida con el supervisor (5000h).
; pasmo user.asm user.bin user.sym
RESULTS     equ 5000h               ; resultados (pagina compartida)
N       equ 1000                ; llamadas en el bucle de tiempos

SYSCALL macro id
        rst 30h
        db 0FFh
        dw id
        endm

        org 100h
start:
        SYSCALL 0               ; version -> HL
        ld (RESULTS + 0), hl
        ld hl, 1234h
        ld de, 1111h
        SYSCALL 2               ; HL = HL + DE
        ld (RESULTS + 2), hl
        ; N llamadas seguidas (con las interrupciones llegando)
        ld bc, N
t_sys:  push bc
        ld hl, 1
        ld de, 1
        SYSCALL 2
        pop bc
        dec bc
        ld a, b
        or c
        jr nz, t_sys
t_sys_end:
        ; la misma suma con un CALL normal, para comparar
        ld bc, N
t_call: push bc
        ld hl, 1
        ld de, 1
        call add_local
        nop                     ; los 3 bytes que ocupa "DB 0FFh, DW id"
        nop
        nop
        pop bc
        dec bc
        ld a, b
        or c
        jr nz, t_call
t_call_end:
        ld (RESULTS + 4), bc        ; 0 si los bucles acabaron
        ; un rato en modo usuario sin llamar a nada: llegan interrupciones
        ld d, 6
busy:   ld bc, 0
busy2:  dec bc
        ld a, b
        or c
        jr nz, busy2
        dec d
        jr nz, busy
        ; un puerto de la MMU en modo usuario (con el bloqueo: FFh)
        in a, (0F0h)
        ld (RESULTS + 6), a
        ; un CALLF de MSX normal (slot distinto de FFh): no hay BIOS MSX, el
        ; nucleo devuelve A = FFh y salta los 3 bytes igualmente
        xor a
        rst 30h
        db 01h
        dw 1234h
        ld (RESULTS + 7), a
        ; un numero de funcion que no existe: A = FEh
        xor a
        SYSCALL 99
        ld (RESULTS + 8), a
        ; un mensaje por la consola del LX-DOS, letra a letra (funcion 1)
        ld hl, msg
pm:     ld a, (hl)
        or a
        jr z, pm_end
        ld e, a
        push hl
        SYSCALL 1
        pop hl
        inc hl
        jr pm
pm_end:
        ld a, 0A5h              ; marca: el programa llego al final
        ld (RESULTS + 9), a
        SYSCALL 4               ; salir (no vuelve)
        halt

add_local:
        add hl, de
        ret

msg:    db "Hello from user mode, through RST 6", 13, 10, 0
