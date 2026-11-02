; filetest.asm - Prueba de ficheros por FCB en el LX-DOS (CP/M 2.2)
; pasmo filetest.asm FILETEST.COM
BDOS    equ 5
DMA     equ 80h
        org 100h
        ld sp, stack
        ; ---- crear TEST.TXT y escribir 3 registros
        ld de, m_make
        call print
        call fcb_reset
        ld de, fcb
        ld c, 22                ; make
        call BDOS
        call result
        ld b, 3
        ld hl, rec1
wloop:  push bc
        push hl
        ld de, DMA              ; copia el registro al DMA
        ld bc, 128
        ldir
        ld de, fcb
        ld c, 21                ; escritura secuencial
        call BDOS
        call result
        pop hl
        ld de, 128
        add hl, de
        pop bc
        djnz wloop
        ld de, fcb
        ld c, 16                ; close
        call BDOS
        call result
        ; ---- abrir y leer hasta el final
        ld de, m_read
        call print
        call fcb_reset
        ld de, fcb
        ld c, 15                ; open
        call BDOS
        call result
rloop:  ld de, fcb
        ld c, 20                ; lectura secuencial
        call BDOS
        or a
        jr nz, reof
        ld hl, DMA              ; imprime el registro hasta '$'
        ld (DMA + 127), a       ; (A = 0) por si no hay '$'
        ld de, DMA
        ld c, 9
        call BDOS
        jr rloop
reof:   ld de, m_eof
        call print
        ; ---- renombrar a TEST2.TXT
        ld de, m_ren
        call print
        call fcb_reset
        ld hl, name2
        ld de, fcb + 17
        ld bc, 11
        ldir
        ld de, fcb
        ld c, 23
        call BDOS
        call result
        ; ---- buscar *.TXT
        ld de, m_search
        call print
        ld de, fcbw
        ld c, 17
        call BDOS
sloop:  inc a
        jr z, sdone
        ld hl, DMA + 1          ; nombre de la entrada (11 caracteres)
        ld b, 11
sname:  push bc
        push hl
        ld e, (hl)
        ld c, 2
        call BDOS
        pop hl
        pop bc
        inc hl
        djnz sname
        ld e, ' '
        ld c, 2
        call BDOS
        ld de, fcbw
        ld c, 18
        call BDOS
        jr sloop
sdone:  ; ---- borrar TEST2.TXT y comprobar que ya no se abre
        ld de, m_del
        call print
        ld hl, name2
        ld de, fcb + 1
        ld bc, 11
        ldir
        xor a
        ld (fcb), a
        ld (fcb + 12), a
        ld de, fcb
        ld c, 19
        call BDOS
        call result
        ld de, fcb
        ld c, 15
        call BDOS
        ld de, m_gone
        inc a
        jr z, gone
        ld de, m_still
gone:   call print
        ret

fcb_reset:                      ; FCB de TEST.TXT, todo a cero
        ld hl, fcb
        ld b, 36
fr1:    ld (hl), 0
        inc hl
        djnz fr1
        ld hl, name1
        ld de, fcb + 1
        ld bc, 11
        ldir
        ret

print:  ld c, 9
        jp BDOS

result: push af                 ; "[r]" con el codigo de vuelta
        ld e, '['
        ld c, 2
        call BDOS
        pop af
        push af
        and 0Fh
        add a, '0'
        cp '9' + 1
        jr c, r1
        add a, 7
r1:     ld e, a
        ld c, 2
        call BDOS
        ld e, ']'
        ld c, 2
        call BDOS
        pop af
        ret

name1:  db "TEST    TXT"
name2:  db "TEST2   TXT"
fcbw:   db 0, "????????TXT", 0, 0, 0, 0
        ds 20
m_make: db "Make + write 3 records + close: $"
m_read: db 13, 10, "Open + read:", 13, 10, '$'
m_eof:  db "(end of file)", 13, 10, '$'
m_ren:  db "Rename to TEST2.TXT: $"
m_search: db 13, 10, "Search *.TXT: $"
m_del:  db 13, 10, "Delete TEST2.TXT: $"
m_gone: db 13, 10, "Open after delete fails: OK", 13, 10, '$'
m_still: db 13, 10, "Open after delete: FAIL (still there)", 13, 10, '$'
rec1:   db "First record of TEST.TXT", 13, 10, '$'
        ds rec1 + 128 - $
rec2:   db "Second record", 13, 10, '$'
        ds rec2 + 128 - $
rec3:   db "Third and last record", 13, 10, '$'
        ds rec3 + 128 - $
fcb:    ds 36
        ds 64
stack:
