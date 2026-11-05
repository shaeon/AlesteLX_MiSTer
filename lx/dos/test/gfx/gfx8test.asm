; gfx8test.asm - Prueba del modo 320x200x256 del Aleste LX (8 bpp lineal)
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer y el emulador alestelx.
; Programa del LX-DOS: solo usa los puertos (pagina MMIO 2: paleta 00-06,
; CRTC 20/21). Carga una paleta 3-3-2, llena C50000-C5F9FF (64000 bytes) con
; un degradado diagonal (pixel = x + y) por la ventana 1, pone el modo
; (R18 = 03h 8 bpp, R19 = C5h, R20 = 07h lineal 8 bytes por caracter,
; R21 = 02h, R12/R13 = 0), espera una tecla y lo deja todo como estaba.
; pasmo gfx8test.asm GFX8TEST.COM
BDOS    equ 5
MMIO    equ 0F1h
        org 100h
        ld a, 2
        out (MMIO), a
        ; ---- guarda R0-R21, los colores 0 y 1 y el control de la paleta
        ld hl, crtc_save
        ld b, 0
sv:     ld a, b
        out (20h), a
        in a, (21h)
        ld (hl), a
        inc hl
        inc b
        ld a, b
        cp 22
        jr nz, sv
        in a, (05h)
        ld (pal_ctrl), a
        xor a
        out (00h), a
        in a, (01h)
        ld (pal_save), a
        in a, (02h)
        ld (pal_save + 1), a
        ld a, 1
        out (00h), a
        in a, (01h)
        ld (pal_save + 2), a
        in a, (02h)
        ld (pal_save + 3), a
        ; ---- paleta de 256 colores (indice con autoincremento)
        ld a, 20h
        out (05h), a
        xor a
        out (00h), a
        ld hl, palette
        ld b, 0
pl:     ld a, (hl)
        out (01h), a
        inc hl
        ld a, (hl)
        out (02h), a
        inc hl
        djnz pl
        ; ---- la imagen: bancos 14h-17h (C50000) por la ventana 1
        in a, (0FDh)
        ld (win1_save), a
        ld a, 14h
        ld (bank), a
        out (0FDh), a
        ld hl, 4000h
        ld de, 0                ; y
ly:     ld bc, 0                ; x
lx:     ld a, c
        add a, e                ; pixel = x + y
        ld (hl), a
        inc hl
        ld a, h
        cp 80h
        jr nz, nb
        ld a, (bank)            ; siguiente banco de 16 KB
        inc a
        ld (bank), a
        out (0FDh), a
        ld hl, 4000h
nb:     inc bc
        ld a, b
        cp 1                    ; x = 320 (140h)?
        jr nz, lx
        ld a, c
        cp 40h
        jr nz, lx
        inc de
        ld a, e
        cp 200
        jr nz, ly
        ld a, (win1_save)
        out (0FDh), a
        ; ---- el modo
        ld a, 2
        out (MMIO), a
        ld hl, mode_regs
md:     ld a, (hl)
        cp 0FFh
        jr z, md_end
        out (20h), a
        inc hl
        ld a, (hl)
        out (21h), a
        inc hl
        jr md
md_end:
        ; ---- una tecla
        ld c, 6
wk:     push bc
        ld e, 0FFh
        call BDOS
        pop bc
        or a
        jr z, wk
        ; ---- como estaba
        ld a, 2
        out (MMIO), a
        ld hl, crtc_save
        ld b, 0
rs:     ld a, b
        out (20h), a
        ld a, (hl)
        out (21h), a
        inc hl
        inc b
        ld a, b
        cp 22
        jr nz, rs
        xor a
        out (05h), a
        out (00h), a
        ld a, (pal_save)
        out (01h), a
        ld a, (pal_save + 1)
        out (02h), a
        ld a, 1
        out (00h), a
        ld a, (pal_save + 2)
        out (01h), a
        ld a, (pal_save + 3)
        out (02h), a
        ld a, (pal_ctrl)
        out (05h), a
        ret

mode_regs:
        db 12, 0, 13, 0         ; inicio
        db 13h, 0C5h            ; R19: C50000
        db 14h, 07h             ; R20: lineal, paso 4, dos por caracter = 8 bytes
        db 15h, 02h             ; R21: 8 bytes por caracter
        db 12h, 03h             ; R18: 8 bpp
        db 0FFh
palette:
        db 0, 0, 5, 0, 10, 0, 15, 0, 32, 0, 37, 0, 42, 0, 47, 0
        db 64, 0, 69, 0, 74, 0, 79, 0, 96, 0, 101, 0, 106, 0, 111, 0
        db 144, 0, 149, 0, 154, 0, 159, 0, 176, 0, 181, 0, 186, 0, 191, 0
        db 208, 0, 213, 0, 218, 0, 223, 0, 240, 0, 245, 0, 250, 0, 255, 0
        db 0, 2, 5, 2, 10, 2, 15, 2, 32, 2, 37, 2, 42, 2, 47, 2
        db 64, 2, 69, 2, 74, 2, 79, 2, 96, 2, 101, 2, 106, 2, 111, 2
        db 144, 2, 149, 2, 154, 2, 159, 2, 176, 2, 181, 2, 186, 2, 191, 2
        db 208, 2, 213, 2, 218, 2, 223, 2, 240, 2, 245, 2, 250, 2, 255, 2
        db 0, 4, 5, 4, 10, 4, 15, 4, 32, 4, 37, 4, 42, 4, 47, 4
        db 64, 4, 69, 4, 74, 4, 79, 4, 96, 4, 101, 4, 106, 4, 111, 4
        db 144, 4, 149, 4, 154, 4, 159, 4, 176, 4, 181, 4, 186, 4, 191, 4
        db 208, 4, 213, 4, 218, 4, 223, 4, 240, 4, 245, 4, 250, 4, 255, 4
        db 0, 6, 5, 6, 10, 6, 15, 6, 32, 6, 37, 6, 42, 6, 47, 6
        db 64, 6, 69, 6, 74, 6, 79, 6, 96, 6, 101, 6, 106, 6, 111, 6
        db 144, 6, 149, 6, 154, 6, 159, 6, 176, 6, 181, 6, 186, 6, 191, 6
        db 208, 6, 213, 6, 218, 6, 223, 6, 240, 6, 245, 6, 250, 6, 255, 6
        db 0, 9, 5, 9, 10, 9, 15, 9, 32, 9, 37, 9, 42, 9, 47, 9
        db 64, 9, 69, 9, 74, 9, 79, 9, 96, 9, 101, 9, 106, 9, 111, 9
        db 144, 9, 149, 9, 154, 9, 159, 9, 176, 9, 181, 9, 186, 9, 191, 9
        db 208, 9, 213, 9, 218, 9, 223, 9, 240, 9, 245, 9, 250, 9, 255, 9
        db 0, 11, 5, 11, 10, 11, 15, 11, 32, 11, 37, 11, 42, 11, 47, 11
        db 64, 11, 69, 11, 74, 11, 79, 11, 96, 11, 101, 11, 106, 11, 111, 11
        db 144, 11, 149, 11, 154, 11, 159, 11, 176, 11, 181, 11, 186, 11, 191, 11
        db 208, 11, 213, 11, 218, 11, 223, 11, 240, 11, 245, 11, 250, 11, 255, 11
        db 0, 13, 5, 13, 10, 13, 15, 13, 32, 13, 37, 13, 42, 13, 47, 13
        db 64, 13, 69, 13, 74, 13, 79, 13, 96, 13, 101, 13, 106, 13, 111, 13
        db 144, 13, 149, 13, 154, 13, 159, 13, 176, 13, 181, 13, 186, 13, 191, 13
        db 208, 13, 213, 13, 218, 13, 223, 13, 240, 13, 245, 13, 250, 13, 255, 13
        db 0, 15, 5, 15, 10, 15, 15, 15, 32, 15, 37, 15, 42, 15, 47, 15
        db 64, 15, 69, 15, 74, 15, 79, 15, 96, 15, 101, 15, 106, 15, 111, 15
        db 144, 15, 149, 15, 154, 15, 159, 15, 176, 15, 181, 15, 186, 15, 191, 15
        db 208, 15, 213, 15, 218, 15, 223, 15, 240, 15, 245, 15, 250, 15, 255, 15
crtc_save: ds 22
pal_save:  ds 4
pal_ctrl:  db 0
win1_save: db 0
bank:      db 0
