; =============================================================================
; FDC_765.ASM - Disquetera con el uPD765 del Aleste LX (pagina MMIO 9, FF0480)
; Shaeon (Carlos Palmero). 00 estado, 01 datos, 02 motor (D0).
;
; Sin DMA: los bytes del sector se recogen sondeando el registro de estado
; (RQM, DIO y EXM). Discos de 720 KB (80 pistas, 2 caras, 9 sectores de 512).
; =============================================================================

module fdc_765

defc PORT_MMIO_PAGE = 0xF1
defc FDC_PAGE       = 9
defc FDC_MSR        = 0x00
defc FDC_DATA       = 0x01
defc FDC_MOTOR      = 0x02

defc MSR_RQM = 7
defc MSR_DIO = 6
defc MSR_EXM = 5

SECTION DRV_CODE

PUBLIC __fdc_765_vtable
__fdc_765_vtable:
    jp f765_detect
    jp f765_install
    jp f765_get_info
    jp f765_command
    jp f765_uninstall
    jp f765_read
    jp f765_status
    jp f765_read_multi
    jp f765_write_multi

f765_status:
    ld a, FDC_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (FDC_MSR)
    ret

; ---- detect: en reposo el 765 pide ordenes (RQM = 1, DIO = 0)
f765_detect:
    call f765_status
    and 0xC0
    cp 0x80
    ld a, 1
    ret z
    xor a
    ret

; ---- A = byte de orden -> carry si no responde
cmd_out:
    ld c, a
    ld b, 0
co_wait:
    in a, (FDC_MSR)
    bit MSR_RQM, a
    jr z, co_next
    bit MSR_DIO, a
    jr nz, co_fail              ; quiere dar resultados: desincronizado
    ld a, c
    out (FDC_DATA), a
    or a
    ret
co_next:
    djnz co_wait
co_fail:
    scf
    ret

; ---- -> A = byte de resultado; carry si no hay
res_in:
    ld b, 0
ri_wait:
    in a, (FDC_MSR)
    bit MSR_RQM, a
    jr z, ri_next
    bit MSR_DIO, a
    jr z, ri_fail
    in a, (FDC_DATA)
    or a
    ret
ri_next:
    djnz ri_wait
ri_fail:
    scf
    ret

; ---- SENSE INTERRUPT STATUS hasta que acabe la busqueda -> A = ST0
sense:
    ld a, 0x08
    call cmd_out
    ret c
    call res_in                 ; ST0
    ret c
    ld e, a
    cp 0x80                     ; orden invalida: nada pendiente
    jr z, sense
    call res_in                 ; PCN
    ld a, e
    bit 5, a                    ; SE: busqueda terminada
    jr z, sense
    or a
    ret

f765_install:
    ld a, FDC_PAGE
    out (PORT_MMIO_PAGE), a
    ld a, 1
    out (FDC_MOTOR), a
    ld a, 0x03                  ; SPECIFY: SRT/HUT, HLT y sin DMA (ND = 1)
    call cmd_out
    ld a, 0xA1
    call cmd_out
    ld a, 0x03
    call cmd_out
    ld a, 0xFF
    ld (cur_trk), a
    ld (cur_trk + 1), a
    xor a
    ret

f765_uninstall:
    ld a, FDC_PAGE
    out (PORT_MMIO_PAGE), a
    xor a
    out (FDC_MOTOR), a
    ret

f765_get_info:
    ld hl, info
    ret

f765_command:
    ld hl, 0
    ret

; ---- HL = bufer, A = unidad, D = pista, E = cara, C = sector (y B = cuenta)
f765_read:
    ld b, 1
f765_read_multi:
    push af
    ld a, 0x46                  ; READ DATA (MFM)
    jr rw_start
f765_write_multi:
    push af
    ld a, 0x45                  ; WRITE DATA (MFM)
rw_start:
    ld (r_cmd), a
    pop af
    push af
    ld a, b
    dec a
    add a, c
    ld (r_eot), a               ; ultimo sector
    pop af
    and 1
    ld (r_drv), a
    ld a, d
    ld (r_trk), a
    ld a, e
    and 1
    ld (r_head), a
    ld a, c
    ld (r_sec), a
    ld (r_buf), hl
    ld a, FDC_PAGE
    out (PORT_MMIO_PAGE), a
    ld a, 1
    out (FDC_MOTOR), a
    ; ---- recalibra la primera vez y busca la pista si cambia
    ld hl, cur_trk
    ld a, (r_drv)
    ld e, a
    ld d, 0
    add hl, de
    ld a, (hl)
    cp 0xFF
    jr nz, rd_known
    push hl
    ld a, 0x07                  ; RECALIBRATE
    call cmd_out
    ld a, (r_drv)
    call nc, cmd_out
    call nc, sense
    pop hl
    jp c, rd_timeout
    ld (hl), 0
    xor a
rd_known:
    ld b, a
    ld a, (r_trk)
    cp b
    jr z, rd_ontrack
    push hl
    ld a, 0x0F                  ; SEEK
    call cmd_out
    jr c, rd_seek_err
    ld a, (r_head)
    add a, a
    add a, a
    ld b, a
    ld a, (r_drv)
    or b
    call cmd_out
    ld a, (r_trk)
    call nc, cmd_out
    call nc, sense
rd_seek_err:
    pop hl
    jp c, rd_timeout
    ld a, (r_trk)
    ld (hl), a
rd_ontrack:
    ; ---- READ DATA / WRITE DATA (MFM): 9 bytes de orden
    ld a, (r_cmd)
    call cmd_out
    jp c, rd_timeout
    ld a, (r_head)
    add a, a
    add a, a
    ld b, a
    ld a, (r_drv)
    or b
    call cmd_out                ; HD US
    ld a, (r_trk)
    call nc, cmd_out            ; C
    ld a, (r_head)
    call nc, cmd_out            ; H
    ld a, (r_sec)
    call nc, cmd_out            ; R
    ld a, 2
    call nc, cmd_out            ; N: 512 bytes
    ld a, (r_eot)
    call nc, cmd_out            ; EOT: ultimo sector que se lee
    ld a, 0x2A
    call nc, cmd_out            ; GPL
    ld a, 0xFF
    call nc, cmd_out            ; DTL
    jr c, rd_timeout
    ; ---- ejecucion: un byte cada vez que RQM = 1 con EXM = 1
    ld hl, (r_buf)
    ld a, 16
    ld (r_to), a                ; espera maxima: 16 x 65536 vueltas (mas de 1 s)
    ld de, 0
rd_exec:
    in a, (FDC_MSR)
    bit MSR_RQM, a
    jr z, rd_noreq
    bit MSR_EXM, a
    jr z, rd_result             ; fin de la ejecucion
    bit MSR_DIO, a
    jr z, rd_put                ; el 765 pide un byte: escritura
    in a, (FDC_DATA)
    ld (hl), a
    inc hl
    ld de, 0
    jr rd_exec
rd_put:
    ld a, (hl)
    out (FDC_DATA), a
    inc hl
    ld de, 0
    jr rd_exec
rd_noreq:
    bit MSR_EXM, a
    jr nz, rd_wait
    bit 4, a                    ; CB: ocupado sin peticion ni ejecucion
    jr nz, rd_wait
    jr rd_result
rd_wait:
    dec de
    ld a, d
    or e
    jr nz, rd_exec
    ld a, (r_to)
    dec a
    ld (r_to), a
    jr nz, rd_exec
    jr rd_timeout
    ; ---- 7 bytes de resultado: ST0 ST1 ST2 C H R N
rd_result:
    call res_in
    jr c, rd_timeout
    ld (r_st), a
    call res_in
    jr c, rd_timeout
    ld (r_st + 1), a
    call res_in
    jr c, rd_timeout
    ld (r_st + 2), a
    ld b, 4
rd_rest:
    push bc
    call res_in
    pop bc
    jr c, rd_timeout
    djnz rd_rest
    ; ST1 sin EN (fin de pista, normal al llegar a EOT) y ST2
    ld a, (r_st + 1)
    and 0x7F
    ld b, a
    ld a, (r_st + 2)
    and 0x7F
    or b
    ret
rd_timeout:
    ld a, 0x80
    ret

SECTION DRV_DATA

info:
    dw info_name
    db 1, 0
    dw 0x0001
    db 0, 0
info_name:
    db "FDC uPD765", 0

cur_trk: db 0xFF, 0xFF
r_drv:   db 0
r_trk:   db 0
r_head:  db 0
r_sec:   db 0
r_eot:   db 0
r_cmd:   db 0x46
r_buf:   dw 0
r_st:    ds 3
r_to:    db 0
