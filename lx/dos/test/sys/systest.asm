; systest.asm - SYSTEST.COM: prototipo de la llamada al sistema OUT (F2h),A del LX
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer y el emulador alestelx.
;
; Un nucleo minimo (este programa, en modo supervisor dentro del LX-DOS) pone
; en marcha un programa en MODO USUARIO y le atiende las llamadas al sistema
; con el mecanismo acordado con hww: escribir en el puerto F2h entra al
; supervisor (la MMU cambia de mapa para la instruccion siguiente). El numero
; de funcion va en A y los argumentos en registros (resultado en HL, acarreo =
; error): el nucleo no lee nada de la memoria del usuario.
;
;       LD   A, funcion
;       CALL SYSCALL        ; trampolin en la pagina compartida
;
; SYSCALL (pagina compartida): guarda IFF y desactiva las interrupciones, hace
; OUT (F2h),A, y la instruccion siguiente (JP al nucleo) ya se lee con el mapa
; del supervisor; como la pagina es compartida, es el mismo codigo. La vuelta
; (OUT (F0h) con el bit 0 a 0: sale en el M1 siguiente; el acarreo; EI; RET)
; tambien esta en la pagina compartida. Las interrupciones en modo usuario
; entran por la trampa de 0038h (bit 2 del control). Mapas:
;
;   pagina  supervisor (el nucleo)        usuario
;   0       slot 3, TPA (este programa)   slot 2, banco 40h (fisica 900000h): privada
;   1       slot 3, TPA                   slot 2, banco 41h: privada
;   2       slot 3, TPA: COMPARTIDA (pila del usuario, SYSCALL, salida, variables)
;   3       slot 3, drivers: COMPARTIDA
;
; Funciones: 0 terminar, 1 imprimir el caracter de E, 2 HL + 1, 3 nula.
; El programa de usuario comprueba resultados y errores, escribe en su pagina
; privada y en la compartida, hace 1000 llamadas nulas (para medir) y espera
; ~1 s en modo usuario: pulsando teclas mientras, llegan interrupciones
; (con los programas en marcha, el LX-DOS solo deja la linea del teclado).
; pasmo systest.asm SYSTEST.COM systest.sym
BDOS     equ 5
CTRL_USR equ 06h               ; nativo, trampas 0038h/0066h; bit 0 = 0: usuario
UBANK0   equ 40h               ; bancos del usuario en el slot 2
UBANK1   equ 41h
STUB     equ 0A000h            ; en la pagina compartida: SYSCALL y la salida
SYSCALL  equ STUB
R_C      equ 0A050h            ; compartidas: acarreo de vuelta, funcion
FN_TMP   equ 0A051h
USTACK   equ 0A800h
SHARED   equ 0A030h            ; dato que el usuario escribe en la pagina compartida

        org 100h
start:  ld de, m_banner
        ld c, 9
        call BDOS
        ; ---- lo que se toca, para dejarlo igual
        in a, (0E8h)
        ld (sv_e8), a
        in a, (0E9h)
        ld (sv_e9), a
        in a, (0FBh)
        ld (sv_fb), a
        in a, (0F0h)
        ld (sv_f0), a
        di
        ld hl, 0038h
        ld de, orig_isr        ; JP __dos_isr_gate del LX-DOS
        ld bc, 3
        ldir
        ld a, 0C3h             ; el vector de interrupciones del nucleo
        ld (0038h), a
        ld hl, isr_wrap
        ld (0039h), hl
        ; ---- la memoria del usuario: su pagina 0 por la ventana 1 del nucleo
        ld a, UBANK0
        out (0E8h), a          ; slot 2, pagina 0
        out (0E9h), a          ; (de paso) slot 2, pagina 1 -> el banco 40h
        ld a, 0FBh             ; pagina 1 del supervisor -> slot 2
        out (0FAh), a
        ld hl, 4000h           ; limpia la pagina cero del usuario
        ld de, 4001h
        ld bc, 0FFh
        ld (hl), 0
        ldir
        ld a, 0C3h             ; el mismo en la pagina 0 del usuario
        ld (4038h), a
        ld hl, isr_wrap
        ld (4039h), hl
        ld hl, uimg            ; el programa de usuario, en su 0100h
        ld de, 4100h
        ld bc, uimg_end - uimg
        ldir
        ld a, UBANK1           ; su pagina 1: el dato privado a 0
        out (0E9h), a
        xor a
        ld (4000h), a
        ld a, 0FFh             ; el nucleo, otra vez todo en el slot 3
        out (0FAh), a
        xor a
        ld (4000h), a          ; el 4000h del nucleo (TPA) a 0
        ld (SHARED), a
        ld hl, stub_src        ; la salida, en la pagina compartida
        ld de, STUB
        ld bc, stub_end - stub_src
        ldir
        ld a, 0FAh             ; usuario: paginas 0-1 slot 2, 2-3 slot 3
        out (0FBh), a
        ; ---- al usuario, en 0100h
        ld (ksp), sp
        ld sp, USTACK
        ld hl, 0100h
        push hl
        xor a
        ld (R_C), a
        ld a, 1
        ld (ctx_user), a
        ld a, CTRL_USR
        jp x_ei_s

; ---------------------------------------------------------------- llamadas
; Desde SYSCALL, ya en supervisor, con las interrupciones desactivadas.
; A = funcion; pila: [vuelta al usuario][AF con IFF]
k_entry:
        ld (a_hl), hl
        ld hl, ctx_user
        ld (hl), 0
        ld hl, (nsys)
        inc hl
        ld (nsys), hl
        ld hl, (a_hl)
        cp NFUNC
        jr nc, k_bad
        ld l, a                ; JP numero A de la tabla (alineada a 256)
        add a, a
        add a, l
        ld l, a
        ld h, jtab / 256
        ld (hcall + 1), hl
        ld hl, (a_hl)
hcall:  call 0                 ; HL = resultado, acarreo = error
        jr k_ret
k_bad:  scf
k_ret:  sbc a, a               ; A = FFh con acarreo
        ld (R_C), a
        pop af                 ; P/V = IFF2 de la entrada
        ld a, 1
        ld (ctx_user), a
        ld a, CTRL_USR
        jp pe, x_ei_s
        jp x_di_s

f_exit: ld sp, (ksp)           ; al nucleo, como si volviera del arranque
        jp finish
f_putc: ld c, 2
        call BDOS
        ld hl, (a_hl)
        or a
        ret
f_echo: inc hl
        or a
        ret
f_null: or a
        ret

; ---------------------------------------------------------------- IM 1
; 0038h (trampa si estaba el usuario). La rutina del LX-DOS acaba en EI; RETI.
isr_wrap:
        push af
        ld a, (ctx_user)
        or a
        jr z, isr_sup
        xor a
        ld (ctx_user), a
        push hl
        ld hl, (nirq)
        inc hl
        ld (nirq), hl
        pop hl
        pop af
        call orig_isr
        di
        push af
        ld a, 1
        ld (ctx_user), a
        ld a, CTRL_USR
        jp X_INT               ; al usuario, a donde lo interrumpieron
isr_sup:
        pop af
orig_isr:
        ds 3                   ; JP __dos_isr_gate (copiado de 0038h)

; ---------------------------------------------------------------- fin
finish: di
        ld a, (sv_f0)          ; supervisor, sin trampas
        out (0F0h), a
        ld a, (sv_fb)
        out (0FBh), a
        ld a, (4000h)          ; el 4000h del nucleo: debe seguir a 0
        ld (k4000), a
        ld a, UBANK1           ; el 4000h del usuario: 5Ah
        out (0E9h), a
        ld a, 0FBh
        out (0FAh), a
        ld a, (4000h)
        ld (u4000), a
        ld a, 0FFh
        out (0FAh), a
        ld a, (sv_e8)
        out (0E8h), a
        ld a, (sv_e9)
        out (0E9h), a
        ld hl, orig_isr
        ld de, 0038h
        ld bc, 3
        ldir
        ei
        ld de, m_calls
        ld c, 9
        call BDOS
        ld hl, (nsys)
        call pdec
        ld de, m_irq
        ld c, 9
        call BDOS
        ld hl, (nirq)
        call pdec
        ld de, m_priv
        ld c, 9
        call BDOS
        ld a, (k4000)
        or a
        jr nz, p_fail
        ld a, (u4000)
        cp 5Ah
        jr nz, p_fail
        ld de, m_ok
        jr p_pr
p_fail: ld de, m_fail
p_pr:   ld c, 9
        call BDOS
        ld de, m_shared
        ld c, 9
        call BDOS
        ld a, (SHARED)
        cp 0A5h
        ld de, m_ok
        jr z, s_pr
        ld de, m_fail
s_pr:   ld c, 9
        call BDOS
        ret

pdec:   ld bc, -10000          ; HL en decimal
        call pd1
        ld bc, -1000
        call pd1
        ld bc, -100
        call pd1
        ld bc, -10
        call pd1
        ld bc, -1
pd1:    ld a, '0' - 1
pd2:    inc a
        add hl, bc
        jr c, pd2
        sbc hl, bc
        push hl
        ld e, a
        ld c, 2
        call BDOS
        pop hl
        ret

; ---------------------------------------------------------------- salida
; Se copia a STUB (pagina compartida). SYSCALL: tras el OUT (F2h), la CPU ya
; lee con el mapa del supervisor (JP k_entry). Salida: tras el OUT (F0h), con
; el del usuario (LD A,(R_C), RRA, EI/NOP, RET).
stub_src:
        ld (FN_TMP), a         ; SYSCALL
        ld a, i                ; P/V = IFF2
        di
        push af
        ld a, (FN_TMP)
        out (0F2h), a          ; al supervisor
        jp k_entry
X_EI    equ STUB + ($ - stub_src)
        out (0F0h), a          ; salida con EI
        ld a, (R_C)
        rra                    ; acarreo = error
        ei
        ret
X_DI    equ STUB + ($ - stub_src)
        out (0F0h), a          ; salida sin EI
        ld a, (R_C)
        rra
        nop
        ret
X_INT   equ STUB + ($ - stub_src)
        out (0F0h), a          ; vuelta de una interrupcion: AF del usuario
        pop af
        ei
        ret
stub_end:
x_ei_s  equ X_EI
x_di_s  equ X_DI

; ---------------------------------------------------------------- usuario
; Corre en su 0100h (pagina privada): sin direcciones absolutas propias.
uimg:
        ld e, 'U'
        ld a, 1
        call SYSCALL
        ld e, ':'
        ld a, 1
        call SYSCALL
        ld e, ' '
        ld a, 1
        call SYSCALL
        ld hl, 1233h           ; eco: 1234h
        ld a, 2
        call SYSCALL
        ld e, 'E'
        ld a, h
        cp 12h
        jr nz, u_e1
        ld a, l
        cp 34h
        jr z, u_e2
u_e1:   ld e, 'e'
u_e2:   ld a, 1
        call SYSCALL
        ld a, 77h              ; funcion que no existe: acarreo
        call SYSCALL
        ld e, 'F'
        jr c, u_f
        ld e, 'f'
u_f:    ld a, 1
        call SYSCALL
        ld a, 5Ah              ; su pagina privada
        ld (4000h), a
        ld a, 0A5h             ; la compartida
        ld (SHARED), a
        ld bc, 1000            ; 1000 llamadas nulas
uloop:  ld a, 3
        call SYSCALL
        dec bc
        ld a, b
        or c
        jr nz, uloop
uend:   ld d, 10               ; ~1 s solo en modo usuario: si se pulsan
u_w1:   ld bc, 0               ; teclas, llegan interrupciones (el LX-DOS solo
                               ; deja la del teclado) y tienen que volver aqui
u_w2:   dec bc
        ld a, b
        or c
        jr nz, u_w2
        dec d
        jr nz, u_w1
        ld e, '.'
        ld a, 1
        call SYSCALL
        xor a                  ; terminar
        call SYSCALL
        jr $
uimg_end:
ULOOP   equ uloop - uimg + 100h
UEND    equ uend - uimg + 100h

; ---------------------------------------------------------------- tabla
        ds (256 - ($ & 255)) & 255
jtab:   jp f_exit              ; 0
        jp f_putc              ; 1
        jp f_echo              ; 2
        jp f_null              ; 3
NFUNC   equ ($ - jtab) / 3

; ---------------------------------------------------------------- datos
m_banner: db "SYSTEST: OUT (F2h),A syscalls from user mode", 13, 10, "user> $"
m_calls:  db 13, 10, "syscalls served: $"
m_irq:    db 13, 10, "interrupts taken in user mode: $"
m_priv:   db 13, 10, "private user page: $"
m_shared: db 13, 10, "shared page: $"
m_ok:     db "OK$"
m_fail:   db "FAIL$"
ctx_user: db 0
nsys:     dw 0
nirq:     dw 0
ksp:      dw 0
a_hl:     dw 0
a_de:     dw 0
a_bc:     dw 0
a_ix:     dw 0
a_iy:     dw 0
sv_e8:    db 0
sv_e9:    db 0
sv_fb:    db 0
sv_f0:    db 0
k4000:    db 0
u4000:    db 0
