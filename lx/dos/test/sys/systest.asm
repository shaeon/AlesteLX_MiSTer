; systest.asm - SYSTEST.COM: la llamada al sistema OUT (F2h),A del LX, con el
; esquema acordado con hww (wrapper y salida en la misma direccion)
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer y el emulador alestelx.
;
; Un nucleo minimo (este programa, en modo supervisor dentro del LX-DOS) pone
; en marcha un programa en MODO USUARIO y le atiende las llamadas al sistema.
; El numero de funcion va en A, los argumentos en registros; el resultado en
; HL y el error en el acarreo; A se pierde. WRAP (7F00h) esta en la pagina 1,
; que es DISTINTA en los dos mapas:
;
;   direccion  mapa del usuario     mapa del supervisor
;   7F00h      OUT (F2h),A          OUT (F0h),A      (salida)
;   7F02h      NOP                  NOP              (byte de transicion)
;   7F03h      EI                   prologo del nucleo (sin DI)
;   7F04h      RET                  ...
;
; Regla del hardware (mmu_native.sv): el cambio de modo en un M1 (la salida
; pendiente tras OUT (F0h), o una trampa) se registra cuando la direccion de
; ESE codigo de operacion ya ha salido: se lee todavia con el mapa anterior, y
; sus operandos, la pila y lo siguiente, con el nuevo. Por eso 7F02h tiene la
; misma instruccion de un byte en los dos mapas. (La entrada por OUT (F2h)
; cambia en la propia escritura: 7F02h ya se lee del supervisor.)
;
; El programa hace CALL 7F00h: tras el OUT (F2h),A, 7F02h y lo siguiente son
; del supervisor (el nucleo). El nucleo guarda el SP del usuario en 4FFEh y usa
; su pila, debajo, en su pagina 1 (W1, como en el diseno de hww). Al terminar
; restaura el SP y salta a 7F00h, donde en su mapa esta OUT (F0h),A: tras el
; NOP de 7F02h, 7F03h (EI) y 7F04h (RET) ya se leen del mapa del usuario: el
; RET del wrapper es la vuelta. OUT no toca los indicadores: el acarreo llega
; al usuario.
;
; Interrupciones en modo usuario: entran por la trampa de 0038h. Para volver
; hay que restaurar AF entero, y la instruccion que lo hace (POP AF) se lee ya
; del mapa del usuario: la pila del usuario tiene que estar en una pagina que
; vean los dos mapas (aqui la 2). Carrera sin DI: si llega una interrupcion
; justo tras el OUT (F2h),A (en el prologo, antes de cambiar de pila), la rutina
; ve una direccion de vuelta del prologo y vuelve al nucleo (contadas en
; "races"). La salida si desactiva las interrupciones (de ahi el EI del
; wrapper). Un bit de estado de hardware ("entrada desde el usuario", la
; recomendacion 19 de hww) evitaria las dos cosas.
;
;   pagina  supervisor (el nucleo)        usuario
;   0       slot 3, TPA (este programa)   slot 2, banco 40h: privada (su programa)
;   1       slot 3, TPA (WRAP, su pila)   slot 2, banco 41h: privada (su WRAP)
;   2       slot 3, TPA: COMPARTIDA (pila del usuario, vuelta de interrupciones)
;   3       slot 3, drivers: COMPARTIDA
;
; Funciones: 0 terminar, 1 imprimir el caracter de E, 2 HL + 1, 3 nula.
; El programa de usuario comprueba resultados y errores, escribe en su pagina
; privada y en la compartida, hace 20000 llamadas nulas (para medir) y espera
; ~1 s en modo usuario: pulsando teclas mientras, llegan interrupciones. Con
; los programas en marcha, el LX-DOS solo deja la linea del teclado; durante la
; prueba se activa tambien la del VBlank (2), para que lleguen a menudo.
; pasmo systest.asm SYSTEST.COM systest.sym
BDOS     equ 5
CTRL_USR equ 06h               ; nativo, trampas 0038h/0066h; bit 0 = 0: usuario
UBANK0   equ 40h               ; bancos del usuario en el slot 2
UBANK1   equ 41h
STUB     equ 0A000h            ; en la pagina compartida: vuelta de interrupciones
NCALLS   equ 20000             ; llamadas nulas del bucle (para medir)
VBLANK   equ 0                 ; 1 = activar el VBlank durante la prueba (estres de la carrera; en el core aun se cuelga)
WRAP     equ 7F00h             ; pagina 1: wrapper (usuario) / salida (supervisor)
KSP_SAVE equ 4FFEh             ; SP del usuario; debajo, la pila del nucleo (W1)
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
        ld a, UBANK1           ; su pagina 1: el dato privado a 0 y su WRAP
        out (0E9h), a
        xor a
        ld (4000h), a
        ld hl, uwrap
        ld de, WRAP
        ld bc, uwrap_end - uwrap
        ldir
        ld a, 0FFh             ; el nucleo, otra vez todo en el slot 3
        out (0FAh), a
        xor a
        ld (4000h), a          ; el 4000h del nucleo (TPA) a 0
        ld hl, swrap           ; en su pagina 1: la salida y el prologo
        ld de, WRAP
        ld bc, swrap_end - swrap
        ldir
        ld (SHARED), a
        ld hl, stub_src        ; la salida, en la pagina compartida
        ld de, STUB
        ld bc, stub_end - stub_src
        ldir
        ld a, 0FAh             ; usuario: paginas 0-1 slot 2, 2-3 slot 3
        out (0FBh), a
        ; ---- el VBlank (linea 2 del PIC) tambien, para que lleguen
        ; interrupciones a menudo y caigan algunas en la ventana de la carrera
        in a, (0F1h)
        ld (sv_page), a
        xor a
        out (0F1h), a
        in a, (00h)
        ld (sv_mask), a
        if VBLANK
        or 04h
        endif
        out (00h), a
        ld a, (sv_page)
        out (0F1h), a
        ; ---- al usuario, en 0100h
        ld (ksp), sp
        ld sp, USTACK
        ld hl, 0100h
        push hl
        push af
        ld a, 1
        ld (ctx_user), a
        ld a, CTRL_USR
        jp X_INT

; ---------------------------------------------------------------- llamadas
; Desde el prologo de WRAP+2 (pagina 1 del supervisor), con ctx_user = 0.
; La funcion esta en fn_s; las interrupciones, como las tenia el usuario.
k_entry:
        ld (KSP_SAVE), sp      ; pila propia (W1)
        ld sp, KSP_SAVE
        ld (a_hl), hl
        ld hl, (nsys)
        inc hl
        ld (nsys), hl
        ld a, (fn_s)
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
k_bad:  ld hl, (a_hl)
        scf
k_ret:  di                     ; ni LD, ni JP, ni OUT tocan los indicadores
        ld sp, (KSP_SAVE)
        ld a, 1
        ld (ctx_user), a
        ld a, CTRL_USR
        jp WRAP                ; OUT (F0h),A; luego EI y RET del mapa del usuario

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
; Entra con el SP de quien fue interrumpido: el del usuario (pagina compartida)
; o el del nucleo.
isr_wrap:
        push af
        push hl
        ld a, (ctx_user)
        or a
        jr z, isr_k
        ld hl, 5               ; byte alto de la direccion de vuelta
        add hl, sp
        ld a, (hl)
        cp WRAP / 256
        jr nz, isr_u
        dec hl
        ld a, (hl)
        cp (WRAP + 2) & 255
        jr c, isr_u
        cp p_end - swrap + (WRAP & 255)
        jr nc, isr_u
        ld hl, (nrace)         ; en el prologo: ya es el nucleo
        inc hl
        ld (nrace), hl
        jr isr_k
isr_u:  xor a                  ; desde el usuario
        ld (ctx_user), a
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
isr_k:  pop hl
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
        xor a                  ; la mascara del PIC como estaba
        out (0F1h), a
        ld a, (sv_mask)
        out (00h), a
        ld a, (sv_page)
        out (0F1h), a
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
        ld de, m_race
        ld c, 9
        call BDOS
        ld hl, (nrace)
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
; Vuelta de una interrupcion (pagina compartida): tras el OUT (F0h) la CPU ya
; lee del mapa del usuario: POP AF, EI y RET tienen que verse en los dos.
stub_src:
X_INT   equ STUB + ($ - stub_src)
        out (0F0h), a
        pop af
        ei
        ret
stub_end:

; WRAP del usuario (en su pagina 1)
uwrap:  out (0F2h), a          ; 7F00h: al supervisor
        nop                    ; 7F02h: byte de transicion, igual en los dos
        ei                     ; 7F03h: tras la salida, ya del mapa del usuario
        ret                    ; 7F04h: la vuelta
uwrap_end:

; WRAP del supervisor (en su pagina 1): la salida y el prologo, sin DI
swrap:  out (0F0h), a          ; 7F00h: salida
        nop                    ; 7F02h: byte de transicion, igual en los dos
        ld (fn_s), a           ; 7F03h: prologo (ventana de la carrera)
        xor a
        ld (ctx_user), a
p_end:  jp k_entry             ; ya con ctx_user = 0
swrap_end:

; ---------------------------------------------------------------- usuario
; Corre en su 0100h (pagina privada): sin direcciones absolutas propias.
uimg:
        ld e, 'U'
        ld a, 1
        call WRAP
        ld e, ':'
        ld a, 1
        call WRAP
        ld e, ' '
        ld a, 1
        call WRAP
        ld hl, 1233h           ; eco: 1234h
        ld a, 2
        call WRAP
        ld e, 'E'
        ld a, h
        cp 12h
        jr nz, u_e1
        ld a, l
        cp 34h
        jr z, u_e2
u_e1:   ld e, 'e'
u_e2:   ld a, 1
        call WRAP
        ld a, 77h              ; funcion que no existe: acarreo
        call WRAP
        ld e, 'F'
        jr c, u_f
        ld e, 'f'
u_f:    ld a, 1
        call WRAP
        ld a, 5Ah              ; su pagina privada
        ld (4000h), a
        ld a, 0A5h             ; la compartida
        ld (SHARED), a
        ld bc, NCALLS          ; llamadas nulas
uloop:  ld a, 3
        call WRAP
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
        call WRAP
        xor a                  ; terminar
        call WRAP
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
m_banner: db "SYSTEST: OUT (F2h),A syscalls, wrapper/exit layout", 13, 10, "user> $"
m_calls:  db 13, 10, "syscalls served: $"
m_irq:    db 13, 10, "interrupts taken in user mode: $"
m_race:   db 13, 10, "races caught (interrupt right after OUT (F2h),A): $"
m_priv:   db 13, 10, "private user page: $"
m_shared: db 13, 10, "shared page: $"
m_ok:     db "OK$"
m_fail:   db "FAIL$"
ctx_user: db 0
nsys:     dw 0
nirq:     dw 0
nrace:    dw 0
fn_s:     db 0
ksp:      dw 0
a_hl:     dw 0
a_de:     dw 0
a_bc:     dw 0
a_ix:     dw 0
a_iy:     dw 0
sv_e8:    db 0
sv_mask:  db 0
sv_page:  db 0
sv_e9:    db 0
sv_fb:    db 0
sv_f0:    db 0
k4000:    db 0
u4000:    db 0
