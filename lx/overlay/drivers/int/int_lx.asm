; =============================================================================
; INT_LX.ASM - Interrupciones con el PIC del modo LX (pagina MMIO 0, FF0000)
; Shaeon (Carlos Palmero). Registros: doc/10-modo-lx.md del core.
;
; Despachador de IM 1: guarda registros y pagina MMIO, lee las lineas
; pendientes y habilitadas, las borra en el PIC y llama a la rutina de cada
; una (de la 0 a la 15). Lineas: 0 disquetera, 1 DMA, 2 VBlank, 3 Magic
; Sound 2, 4 Gate Array (300 Hz), 6 temporizador.
; =============================================================================

module int_lx

defc PORT_MMIO_PAGE = 0xF1
defc PIC_PAGE       = 0
defc PIC_MASK_LO    = 0x00
defc PIC_MASK_HI    = 0x01
defc PIC_VECTOR     = 0x02
defc PIC_STATUS_LO  = 0x03
defc PIC_STATUS_HI  = 0x04
defc PIC_CLEAR_LO   = 0x07
defc PIC_CLEAR_HI   = 0x08

SECTION DRV_CODE

PUBLIC __int_lx_vtable
__int_lx_vtable:
    jp int_lx_detect
    jp int_lx_install
    jp int_lx_get_info
    jp int_lx_command
    jp int_lx_uninstall
    jp int_lx_set_handler
    jp int_lx_enable
    jp int_lx_disable
    jp int_lx_isr

; ---- detect: el registro VECTOR del PIC se lee como se escribe
int_lx_detect:
    ld a, PIC_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (PIC_VECTOR)
    ld c, a
    ld a, 0x5A
    out (PIC_VECTOR), a
    in a, (PIC_VECTOR)
    ld b, a
    ld a, c
    out (PIC_VECTOR), a
    ld a, b
    cp 0x5A
    ld a, 1
    ret z
    xor a
    ret

; ---- install: todo enmascarado y borrado, sin rutinas, IM 1 y EI
int_lx_install:
    di
    ld hl, handlers
    ld b, 32
int_clr:
    ld (hl), 0
    inc hl
    djnz int_clr
    xor a
    ld (mask_lo), a
    ld (mask_hi), a
    ld a, PIC_PAGE
    out (PORT_MMIO_PAGE), a
    xor a
    out (PIC_MASK_LO), a
    out (PIC_MASK_HI), a
    ld a, 0xFF
    out (PIC_CLEAR_LO), a
    out (PIC_CLEAR_HI), a
    im 1
    ei
    xor a
    ret

int_lx_uninstall:
    di
    ld a, PIC_PAGE
    out (PORT_MMIO_PAGE), a
    xor a
    out (PIC_MASK_LO), a
    out (PIC_MASK_HI), a
    ld (mask_lo), a
    ld (mask_hi), a
    ret

int_lx_get_info:
    ld hl, info
    ret

; sin ordenes propias
int_lx_command:
    ld hl, 0
    ret

; ---- set_handler: A = linea, HL = rutina
int_lx_set_handler:
    and 0x0F
    ex de, hl
    ld l, a
    ld h, 0
    add hl, hl
    ld bc, handlers
    add hl, bc
    di                          ; los dos bytes sin que entre una interrupcion
    ld (hl), e
    inc hl
    ld (hl), d
    ei
    ret

; ---- enable / disable: A = linea. Actualiza la copia y el PIC.
int_lx_enable:
    call line_bit               ; HL = &mask_lo o &mask_hi, C = bit, E = puerto
    di
    ld a, (hl)
    or c
    jr mask_out
int_lx_disable:
    call line_bit
    di
    ld a, c
    cpl
    and (hl)
mask_out:
    ld (hl), a
    ld b, a
    ld a, PIC_PAGE
    out (PORT_MMIO_PAGE), a
    ld c, e
    out (c), b
    ei
    ret

; A = linea -> HL = &mask_lo o &mask_hi, C = mascara del bit, E = puerto (0/1)
line_bit:
    and 0x0F
    ld hl, mask_lo
    ld e, PIC_MASK_LO
    cp 8
    jr c, lb_lo
    inc hl
    ld e, PIC_MASK_HI
    sub 8
lb_lo:
    ld b, a
    ld c, 1
    inc b
lb_sh:
    dec b
    ret z
    sla c
    jr lb_sh

; ---- despachador de IM 1
int_lx_isr:
    push af
    push bc
    push de
    push hl
    push ix
    push iy
    in a, (PORT_MMIO_PAGE)      ; pagina del programa interrumpido
    push af
    ld a, PIC_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (PIC_STATUS_LO)
    ld e, a
    in a, (PIC_STATUS_HI)
    ld d, a
    ld a, e                     ; las borra antes de atenderlas: si llega otra
    out (PIC_CLEAR_LO), a       ; durante la rutina, se vuelve a capturar
    ld a, d
    out (PIC_CLEAR_HI), a
    ld hl, handlers
    ld b, 0                     ; B = linea
isr_next:
    ld a, d
    or e
    jr z, isr_done
    srl d
    rr e
    jr nc, isr_skip
    push hl
    push de
    push bc
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    or h
    jr z, isr_none
    ld a, b
    call jp_hl
isr_none:
    pop bc
    pop de
    pop hl
isr_skip:
    inc hl
    inc hl
    inc b
    jr isr_next
isr_done:
    pop af
    out (PORT_MMIO_PAGE), a
    pop iy
    pop ix
    pop hl
    pop de
    pop bc
    pop af
    ei
    reti

jp_hl:
    jp (hl)

SECTION DRV_DATA

info:
    dw info_name
    db 1, 0
    dw 0x0003                   ; usa IRQ, estatico
    db 0, 0
info_name:
    db "INT LX PIC", 0

mask_lo:  db 0
mask_hi:  db 0
handlers: ds 32
