; modplay.asm - MODPLAY.COM: toca un MOD o un STM de fondo en el LX-DOS
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
;
;   MODPLAY fichero    lo carga y lo toca; la musica sigue al volver al DOS
;   MODPLAY /S         para la musica
;   MODPLAY            dice que suena y como se usa
;
; Usa la extension del BDOS del LX-DOS para la musica (lx/dos/bdos.c):
;   C = A0h, DE = nombre ASCIIZ (0 = parar) -> A = 0 bien, 1 no esta,
;                 2 error de disco, 3 formato, 4 demasiado grande
;   C = A1h, DE = 32 bytes de informacion
; Usa la pila que le da el DOS (con 0000h para volver con RET).
; pasmo modplay.asm MODPLAY.COM
BDOS    equ 5
TAIL    equ 80h
        org 100h
        ; ---- argumento: primer nombre de la linea de ordenes
        ld hl, TAIL
        ld b, (hl)              ; longitud
        inc hl
skip:   ld a, b
        or a
        jr z, noarg
        ld a, (hl)
        cp ' '
        jr nz, gotarg
        inc hl
        dec b
        jr skip
gotarg: cp '/'
        jr z, option
        ld de, fname            ; copia hasta el espacio o el final
copy:   ld a, (hl)
        cp ' '
        jr z, copied
        ld (de), a
        inc de
        inc hl
        djnz copy
copied: xor a
        ld (de), a
        ld de, m_load
        call print
        ld de, fname
        call prints
        ld de, m_dots
        call print
        ld de, fname
        ld c, 0A0h
        call BDOS
        or a
        jr nz, error
        ld de, m_crlf
        call print
        jr showinfo

option: inc hl                  ; /S
        ld a, (hl)
        and 0DFh
        cp 'S'
        jr nz, usage
        ld de, 0
        ld c, 0A0h
        call BDOS
        ld de, m_stop
        jp print

noarg:  ld de, info             ; sin argumentos: que suena
        ld c, 0A1h
        call BDOS
        ld a, (info)
        or a
        jr z, usage
showinfo:
        ld de, info
        ld c, 0A1h
        call BDOS
        ld de, m_play
        call print
        ld de, info + 9         ; titulo
        call prints
        ld de, m_kind1
        call print
        ld de, info + 5         ; MOD o STM
        call prints
        ld de, m_kind2
        call print
        ld a, (info + 2)
        call pdec
        ld de, m_pos
        call print
        ld a, (info + 3)
        call pdec
        ld de, m_pat
        jp print

usage:  ld de, m_usage
        jp print

error:  push af                 ; A = codigo de error
        ld de, m_crlf
        call print
        pop af
        ld de, e_notfound
        dec a
        jr z, perr
        ld de, e_disk
        dec a
        jr z, perr
        ld de, e_format
        dec a
        jr z, perr
        ld de, e_big
perr:   jp print

; ---- utilidades
print:  ld c, 9                 ; cadena hasta '$'
        jp BDOS

prints: ld a, (de)              ; cadena hasta 0
        or a
        ret z
        push de
        ld e, a
        ld c, 2
        call BDOS
        pop de
        inc de
        jr prints

pdec:   ld b, 0                 ; A en decimal (0-255) sin ceros a la izquierda
        ld c, 100
        call digit
        ld c, 10
        call digit
        ld b, 1
        ld c, 1
digit:  ld e, '0' - 1
dg1:    inc e
        sub c
        jr nc, dg1
        add a, c
        push af
        ld a, e
        cp '0'
        jr nz, dg2
        ld a, b
        or a
        jr z, dg3               ; cero a la izquierda: no se escribe
dg2:    ld b, 1
        push bc
        ld c, 2
        call BDOS
        pop bc
dg3:    pop af
        ret

m_load:   db "Loading $"
m_dots:   db "...$"
m_crlf:   db 13, 10, '$'
m_play:   db "Playing ", '"', '$'
m_kind1:  db '"', " ($"
m_kind2:  db ", $"
m_pos:    db " positions, $"
m_pat:    db " patterns)", 13, 10, "MODPLAY /S stops it.", 13, 10, '$'
m_stop:   db "Music stopped.", 13, 10, '$'
m_usage:  db "MODPLAY file   play a 4-channel MOD or an STM in the background", 13, 10
          db "MODPLAY /S     stop the music", 13, 10, '$'
e_notfound: db "File not found.", 13, 10, '$'
e_disk:   db "Disk error.", 13, 10, '$'
e_format: db "Not a 4-channel MOD or an STM.", 13, 10, '$'
e_big:    db "File too big.", 13, 10, '$'
fname:    ds 16
info:     ds 32
          ds 64
stack:
