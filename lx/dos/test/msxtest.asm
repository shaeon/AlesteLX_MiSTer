; msxtest.asm - Prueba de las funciones de MSX-DOS 1 en el LX-DOS
; pasmo msxtest.asm MSXTEST.COM
BDOS    equ 5
        org 100h
        ld sp, stack
        ; ---- fecha: poner 2026-11-02 y leerla
        ld hl, 2026
        ld d, 11
        ld e, 2
        ld c, 2Bh
        call BDOS
        ld de, m_date
        call print
        ld c, 2Ah
        call BDOS               ; HL ano, D mes, E dia, A dia de la semana
        push af
        push de
        call pdec               ; ano
        ld e, '-'
        call pch
        pop de
        push de
        ld l, d
        ld h, 0
        call pdec2              ; mes
        ld e, '-'
        call pch
        pop de
        ld l, e
        ld h, 0
        call pdec2              ; dia
        ld de, m_wd
        call print
        pop af
        ld l, a
        ld h, 0
        call pdec               ; 1 = lunes
        ; ---- hora: poner 12:34:56 y leerla
        ld hl, 0C22h            ; 12:34
        ld d, 56
        ld e, 0
        ld c, 2Dh
        call BDOS
        ld de, m_time
        call print
        ld c, 2Ch
        call BDOS               ; H, L, D
        push de
        push hl
        ld l, h
        ld h, 0
        call pdec2
        ld e, ':'
        call pch
        pop hl
        ld h, 0
        call pdec2
        ld e, ':'
        call pch
        pop de
        ld l, d
        ld h, 0
        call pdec2
        ; ---- asignacion del disco
        ld de, m_alloc
        call print
        ld e, 0
        ld c, 1Bh
        call BDOS               ; A spc, BC 512, DE total, HL libres
        push hl
        push de
        push bc
        ld l, a
        ld h, 0
        call pdec
        ld de, m_spc
        call print
        pop hl
        call pdec
        ld de, m_bps
        call print
        pop hl
        call pdec
        ld de, m_tot
        call print
        pop hl
        call pdec
        ld de, m_free
        call print
        ; ---- bloques: 300 bytes con registros de 1 byte
        ld de, m_blk
        call print
        call fcb_reset
        ld de, fcb
        ld c, 16h               ; crear
        call BDOS
        ld hl, 1
        ld (fcb + 14), hl       ; tamano de registro = 1
        ld hl, 0
        ld (fcb + 33), hl
        ld (fcb + 35), hl
        ld de, data
        ld c, 1Ah               ; DMA = data
        call BDOS
        ld hl, 300
        ld de, fcb
        ld c, 26h               ; escritura de bloque
        call BDOS
        call pres
        ld de, fcb
        ld c, 10h
        call BDOS
        call fcb_reset
        ld de, fcb
        ld c, 0Fh               ; abrir
        call BDOS
        ld de, m_size           ; tamano del fichero (bytes 16-19 del FCB)
        call print
        ld hl, (fcb + 16)
        call pdec
        ld hl, 1
        ld (fcb + 14), hl
        ld hl, 0
        ld (fcb + 33), hl
        ld (fcb + 35), hl
        ld de, buf
        ld c, 1Ah
        call BDOS
        ld hl, 500              ; pide 500, hay 300
        ld de, fcb
        ld c, 27h               ; lectura de bloque
        call BDOS
        push hl
        push af
        ld de, m_read
        call print
        pop af
        call pres
        ld de, m_got
        call print
        pop hl
        call pdec
        ld de, m_cmp            ; compara lo leido
        call print
        ld hl, data
        ld de, buf
        ld bc, 300
cmp1:   ld a, (de)
        cp (hl)
        jr nz, cmpbad
        inc hl
        inc de
        dec bc
        ld a, b
        or c
        jr nz, cmp1
        ld de, m_ok
        jr cmpend
cmpbad: ld de, m_bad
cmpend: call print
        ld de, fcb
        ld c, 13h               ; borrar
        call BDOS
        ; ---- sector de arranque (2Fh) -> nombre del formateador (3-10)
        ld de, m_abs
        call print
        ld de, buf
        ld c, 1Ah
        call BDOS
        ld de, 0                ; sector 0
        ld hl, 0100h            ; H = 1 sector, L = unidad A
        ld c, 2Fh
        call BDOS
        call pres
        ld e, ' '
        call pch
        ld hl, buf + 3
        ld b, 8
abs1:   push bc
        push hl
        ld e, (hl)
        call pch
        pop hl
        pop bc
        inc hl
        djnz abs1
        ld de, m_end
        call print
        ret

fcb_reset:
        ld hl, fcb
        ld b, 37
fr1:    ld (hl), 0
        inc hl
        djnz fr1
        ld hl, name
        ld de, fcb + 1
        ld bc, 11
        ldir
        ret

print:  ld c, 9
        jp BDOS
pch:    ld c, 2
        jp BDOS
pres:   push af                 ; "[A]"
        ld e, '['
        call pch
        pop af
        add a, '0'
        ld e, a
        call pch
        ld e, ']'
        jp pch

pdec2:  ld a, l                 ; dos cifras
        cp 10
        jr nc, pdec
        push hl
        ld e, '0'
        call pch
        pop hl
pdec:   xor a                   ; HL en decimal
        ld (started), a
        ld de, -10000
        call dig
        ld de, -1000
        call dig
        ld de, -100
        call dig
        ld de, -10
        call dig
        ld a, l
        add a, '0'
        ld e, a
        jp pch
dig:    ld a, '0' - 1
dig1:   inc a
        add hl, de
        jr c, dig1
        sbc hl, de
        cp '0'
        jr nz, dig2
        ld c, a
        ld a, (started)         ; (la llamada al BDOS cambia B: el estado va en memoria)
        or a
        ld a, c
        ret z
dig2:   ld c, a
        ld a, 1
        ld (started), a
        ld a, c
        push hl
        ld e, a
        call pch
        pop hl
        ret

started: db 0
name:   db "BLK     DAT"
m_date: db "Date (set 2026-11-02): $"
m_wd:   db "  weekday $"
m_time: db 13, 10, "Time (set 12:34:56): $"
m_alloc: db 13, 10, "Alloc info: $"
m_spc:  db " sect/cluster, $"
m_bps:  db " bytes/sector, $"
m_tot:  db " clusters, $"
m_free: db " free$"
m_blk:  db 13, 10, "Block write 300 x 1 byte: $"
m_size: db 13, 10, "File size after open: $"
m_read: db 13, 10, "Block read 500: $"
m_got:  db " records read: $"
m_cmp:  db 13, 10, "Data compare: $"
m_ok:   db "OK$"
m_bad:  db "FAIL$"
m_abs:  db 13, 10, "Absolute read sector 0: $"
m_end:  db 13, 10, '$'
data:
        rept 300
        db ($ - data) & 0FFh
        endm
fcb:    ds 37
buf:    ds 512
        ds 64
stack:
