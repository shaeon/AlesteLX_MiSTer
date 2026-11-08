; systest.asm - SYSTEST.COM: prototipo de la llamada al sistema RST 6 del LX
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer y el emulador alestelx.
;
; Un nucleo minimo (este programa, en modo supervisor dentro del LX-DOS) pone
; en marcha un programa en MODO USUARIO y le atiende las llamadas al sistema
; con el formato propuesto con hww:
;
;       RST 30h
;       DB  0FFh            ; slot FFh = el supervisor (los demas, CALLF de MSX)
;       DW  numero          ; numero de funcion, no una direccion
;       ; argumentos y resultado en registros (HL resultado, acarreo = error)
;
; La MMU entra al supervisor en el M1 de 0030h (bit 3 del control, provisional)
; y en el de 0038h (interrupciones, bit 2). Mapas:
;
;   pagina  supervisor (el nucleo)        usuario
;   0       slot 3, TPA (este programa)   slot 2, banco 40h (fisica 900000h): privada
;   1       slot 3, TPA                   slot 2, banco 41h: privada
;   2       slot 3, TPA: COMPARTIDA (pila del usuario, codigo de salida)
;   3       slot 3, drivers: COMPARTIDA
;
; La salida al usuario (OUT (F0h) con el bit 0 a 0: sale en el M1 siguiente;
; POP AF; EI; RET) esta en la pagina compartida, porque las instrucciones de
; despues del OUT se leen ya con el mapa del usuario.
;
; Funciones: 0 terminar, 1 imprimir el caracter de E, 2 HL + 1, 3 nula.
; El programa de usuario comprueba resultados y errores, escribe en su pagina
; privada y en la compartida, hace 1000 llamadas nulas (para medir) y espera
; ~1 s en modo usuario: pulsando teclas mientras, llegan interrupciones
; (con los programas en marcha, el LX-DOS solo deja la linea del teclado).
; pasmo systest.asm SYSTEST.COM systest.sym
BDOS     equ 5
CTRL_USR equ 0Eh               ; nativo, trampas 0038h/0066h, RST 6; bit 0 = 0: usuario
UBANK0   equ 40h               ; bancos del usuario en el slot 2
UBANK1   equ 41h
STUB     equ 0A000h            ; en la pagina compartida
STUB_EI  equ STUB
STUB_DI  equ STUB + 5
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
        ld hl, 0030h
        ld de, sv_30
        ld bc, 3
        ldir
        ld hl, 0038h
        ld de, orig_isr        ; JP __dos_isr_gate del LX-DOS
        ld bc, 3
        ldir
        ld a, 0C3h             ; los vectores del nucleo
        ld (0030h), a
        ld hl, sys_entry
        ld (0031h), hl
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
        ld a, 0C3h             ; los mismos vectores en la pagina 0 del usuario
        ld (4030h), a
        ld hl, sys_entry
        ld (4031h), hl
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
        push af
        ld a, 1
        ld (ctx_user), a
        ld a, CTRL_USR
        jp STUB_EI

; ---------------------------------------------------------------- llamadas
; Entrada desde el RST 30h del usuario (su 0030h y el del nucleo: JP aqui).
; Pila: [vuelta (apunta al DB 0FFh)]
sys_entry:
        push af
        ld a, i                ; P/V = IFF2: si el usuario tenia interrupciones
        di
        push af                ; pila: [vuelta][AF usuario][AF con IFF]
        ld (a_hl), hl
        ld (a_de), de
        ld (a_bc), bc
        ld (a_ix), ix
        ld (a_iy), iy
        xor a
        ld (ctx_user), a
        ld hl, 4
        add hl, sp
        ld (retp), hl          ; donde esta la vuelta
        ld e, (hl)
        inc hl
        ld d, (hl)             ; DE = vuelta: los 3 bytes de detras del RST
        call uread
        ld (sc_slot), a
        inc de
        call uread
        ld (sc_id), a
        inc de
        call uread
        ld (sc_id + 1), a
        inc de
        ld hl, (retp)          ; vuelve detras de los 3 bytes
        ld (hl), e
        inc hl
        ld (hl), d
        ld hl, (nsys)
        inc hl
        ld (nsys), hl
        ld a, (sc_slot)
        inc a
        jr nz, sc_bad          ; slot distinto de FFh: aqui no hay CALLF de MSX
        ld hl, (sc_id)
        ld a, h
        or a
        jr nz, sc_bad
        ld a, l
        cp NFUNC
        jr nc, sc_bad
        add a, a
        ld e, a
        ld d, 0
        ld hl, sc_table
        add hl, de
        ld e, (hl)
        inc hl
        ld d, (hl)
        ld (hcall + 1), de
        ld bc, (a_bc)
        ld de, (a_de)
        ld hl, (a_hl)
hcall:  call 0                 ; HL = resultado, acarreo = error
        jr sc_ret
sc_bad: ld hl, (a_hl)
        scf
sc_ret: ld (a_hl), hl
        sbc a, a               ; A = FFh con acarreo
        and 1
        ld c, a
        ld hl, 2
        add hl, sp             ; el F del usuario en la pila
        ld a, (hl)
        and 0FEh
        or c
        ld (hl), a
        ld bc, (a_bc)
        ld de, (a_de)
        ld hl, (a_hl)
        ld ix, (a_ix)
        ld iy, (a_iy)
        pop af                 ; P/V = IFF2 de la entrada
        ld a, 1
        ld (ctx_user), a
        ld a, CTRL_USR
        jp pe, STUB_EI
        jp STUB_DI

; Un byte de la memoria del usuario: DE = su direccion -> A. Sus paginas 2 y 3
; son las del nucleo; las 0 y 1 se ven poniendo su banco del slot 2 en la
; ventana 1 del nucleo.
uread:  ld a, d
        cp 80h
        jr c, ur_priv
        ld a, (de)
        ret
ur_priv:
        push hl
        ld a, UBANK0
        bit 6, d
        jr z, ur_b
        ld a, UBANK1
ur_b:   out (0E9h), a
        ld a, 0FBh
        out (0FAh), a
        ld a, d
        and 3Fh
        or 40h
        ld h, a
        ld l, e
        ld a, (hl)
        push af
        ld a, 0FFh
        out (0FAh), a
        ld a, UBANK1
        out (0E9h), a
        pop af
        pop hl
        ret

sc_table:
        dw f_exit, f_putc, f_echo, f_null
NFUNC   equ ($ - sc_table) / 2

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
        jp STUB_EI             ; al usuario, a donde lo interrumpieron
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
        ld hl, sv_30
        ld de, 0030h
        ld bc, 3
        ldir
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
; Se copia a STUB (pagina compartida). Tras el OUT, la CPU ya lee con el mapa
; del usuario: POP AF, EI/NOP y RET tienen que estar en las dos.
stub_src:
        out (0F0h), a          ; STUB_EI
        pop af
        ei
        ret
        out (0F0h), a          ; STUB_DI
        pop af
        nop
        ret
stub_end:

; ---------------------------------------------------------------- usuario
; Corre en su 0100h (pagina privada): sin direcciones absolutas propias.
uimg:
        ld e, 'U'
        rst 30h
        db 0FFh
        dw 1
        ld e, ':'
        rst 30h
        db 0FFh
        dw 1
        ld e, ' '
        rst 30h
        db 0FFh
        dw 1
        ld hl, 1233h           ; eco: 1234h
        rst 30h
        db 0FFh
        dw 2
        ld e, 'E'
        ld a, h
        cp 12h
        jr nz, u_e1
        ld a, l
        cp 34h
        jr z, u_e2
u_e1:   ld e, 'e'
u_e2:   rst 30h
        db 0FFh
        dw 1
        rst 30h                ; slot 01h: no es del supervisor: acarreo
        db 01h
        dw 0
        ld e, 'S'
        jr c, u_s
        ld e, 's'
u_s:    rst 30h
        db 0FFh
        dw 1
        rst 30h                ; funcion que no existe: acarreo
        db 0FFh
        dw 0777h
        ld e, 'F'
        jr c, u_f
        ld e, 'f'
u_f:    rst 30h
        db 0FFh
        dw 1
        ld a, 5Ah              ; su pagina privada
        ld (4000h), a
        ld a, 0A5h             ; la compartida
        ld (SHARED), a
        ld bc, 1000            ; 1000 llamadas nulas
uloop:  rst 30h
        db 0FFh
        dw 3
        dec bc
        ld a, b
        or c
        jr nz, uloop
uend:   ld d, 10               ; ~1 s solo en modo usuario: si se pulsan
u_w1:   ld bc, 0                ; teclas, llegan interrupciones (el LX-DOS solo
                               ; deja la del teclado) y tienen que volver aqui
u_w2:   dec bc
        ld a, b
        or c
        jr nz, u_w2
        dec d
        jr nz, u_w1
        ld e, '.'
        rst 30h
        db 0FFh
        dw 1
        rst 30h                ; terminar
        db 0FFh
        dw 0
        jr $
uimg_end:
ULOOP   equ uloop - uimg + 100h
UEND    equ uend - uimg + 100h

; ---------------------------------------------------------------- datos
m_banner: db "SYSTEST: RST 6 syscalls from user mode", 13, 10, "user> $"
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
retp:     dw 0
a_hl:     dw 0
a_de:     dw 0
a_bc:     dw 0
a_ix:     dw 0
a_iy:     dw 0
sc_slot:  db 0
sc_id:    dw 0
sv_30:    ds 3
sv_e8:    db 0
sv_e9:    db 0
sv_fb:    db 0
sv_f0:    db 0
k4000:    db 0
u4000:    db 0
