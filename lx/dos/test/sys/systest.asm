; systest.asm - SYSTEST.COM: la llamada al sistema del LX con la salida en el
; RET y el bloqueo de interrupciones del bit 3 del control (propuestas de hww)
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer y el emulador alestelx.
;
; Un nucleo minimo (este programa, en modo supervisor dentro del LX-DOS) pone
; en marcha un programa en MODO USUARIO y le atiende las llamadas al sistema.
; Numero de funcion en A, argumentos en registros; resultado en HL y en A/F
; (acarreo = error). Todas las paginas del usuario que importan son privadas,
; tambien su pila.
;
; Entrada: el usuario hace CALL WRAP (7F00h, en su pagina 1):
;   usuario    7F00h  OUT (F2h),A     ; la MMU pasa al supervisor ya y bloquea
;                                     ; las interrupciones (bit 3 del control)
;   supervisor 7F02h  JP k_entry      ; la instruccion siguiente, de su mapa
; El nucleo cambia a su pila (W1, el SP del usuario en 4FFEh) y quita el
; bloqueo escribiendo el control con el bit 3 a 0. No toca las interrupciones
; del Z80: el estado que tenia el usuario se conserva.
;
; Salida: OUT (F0h),A con el bit 0 a 0 ARMA la salida y bloquea las
; interrupciones; el nucleo restaura AF y el SP del usuario todavia en
; supervisor; RET: la MMU sale (y quita el bloqueo) en el M1 que lee ese C9
; (leido con el mapa del supervisor) y el RET toma la vuelta de la pila del
; usuario con el mapa del usuario. Ni DI ni EI.
;
; Interrupciones en modo usuario: entran por la trampa de 0038h (el mismo JP en
; las dos paginas 0: el codigo de operacion de ese M1 sale del mapa del
; usuario). La rutina no toca la pila del usuario: guarda su SP, usa su propia
; pila, y vuelve con la misma salida en el RET.
;
;   pagina  supervisor (el nucleo)          usuario
;   0       slot 3, TPA (este programa)     slot 2, banco 40h: privada (su programa)
;   1       slot 3, TPA (salto, sus pilas)  slot 2, banco 41h: privada (WRAP, su pila)
;   2-3     slot 3 (TPA, drivers), igual en los dos
;
; Funciones: 0 terminar, 1 imprimir el caracter de E, 2 HL + 1, 3 nula.
; El programa de usuario comprueba resultados y errores, escribe en su pagina
; privada y en la 2, hace NCALLS llamadas nulas (para medir) y espera ~1 s en
; modo usuario: pulsando teclas mientras, llegan interrupciones. Con los
; programas en marcha, el LX-DOS solo deja la linea del teclado; con VBLANK = 1
; se activa tambien la del VBlank (2), para que lleguen a menudo.
; pasmo systest.asm SYSTEST.COM systest.sym
BDOS     equ 5
CTRL_USR equ 06h               ; nativo, trampas 0038h/0066h; bit 0 = 0: salir
CTRL_SUP equ 07h               ; lo mismo en supervisor; bit 3 = 0: sin bloqueo
UBANK0   equ 40h               ; bancos del usuario en el slot 2
UBANK1   equ 41h
NCALLS   equ 20000             ; llamadas nulas del bucle (para medir)
VBLANK   equ 0                 ; 1 = activar el VBlank durante la prueba
WRAP     equ 7F00h             ; pagina 1: wrapper (usuario) / salto (supervisor)
USTACK   equ 7E00h             ; pila del usuario (su pagina 1, privada)
KSP_SAVE equ 4FFEh             ; SP del usuario; debajo, la pila del nucleo (W1)
ISTACK   equ 4D00h             ; pila de las interrupciones que llegan del usuario
SHARED   equ 0A030h            ; dato que el usuario escribe en la pagina 2

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
        ; ---- la memoria del usuario, por la ventana 1 del nucleo
        ld a, UBANK0
        out (0E8h), a          ; slot 2, pagina 0
        out (0E9h), a          ; (de paso) slot 2, pagina 1 -> banco 40h
        ld a, 0FBh             ; pagina 1 del supervisor -> slot 2
        out (0FAh), a
        ld hl, 4000h           ; su pagina cero, limpia
        ld de, 4001h
        ld bc, 0FFh
        ld (hl), 0
        ldir
        ld a, 0C3h             ; el mismo JP en su 0038h
        ld (4038h), a
        ld hl, isr_wrap
        ld (4039h), hl
        ld hl, uimg            ; su programa, en su 0100h
        ld de, 4100h
        ld bc, uimg_end - uimg
        ldir
        ld a, UBANK1           ; su pagina 1: el dato privado a 0, WRAP, su pila
        out (0E9h), a
        xor a
        ld (4000h), a
        ld a, 0D3h             ; 7F00h: OUT (F2h),A
        ld (WRAP), a
        ld a, 0F2h
        ld (WRAP + 1), a
        ld hl, 0100h           ; en su pila, la vuelta al arrancar: 0100h
        ld (USTACK - 2), hl
        ld a, 0FFh             ; el nucleo, otra vez todo en el slot 3
        out (0FAh), a
        xor a
        ld (4000h), a          ; el 4000h del nucleo (TPA) a 0
        ld (SHARED), a
        ld a, 0C3h             ; su 7F02h: JP k_entry
        ld (WRAP + 2), a
        ld hl, k_entry
        ld (WRAP + 3), hl
        ld a, 0FAh             ; usuario: paginas 0-1 slot 2, 2-3 slot 3
        out (0FBh), a
        ; ---- interrupciones durante la prueba
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
        ; ---- al usuario: RET de su pila (0100h)
        ld (ksp), sp
        ld a, CTRL_USR
        out (0F0h), a          ; arma la salida (y bloquea)
        ld a, 1
        ld (ctx_user), a
        ld sp, USTACK - 2
        ei                     ; el usuario, con interrupciones
        ret                    ; sale aqui: la vuelta, de la pila del usuario

; ---------------------------------------------------------------- llamadas
; Desde WRAP (OUT (F2h),A) y el JP de 7F02h: supervisor, con el bloqueo;
; A = funcion; la vuelta, en la pila del usuario.
k_entry:
        ld (fn_s), a
        xor a
        ld (ctx_user), a
        ld (KSP_SAVE), sp      ; pila propia (W1)
        ld sp, KSP_SAVE
        ld a, CTRL_SUP         ; quita el bloqueo: interrupciones durante la
        out (0F0h), a          ; llamada (si el usuario las tenia)
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
hcall:  call 0                 ; HL, A y F de vuelta (acarreo = error)
        jr k_ret
k_bad:  ld hl, (a_hl)
        scf
k_ret:  push af                ; el resultado, en la pila del nucleo
        ld a, CTRL_USR
        out (0F0h), a          ; arma la salida y bloquea
        ld a, 1
        ld (ctx_user), a
        pop af                 ; todavia en supervisor
        ld sp, (KSP_SAVE)
        ret                    ; sale aqui (y quita el bloqueo): la vuelta, de
                               ; la pila del usuario

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
; 0038h: la trampa si estaba el usuario (entra con el SP del usuario, que en el
; mapa del supervisor no es su pila: no se apila nada hasta cambiar de pila).
; La rutina del LX-DOS acaba en EI; RETI.
isr_wrap:
        ex af, af'
        ld a, (ctx_user)
        or a
        jr z, isr_k
        ld (isr_usp), sp       ; desde el usuario: pila propia
        ld sp, ISTACK
        ex af, af'
        push af
        push hl
        xor a
        ld (ctx_user), a
        ld hl, (nirq)
        inc hl
        ld (nirq), hl
        pop hl
        pop af
        call orig_isr          ; acaba en EI; RETI
        push af
        ld a, CTRL_USR
        out (0F0h), a          ; arma la salida y bloquea
        ld a, 1
        ld (ctx_user), a
        pop af
        ld sp, (isr_usp)
        ret                    ; al usuario, a donde lo interrumpieron
isr_k:  ex af, af'             ; desde el nucleo: con su pila
orig_isr:
        ds 3                   ; JP __dos_isr_gate (copiado de 0038h)

; ---------------------------------------------------------------- fin
finish: di
        ld a, (sv_f0)          ; supervisor, sin trampas
        out (0F0h), a
        ld a, (sv_fb)
        out (0FBh), a
        xor a                  ; la mascara del PIC como estaba
        out (0F1h), a
        ld a, (sv_mask)
        out (00h), a
        ld a, (sv_page)
        out (0F1h), a
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
        ld a, 0A5h             ; la 2
        ld (SHARED), a
        ld bc, NCALLS          ; llamadas nulas
uloop:  ld a, 3
        call WRAP
        dec bc
        ld a, b
        or c
        jr nz, uloop
uend:   ld d, 10               ; ~1 s solo en modo usuario: si se pulsan
u_w1:   ld bc, 0               ; teclas, llegan interrupciones y tienen que
u_w2:   dec bc                 ; volver aqui
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
m_banner: db "SYSTEST: OUT (F2h),A syscalls, exit on RET, interrupt hold", 13, 10, "user> $"
m_calls:  db 13, 10, "syscalls served: $"
m_irq:    db 13, 10, "interrupts taken in user mode: $"
m_priv:   db 13, 10, "private user page: $"
m_shared: db 13, 10, "page 2 data: $"
m_ok:     db "OK$"
m_fail:   db "FAIL$"
ctx_user: db 0
nsys:     dw 0
nirq:     dw 0
fn_s:     db 0
ksp:      dw 0
isr_usp:  dw 0
a_hl:     dw 0
sv_e8:    db 0
sv_e9:    db 0
sv_fb:    db 0
sv_f0:    db 0
sv_mask:  db 0
sv_page:  db 0
k4000:    db 0
u4000:    db 0
