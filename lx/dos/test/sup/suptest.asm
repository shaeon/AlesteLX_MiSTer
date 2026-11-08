; suptest.asm - SUPTEST.COM: prototipo de llamada al sistema por RST 6
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer y el emulador.
;
; Un nucleo minimo que corre como programa del LX-DOS (en supervisor) y
; ejecuta user.asm en MODO USUARIO:
;   mapa de usuario: pagina 0 = slot 2, banco 30h (el programa, en 0100h:
;   la pagina cero es del sistema, porque las trampas saltan en cualquier
;   lectura de instruccion en 0030h, 0038h y 0066h); pagina 1 =
;   slot 3, la misma que la del supervisor (pila del usuario, resultados y el
;   codigo de salida); pagina 2 = slot 2 (sin usar); pagina 3 = slot 3, los
;   drivers (compartida, como en el diseno de hww).
;   0030h (supervisor): entrada de las llamadas al sistema. Lee los 3 bytes
;     de detras del RST en la memoria del usuario (la ventana 2 del supervisor
;     se asoma a su pagina 0), atiende la funcion y vuelve sumando 3.
;   0038h (supervisor): las interrupciones que llegan en modo usuario entran
;     por la trampa; se llama a la rutina normal del LX-DOS y se vuelve.
;   La vuelta a usuario se hace en la pagina compartida: escribir F0h con el
;   bit 0 a 0 cambia de mapa en la lectura de la instruccion siguiente.
; Registro de control en usuario: 1Eh = nativo, trampas 0038/0066 (bit 2),
; RST 6 (bit 3, provisional), puertos bloqueados para el usuario (bit 4).
; Funciones: 0 version -> HL; 1 putchar E; 2 HL = HL + DE; 4 salir.
; A = FFh: CALLF de otro slot (no hay BIOS MSX); A = FEh: funcion no existe.
; pasmo suptest.asm SUPTEST.COM suptest.sym  (necesita user.bin)
BDOS    equ 5
CTRL_USER equ 1Eh
CTRL_SUP  equ 13h
USER_BANK equ 30h
STUB    equ 4000h               ; en la pagina compartida
USTACK  equ 7FF0h
RESULTS equ 5000h

        org 100h
        ld de, m_title
        call print
        ; ---- guarda lo que se toca
        in a, (0FBh)
        ld (s_fb), a
        in a, (0E8h)
        ld (s_e8), a
        in a, (0EAh)
        ld (s_ea), a
        ld hl, 30h
        ld de, s_z30
        ld bc, 4
        ldir
        ld hl, 38h
        ld de, s_z38
        ld bc, 3
        ldir
        ld hl, (39h)            ; destino de JP en 0038h (la pasarela del LX-DOS)
        ld (isr_jp + 1), hl
        ; ---- el mapa del usuario
        ld a, USER_BANK
        out (0E8h), a           ; slot 2, pagina 0
        out (0EAh), a           ; slot 2, pagina 2: la misma, para asomarse
        ld a, 0EEh              ; paginas 0 y 2 = slot 2; 1 y 3 = slot 3
        out (0FBh), a
        ; ---- el programa de usuario en su pagina 0 (por la ventana 2)
        di
        ld a, 0EFh
        out (0FAh), a           ; supervisor: pagina 2 = slot 2
        ld hl, user_bin
        ld de, 8100h            ; el programa empieza en 0100h, como en CP/M
        ld bc, user_end - user_bin
        ldir
        ld a, 0FFh
        out (0FAh), a
        ei
        ; ---- el codigo de salida en la pagina compartida, resultados a 0
        ld hl, stub_code
        ld de, STUB
        ld bc, stub_end - stub_code
        ldir
        ld hl, RESULTS
        ld de, RESULTS + 1
        ld bc, 15
        ld (hl), 0
        ldir
        ; ---- las entradas del nucleo
        di
        ; 0030h: DI y JP. La trampa deja las interrupciones como estaban (en
        ; modo usuario, activas): si una llegara entre la trampa y el DI, el
        ; manejador de interrupciones la tomaria por una del modo usuario
        ld a, 0F3h              ; DI
        ld (30h), a
        ld a, 0C3h              ; JP sys_entry
        ld (31h), a
        ld hl, sys_entry
        ld (32h), hl
        ld hl, isr_wrap
        ld (39h), hl
        ; ---- a modo usuario: el programa empieza en 0000h
        ld (saved_sp), sp
        ld sp, USTACK
        ld hl, 0100h
        push hl                 ; direccion de entrada del usuario
        push af                 ; el codigo de salida hace POP AF
        ld a, 1
        ld (in_user), a
        ld a, CTRL_USER
        jp STUB

; ---- aqui vuelve la funcion 4 (salir), en supervisor
after_user:
        di
        ld sp, (saved_sp)
        ld a, CTRL_SUP
        out (0F0h), a
        ld a, (s_fb)
        out (0FBh), a
        ld a, (s_e8)
        out (0E8h), a
        ld a, (s_ea)
        out (0EAh), a
        ld hl, s_z30
        ld de, 30h
        ld bc, 4
        ldir
        ld hl, s_z38
        ld de, 38h
        ld bc, 3
        ldir
        ei
        ; ---- resultados
        ld de, m_ver
        call print
        ld hl, (RESULTS + 0)
        call phex16
        ld de, m_add
        call print
        ld hl, (RESULTS + 2)
        call phex16
        ld de, m_loops
        call print
        ld hl, (RESULTS + 4)
        call phex16
        ld de, m_port
        call print
        ld a, (RESULTS + 6)
        call phex8
        ld de, m_callf
        call print
        ld a, (RESULTS + 7)
        call phex8
        ld de, m_bad
        call print
        ld a, (RESULTS + 8)
        call phex8
        ld de, m_end
        call print
        ld a, (RESULTS + 9)
        call phex8
        ld de, m_calls
        call print
        ld hl, (n_calls)
        call phex16
        ld de, m_irqs
        call print
        ld hl, (n_irqs)
        call phex16
        ld de, m_crlf
        call print
        ; veredicto
        ld hl, (RESULTS + 0)
        ld de, 0001h
        or a
        sbc hl, de
        jr nz, bad
        ld hl, (RESULTS + 2)
        ld de, 2345h
        or a
        sbc hl, de
        jr nz, bad
        ld a, (RESULTS + 6)
        cp 0FFh
        jr nz, bad
        ld a, (RESULTS + 7)
        cp 0FFh
        jr nz, bad
        ld a, (RESULTS + 8)
        cp 0FEh
        jr nz, bad
        ld a, (RESULTS + 9)
        cp 0A5h
        jr nz, bad
        ld hl, (n_irqs)
        ld a, h
        or l
        jr z, bad
        ld de, m_ok
        jr verdict
bad:    ld de, m_fail
verdict:
        call print
        ret

; ======================================================================
; Llamada al sistema (0030h en el mapa del supervisor)
sys_entry:                      ; (con las interrupciones ya cerradas en 0030h)
        ld (k_hl), hl
        ld (k_de), de
        xor a
        ld (in_user), a
        ld hl, (n_calls)
        inc hl
        ld (n_calls), hl
        pop hl                  ; direccion de vuelta (pila del usuario: compartida)
        ; los 3 bytes de detras del RST, en la pagina 0 del usuario
        ld a, 0EFh
        out (0FAh), a           ; ventana 2 = pagina 0 del usuario
        push hl
        ld a, h
        and 3Fh
        or 80h
        ld h, a
        ld a, (hl)              ; slot
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)              ; numero de funcion
        ld (k_slot), a
        ld a, 0FFh
        out (0FAh), a
        pop hl
        inc hl
        inc hl
        inc hl
        push hl                 ; vuelta detras de los 3 bytes
        ld a, (k_slot)
        cp 0FFh
        jr z, sys_lx
        ld a, 0FFh              ; un CALLF de MSX: aqui no hay BIOS MSX
        jr sys_ret_a
sys_lx: ld a, d
        or a
        jr nz, sys_bad
        ld a, e
        or a
        jr z, f_version
        cp 1
        jr z, f_putchar
        cp 2
        jr z, f_add
        cp 4
        jp z, after_user
sys_bad:
        ld a, 0FEh
        jr sys_ret_a
f_version:
        ld hl, 0001h
        ld (k_hl), hl
        xor a
        jr sys_ret_a
f_putchar:
        ld de, (k_de)
        ld c, 2
        call BDOS               ; la consola del LX-DOS
        di
        xor a
        jr sys_ret_a
f_add:  ld hl, (k_hl)
        ld de, (k_de)
        add hl, de
        ld (k_hl), hl
        xor a
sys_ret_a:                      ; vuelta al usuario con A, HL = k_hl, DE = k_de
        ld hl, (k_hl)
        ld de, (k_de)
        push af
        ld a, 1
        ld (in_user), a
        ld a, CTRL_USER
        jp STUB

; ======================================================================
; Interrupciones (0038h en el mapa del supervisor)
isr_wrap:
        push af
        ld a, (in_user)
        or a
        jr z, isr_super
        xor a
        ld (in_user), a
        push hl
        ld hl, (n_irqs)
        inc hl
        ld (n_irqs), hl
        pop hl
        pop af
        call isr_jp             ; la pasarela del LX-DOS (acaba con EI / RETI)
        di
        push af
        ld a, 1
        ld (in_user), a
        ld a, CTRL_USER
        jp STUB                 ; vuelve al usuario
isr_super:
        pop af
isr_jp: jp 0                    ; el destino original de 0038h

; ======================================================================
; Codigo de salida: se copia a la pagina compartida (4000h). Tras el OUT, la
; siguiente instruccion ya se lee con el mapa del usuario
stub_code:
        out (0F0h), a           ; bit 0 = 0: a usuario en el siguiente M1
        pop af
        ei
        ret
stub_end:

; ======================================================================
print:  ld c, 9
        jp BDOS
phex16: push hl
        ld a, h
        call phex8
        pop hl
        ld a, l
phex8:  push af
        rrca
        rrca
        rrca
        rrca
        call nib
        pop af
nib:    and 0Fh
        add a, 90h
        daa
        adc a, 40h
        daa
        ld e, a
        ld c, 2
        jp BDOS

m_title: db "SUPTEST - RST 6 syscall prototype (user mode)", 13, 10, '$'
m_ver:   db "version (fn 0):        $"
m_add:   db 13, 10, "1234+1111 (fn 2):      $"
m_loops: db 13, 10, "loops left:            $"
m_port:  db 13, 10, "port F0h in user mode: $"
m_callf: db 13, 10, "CALLF slot 01h:        $"
m_bad:   db 13, 10, "unknown function:      $"
m_end:   db 13, 10, "user program end mark: $"
m_calls: db 13, 10, "syscalls:              $"
m_irqs:  db 13, 10, "IRQs in user mode:     $"
m_crlf:  db 13, 10, '$'
m_ok:    db "RST 6 SYSCALL TEST: OK", 13, 10, '$'
m_fail:  db "RST 6 SYSCALL TEST: FAILED", 13, 10, '$'

in_user:  db 0
n_calls:  dw 0
n_irqs:   dw 0
k_hl:     dw 0
k_de:     dw 0
k_slot:   db 0
saved_sp: dw 0
s_fb:     db 0
s_e8:     db 0
s_ea:     db 0
s_z30:    ds 4
s_z38:    ds 3

user_bin:
        incbin "user.bin"
user_end:
