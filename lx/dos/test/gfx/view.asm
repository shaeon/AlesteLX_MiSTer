; view.asm - VIEW.COM: visor de imagenes .LXI (320x200, 256 colores) del LX-DOS
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
;
;   VIEW              todas las *.LXI de la unidad actual
;   VIEW nombre       una, o varias con comodines (VIEW B:*.LXI)
; Una tecla pasa a la siguiente; Esc sale. Usa la funcion A2h del BDOS del
; LX-DOS (gfx8.c): carga la imagen y pone el modo; A2h con DE = 0 vuelve al
; texto. pasmo view.asm VIEW.COM
BDOS    equ 5
FCB     equ 5Ch
DMA     equ 80h
MAXN    equ 64
        org 100h
        ; ---- sin nombre: *.LXI
        ld a, (FCB + 1)
        cp ' '
        jr nz, has_name
        ld hl, star_lxi
        ld de, FCB + 1
        ld bc, 11
        ldir
has_name:
        ; ---- la unidad del FCB (0 = la actual) para los nombres
        ld a, (FCB)
        ld (drive), a
        ; ---- la lista de nombres (busqueda 17h / 18h), en 'names', 13 bytes cada uno
        ld hl, names
        ld (np), hl
        xor a
        ld (count), a
        ld de, FCB
        ld c, 17
        call BDOS
found:  inc a
        jr z, listed
        call add_name
        ld a, (count)
        cp MAXN
        jr z, listed
        ld de, FCB
        ld c, 18
        call BDOS
        jr found
listed: ld a, (count)
        or a
        jr nz, show_all
        ld de, m_none
        ld c, 9
        jp BDOS                 ; y vuelve al DOS
        ; ---- una a una
show_all:
        ld hl, names
        ld a, (count)
        ld b, a
next:   push bc
        push hl
        ex de, hl
        ld c, 0A2h
        call BDOS               ; carga y muestra
        or a
        jr z, shown
        ; error: al texto, mensaje y sigue
        push af
        ld de, 0
        ld c, 0A2h
        call BDOS
        pop af
        ld de, e_nofile
        cp 1
        jr z, perr
        ld de, e_disk
        cp 2
        jr z, perr
        ld de, e_format
perr:   pop hl
        push hl
        call print_name
        ld c, 9
        call BDOS
        jr skip
shown:  ld c, 8                 ; una tecla, sin eco (MSX-DOS)
        call BDOS
        cp 27
        jr z, quit
skip:   pop hl
        ld de, 13
        add hl, de
        pop bc
        djnz next
        jr done
quit:   pop hl
        pop bc
done:   ld de, 0
        ld c, 0A2h
        call BDOS               ; al texto
        ret

; El nombre de la entrada encontrada (en el DMA, al estilo CP/M: 1-11) ->
; "X:NOMBRE.EXT" en la lista
add_name:
        ld de, (np)
        ld a, (drive)
        or a
        jr z, an_nodrv
        add a, 'A' - 1
        ld (de), a
        inc de
        ld a, ':'
        ld (de), a
        inc de
an_nodrv:
        ld hl, DMA + 1
        ld b, 8
an_n:   ld a, (hl)
        and 7Fh
        cp ' '
        jr z, an_nsk
        ld (de), a
        inc de
an_nsk: inc hl
        djnz an_n
        ld a, (hl)
        cp ' '
        jr z, an_end
        ld a, '.'
        ld (de), a
        inc de
        ld b, 3
an_e:   ld a, (hl)
        and 7Fh
        cp ' '
        jr z, an_esk
        ld (de), a
        inc de
an_esk: inc hl
        djnz an_e
an_end: xor a
        ld (de), a
        ld hl, (np)
        ld de, 13
        add hl, de
        ld (np), hl
        ld hl, count
        inc (hl)
        ret

print_name:                     ; HL = nombre ASCIIZ
        ld a, (hl)
        or a
        ret z
        push hl
        push de
        ld e, a
        ld c, 2
        call BDOS
        pop de
        pop hl
        inc hl
        jr print_name

star_lxi: db "????????LXI"
m_none:   db "No .LXI images (make them with tools/img2lx.py)", 13, 10, '$'
e_nofile: db ": not found", 13, 10, '$'
e_disk:   db ": disk error", 13, 10, '$'
e_format: db ": not an LXI image", 13, 10, '$'
drive:    db 0
count:    db 0
np:       dw 0
names:    ds MAXN * 13
