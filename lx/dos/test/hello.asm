; hello.asm - Prueba de programas .COM en el LX-DOS (CP/M 2.2)
; pasmo hello.asm HELLO.COM
BDOS    equ 5
        org 100h
        ld de, msg              ; 9: cadena hasta '$'
        ld c, 9
        call BDOS
        ld e, 'O'               ; 2: caracteres
        ld c, 2
        call BDOS
        ld e, 'K'
        ld c, 2
        call BDOS
        ld e, ' '
        ld c, 2
        call BDOS
        ; BIOS de CP/M: CONOUT = (0001h) + 9
        ld hl, (1)
        ld de, 9
        add hl, de
        ld (conout + 1), hl
        ld c, 'B'
        call conout
        ld c, 'I'
        call conout
        ld c, 'O'
        call conout
        ld c, 'S'
        call conout
        ; 12: version -> HL = 0022h
        ld de, msgver
        ld c, 9
        call BDOS
        ld c, 12
        call BDOS
        ld a, l
        call hex
        ; linea de ordenes en 0080h
        ld de, msgtail
        ld c, 9
        call BDOS
        ld a, (80h)
        or a
        jr z, notail
        ld b, a
        ld hl, 81h
tail:   push bc
        push hl
        ld e, (hl)
        ld c, 2
        call BDOS
        pop hl
        pop bc
        inc hl
        djnz tail
notail: ; IX tras una llamada
        ld ix, 1234h
        ld c, 11
        call BDOS
        push ix
        pop hl
        ld de, 1234h
        or a
        sbc hl, de
        ld de, msgixok
        jr z, ixok
        ld de, msgixbad
ixok:   ld c, 9
        call BDOS
        ret                     ; a 0000h: vuelve al LX-DOS

conout: jp 0

hex:    push af
        rrca
        rrca
        rrca
        rrca
        call nib
        pop af
nib:    and 0Fh
        add a, '0'
        cp '9' + 1
        jr c, nib1
        add a, 7
nib1:   ld e, a
        ld c, 2
        jp BDOS

msg:     db "Hello from a .COM program on LX-DOS!", 13, 10, '$'
msgver:  db 13, 10, "CP/M version: $"
msgtail: db 13, 10, "Command tail:$"
msgixok: db 13, 10, "IX preserved: OK", 13, 10, '$'
msgixbad: db 13, 10, "IX preserved: FAIL", 13, 10, '$'
