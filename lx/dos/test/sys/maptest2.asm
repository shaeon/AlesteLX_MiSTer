; maptest2.asm - MAPTEST2.COM: de que mapa salen el codigo de operacion y el
; operando de la primera instruccion tras OUT (F0h),A
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer y el emulador alestelx.
;
; En 7F10h (pagina 1, distinta en los dos mapas):
;   supervisor: OUT (F0h),A / LD B,1 / LD C,1 / LD D,1 / ...
;   usuario:    (2 bytes)   / LD B,2 / LD C,2 / LD D,2 / OUT (F2h),A
; y tras ese OUT (F2h),A el supervisor sigue en 7F1Ah con JP fin.
; Imprime B, C y D: 1 = esa instruccion salio del mapa del supervisor,
; 2 = del usuario. Sin interrupciones.
; pasmo maptest.asm MAPTEST.COM
BDOS    equ 5
T       equ 7F10h
        org 100h
        ld de, m_hello
        ld c, 9
        call BDOS
        di
        in a, (0E9h)
        ld (sv_e9), a
        in a, (0FBh)
        ld (sv_fb), a
        in a, (0F0h)
        ld (sv_f0), a
        ld a, 41h              ; pagina 1 del usuario: slot 2, banco 41h
        out (0E9h), a
        ld a, 0FBh             ; verla por la pagina 1 del supervisor
        out (0FAh), a
        ld hl, ucode
        ld de, T
        ld bc, ucode_end - ucode
        ldir
        ld a, 0FFh
        out (0FAh), a
        ld hl, scode           ; la del supervisor (TPA)
        ld de, T
        ld bc, scode_end - scode
        ldir
        ld a, 0FBh             ; usuario: pagina 1 en el slot 2, el resto slot 3
        out (0FBh), a
        ld (ksp), sp
        ld b, 0
        ld c, 0
        ld d, 0
        ld a, 06h              ; nativo + trampas; bit 0 = 0: salir
        jp T
back:   ld sp, (ksp)           ; ya en supervisor
        ld (rb), bc
        ld a, d
        ld (rd), a
        ld a, (sv_f0)
        out (0F0h), a
        ld a, (sv_fb)
        out (0FBh), a
        ld a, (sv_e9)
        out (0E9h), a
        ei
        ld de, m_b
        ld c, 9
        call BDOS
        ld a, (rb + 1)
        call pdig
        ld de, m_c
        ld c, 9
        call BDOS
        ld a, (rb)
        call pdig
        ld de, m_d
        ld c, 9
        call BDOS
        ld a, (rd)
        call pdig
        ld de, m_end
        ld c, 9
        jp BDOS
pdig:   add a, '0'
        ld e, a
        ld c, 2
        jp BDOS

scode:  out (0F0h), a          ; 7F10h
        ld b, 1                ; 7F12h: 06 01
        ld c, 1                ; 7F14h
        ld d, 1                ; 7F16h
        nop                    ; 7F18h
        nop                    ; 7F19h
        jp back                ; 7F1Ah (tras el OUT (F2h),A del usuario)
scode_end:
ucode:  nop                    ; 7F10h
        nop                    ; 7F11h
        inc b                  ; 7F12h: 04
        inc b                  ; 7F13h: 04
        ld c, 2                ; 7F14h
        ld d, 2                ; 7F16h
        out (0F2h), a          ; 7F18h: al supervisor
        nop                    ; 7F1Ah (no se ejecuta)
        nop
        nop
ucode_end:

m_hello: db "MAPTEST2: B=2 user opcode, B=4 supervisor opcode + user operand, B=1 supervisor", 13, 10, "$"
m_b:     db "B (1st after OUT (F0h)): $"
m_c:     db 13, 10, "C: $"
m_d:     db 13, 10, "D: $"
m_end:   db 13, 10, "$"
ksp:     dw 0
rb:      dw 0
rd:      db 0
sv_e9:   db 0
sv_fb:   db 0
sv_f0:   db 0
