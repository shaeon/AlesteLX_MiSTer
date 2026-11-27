; pictest.asm - Prueba del PIC v2 y del temporizador rev 6 del modo LX
; (rtl/core/lx/lx_sys.sv)
; Se carga como imagen LX (64 KB, la CPU la ve en 0000-FFFF en modo nativo).
; Arma el comparador del temporizador cada 1000 us (COMPARE += 1000 en el
; manejador, sin derivar), habilita en el PIC las lineas 6 (SYSTIMER) y 2
; (VBlank) y cuenta en el manejador de IM 1, que atiende con CLAIM ->
; COMPLETE hasta que CLAIM no da ninguna:
;   3F10  A5 cuando arranca el bucle
;   3F12  ticks del temporizador (16 bits)
;   3F14  VBlanks (16 bits)
;   3F16  otras interrupciones (16 bits)
; pasmo --bin pictest.asm PICTEST.ROM
P_MMIOPG    equ 0F1h
PIC_CMD     equ 00h
PIC_CLAIM   equ 01h
TMR_LO      equ 0F4h
TMR_HI      equ 0F5h
PERIOD      equ 1000
VARS        equ 3F10h
TGT         equ 3F20h               ; objetivo del comparador

            org 0
            di
            jp start
            ds 38h-$
; ---- IM 1
irq:        push af
            push hl
            push de
            xor a
            out (P_MMIOPG), a
claim:      in a, (PIC_CLAIM)       ; bit 7 VALIDO, bits 3-0 linea
            or a
            jp p, irq_end
            and 0Fh
            push af
            cp 6
            jr nz, no_tmr
            ld hl, (VARS+2)
            inc hl
            ld (VARS+2), hl
            ld hl, (TGT)            ; siguiente objetivo
            ld de, PERIOD
            add hl, de
            ld (TGT), hl
            ld a, l
            out (TMR_LO), a
            ld a, h
            out (TMR_HI), a
            jr done
no_tmr:     cp 2
            jr nz, other
            ld hl, (VARS+4)
            inc hl
            ld (VARS+4), hl
            jr done
other:      ld hl, (VARS+6)
            inc hl
            ld (VARS+6), hl
done:       pop af
            or 10h                  ; COMPLETE
            out (PIC_CMD), a
            jr claim
irq_end:    pop de
            pop hl
            pop af
            ei
            reti

start:      ld sp, 3F00h
            ld hl, VARS
            ld b, 32
clr:        ld (hl), 0
            inc hl
            djnz clr
            xor a
            out (P_MMIOPG), a
            ld a, 26h               ; ENABLE linea 6
            out (PIC_CMD), a
            ld a, 22h               ; ENABLE linea 2
            out (PIC_CMD), a
            ld c, TMR_LO            ; primer objetivo: RT + PERIOD
            in l, (c)
            inc c
            in h, (c)
            ld de, PERIOD
            add hl, de
            ld (TGT), hl
            ld a, l
            out (TMR_LO), a
            ld a, h
            out (TMR_HI), a
            im 1
            ld a, 0A5h
            ld (VARS), a
            ei
loop:       jr loop
            ds 10000h-$
