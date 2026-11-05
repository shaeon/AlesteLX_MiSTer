; tunnel.asm - TUNNEL.COM: demo del modo 320x200x256 del LX-DOS
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
; 100 rectangulos concentricos (A5h), un titulo con texto transparente (A7h)
; y la paleta rotando (A4h) hasta pulsar una tecla. pasmo tunnel.asm TUNNEL.COM
BDOS    equ 5
        org 100h
        ld e, 1
        ld c, 0A3h              ; modo grafico
        call BDOS
        ld de, pal_base
        ld c, 0A4h
        call BDOS
        ; ---- rectangulos: i = 0..99: x = i * 3 / 2, y = i, w = 320 - 2x, h = 200 - 2i
        xor a
        ld (ri), a
rloop:     ld a, (ri)
        ld l, a
        ld h, 0
        ld e, l
        ld d, 0
        srl e
        add hl, de              ; x = i + i / 2
        ld (rect), hl
        ld a, (ri)
        ld (rect + 2), a
        xor a
        ld (rect + 3), a
        add hl, hl              ; 2x
        ex de, hl
        ld hl, 320
        or a
        sbc hl, de
        ld (rect + 4), hl       ; w
        ld a, (ri)
        add a, a
        ld e, a
        ld d, 0
        ld hl, 200
        or a
        sbc hl, de
        ld (rect + 6), hl       ; h
        ld a, (ri)
        add a, a
        add a, a
        inc a                   ; color 1..253 (4 por rectangulo, sin 0 ni 255)
        cp 254
        jr c, rcol
        sub 253
rcol:     ld (rect + 8), a
        ld de, rect
        ld c, 0A5h
        call BDOS
        ld a, (ri)
        inc a
        ld (ri), a
        cp 100
        jr nz, rloop
        ; ---- titulo (blanco = 255, fondo transparente)
        ld de, title_blk
        ld c, 0A7h
        call BDOS
        ld de, sub_blk
        ld c, 0A7h
        call BDOS
        ; ---- la paleta gira: colores 1-254
loop:   ld a, (off)
        inc a
        cp 254
        jr c, lo
        xor a
lo:     ld (off), a
        ld ix, pal_work + 2     ; color 1
        ld b, 254
        ld a, (off)
        ld c, a
pl:     ld l, c                 ; base[(k + off) mod 254 + 1]
        ld h, 0
        add hl, hl
        ld de, pal_base + 2
        add hl, de
        ld a, (hl)
        ld (ix + 0), a
        inc hl
        ld a, (hl)
        ld (ix + 1), a
        inc ix
        inc ix
        inc c
        ld a, c
        cp 254
        jr c, pl2
        ld c, 0
pl2:    djnz pl
        ld de, pal_work
        ld c, 0A4h
        call BDOS
        ld b, 40                ; un respiro
dl:     push bc
        ld bc, 400
dl2:    dec bc
        ld a, b
        or c
        jr nz, dl2
        pop bc
        djnz dl
        ld c, 11                ; tecla?
        call BDOS
        or a
        jr z, loop
        ld c, 8
        call BDOS
        ld e, 0
        ld c, 0A3h              ; al texto
        jp BDOS

ri:     db 0
off:    db 0
rect:   ds 9
title_blk: dw 76, 92            ; x, y
        db 255, 0, 1            ; tinta, fondo, transparente
        dw title
sub_blk:  dw 68, 104
        db 255, 0, 1
        dw subt
title:  db "ALESTE LX  320x200x256", 0
subt:   db "press any key to return", 0
pal_base:
        db 0, 0, 17, 15, 33, 15, 33, 15, 33, 15, 49, 15, 49, 15, 49, 15
        db 49, 11, 49, 11, 49, 11, 65, 11, 65, 11, 65, 11, 65, 11, 65, 11
        db 97, 15, 113, 15, 113, 15, 113, 15, 129, 15, 129, 15, 129, 15, 145, 15
        db 113, 11, 113, 11, 113, 11, 113, 11, 129, 11, 129, 11, 129, 11, 129, 11
        db 177, 15, 193, 15, 193, 15, 193, 15, 209, 15, 209, 15, 209, 15, 225, 15
        db 161, 11, 177, 11, 177, 11, 177, 11, 177, 11, 177, 11, 177, 11, 177, 10
        db 241, 14, 241, 13, 241, 13, 241, 13, 241, 12, 241, 12, 241, 12, 241, 11
        db 177, 8, 177, 8, 177, 8, 177, 8, 177, 7, 177, 7, 177, 7, 177, 7
        db 241, 8, 241, 8, 241, 8, 241, 7, 241, 7, 241, 7, 241, 6, 241, 6
        db 177, 4, 177, 4, 177, 4, 177, 4, 177, 3, 177, 3, 177, 3, 177, 3
        db 241, 3, 241, 3, 241, 3, 241, 2, 241, 2, 241, 2, 242, 1, 242, 1
        db 178, 1, 178, 1, 178, 1, 178, 1, 179, 1, 179, 1, 179, 1, 179, 1
        db 245, 1, 245, 1, 245, 1, 246, 1, 246, 1, 246, 1, 247, 1, 247, 1
        db 182, 1, 182, 1, 182, 1, 182, 1, 182, 1, 183, 1, 183, 1, 183, 1
        db 250, 1, 250, 1, 251, 1, 251, 1, 251, 1, 251, 1, 252, 1, 252, 1
        db 185, 1, 186, 1, 186, 1, 186, 1, 186, 1, 187, 1, 187, 1, 187, 1
        db 255, 1, 255, 1, 239, 1, 239, 1, 239, 1, 223, 1, 223, 1, 223, 1
        db 155, 1, 155, 1, 155, 1, 155, 1, 139, 1, 139, 1, 139, 1, 139, 1
        db 175, 1, 175, 1, 159, 1, 159, 1, 159, 1, 143, 1, 143, 1, 143, 1
        db 107, 1, 91, 1, 91, 1, 91, 1, 91, 1, 75, 1, 75, 1, 75, 1
        db 95, 1, 79, 1, 79, 1, 79, 1, 79, 1, 63, 1, 63, 1, 63, 1
        db 43, 1, 27, 1, 27, 1, 27, 1, 27, 2, 27, 2, 27, 2, 27, 2
        db 31, 3, 31, 4, 31, 4, 31, 4, 31, 5, 31, 5, 31, 5, 31, 6
        db 27, 4, 27, 5, 27, 5, 27, 5, 27, 5, 27, 6, 27, 6, 27, 6
        db 31, 8, 31, 9, 31, 9, 31, 9, 31, 10, 31, 10, 31, 10, 31, 11
        db 27, 8, 27, 8, 27, 9, 27, 9, 27, 9, 27, 9, 27, 10, 27, 10
        db 31, 14, 31, 14, 31, 14, 31, 14, 31, 15, 31, 15, 31, 15, 30, 15
        db 26, 11, 26, 11, 26, 11, 26, 11, 25, 11, 25, 11, 25, 11, 25, 11
        db 27, 15, 27, 15, 27, 15, 26, 15, 26, 15, 26, 15, 25, 15, 25, 15
        db 23, 11, 22, 11, 22, 11, 22, 11, 22, 11, 21, 11, 21, 11, 21, 11
        db 22, 15, 22, 15, 22, 15, 21, 15, 21, 15, 21, 15, 20, 15, 20, 15
        db 19, 11, 19, 11, 18, 11, 18, 11, 18, 11, 18, 11, 17, 11, 255, 15
pal_work:
        db 0, 0
        ds 254 * 2
        db 0FFh, 0Fh
