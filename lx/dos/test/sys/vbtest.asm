; vbtest.asm - VBTEST.COM: el VBlank (linea 2 del PIC) activo con un programa
; del LX-DOS en marcha, sin modo usuario. Escribe un punto cada ~0,1 s durante
; ~1 s y deja la mascara del PIC como estaba.
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer y el emulador alestelx.
; pasmo vbtest.asm VBTEST.COM
BDOS    equ 5
        org 100h
        ld de, m_hello
        ld c, 9
        call BDOS
        di
        in a, (0F1h)
        ld (sv_page), a
        xor a
        out (0F1h), a
        in a, (00h)
        ld (sv_mask), a
        or 04h
        out (00h), a
        ld a, (sv_page)
        out (0F1h), a
        ei
        ld b, 10
dots:   push bc
        ld d, 2                 ; ~0,1 s a 18 MHz
w1:     ld bc, 0
w2:     dec bc
        ld a, b
        or c
        jr nz, w2
        dec d
        jr nz, w1
        ld e, '.'
        ld c, 2
        call BDOS
        pop bc
        djnz dots
        di
        xor a
        out (0F1h), a
        ld a, (sv_mask)
        out (00h), a
        ld a, (sv_page)
        out (0F1h), a
        ei
        ld de, m_ok
        ld c, 9
        jp BDOS
m_hello: db "VBTEST: VBlank on for ~1 s", 13, 10, "$"
m_ok:    db 13, 10, "done", 13, 10, "$"
sv_mask: db 0
sv_page: db 0
