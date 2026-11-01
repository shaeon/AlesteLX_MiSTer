; =============================================================================
; DMA_LX.ASM - DMA / blitter del modo LX (pagina MMIO 6, FF0300)
; Shaeon (Carlos Palmero). Registros: doc/10-modo-lx.md del core.
; =============================================================================

module dma_lx

defc PORT_MMIO_PAGE = 0xF1
defc PORT_SUPER_SLOT = 0xFA
defc PORT_BANK_BASE  = 0xE0     ; E0-EF: banco de {slot, ventana}
defc DMA_PAGE       = 6
defc DMA_CTRL       = 0x00
defc DMA_STATUS     = 0x01
defc DMA_SRC        = 0x02
defc DMA_KEY        = 0x10

SECTION DRV_CODE

PUBLIC __dma_lx_vtable
__dma_lx_vtable:
    jp dma_lx_detect
    jp dma_lx_install
    jp dma_lx_get_info
    jp dma_lx_command
    jp dma_lx_uninstall
    jp dma_lx_start
    jp dma_lx_wait
    jp dma_lx_busy
    jp dma_lx_phys

; ---- detect: KEY se lee como se escribe
dma_lx_detect:
    ld a, DMA_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (DMA_KEY)
    ld c, a
    ld a, 0xC3
    out (DMA_KEY), a
    in a, (DMA_KEY)
    ld b, a
    ld a, c
    out (DMA_KEY), a
    ld a, b
    cp 0xC3
    ld a, 1
    ret z
    xor a
    ret

dma_lx_install:
    call dma_lx_wait
    ld a, DMA_PAGE
    out (PORT_MMIO_PAGE), a
    ld a, 1
    out (DMA_STATUS), a         ; borra un fin pendiente
    xor a
    ret

dma_lx_uninstall:
    jp dma_lx_wait

dma_lx_get_info:
    ld hl, info
    ret

dma_lx_command:
    ld hl, 0
    ret

; ---- HL = peticion de 16 bytes
dma_lx_start:
    push hl
    call dma_lx_wait            ; deja la pagina 6 elegida
    pop hl
    ld c, DMA_SRC
    ld b, 15
st_loop:
    ld a, (hl)
    out (c), a                  ; puertos 02h-10h (OTIR no avanza el puerto)
    inc hl
    inc c
    djnz st_loop
    ld a, (hl)                  ; modo
    and 0x03
    add a, a
    or 0x01                     ; arranca, sin interrupcion
    out (DMA_CTRL), a
    ret

; ---- espera a que acabe (deja elegida la pagina 6)
dma_lx_wait:
    ld a, DMA_PAGE
    out (PORT_MMIO_PAGE), a
wt_loop:
    in a, (DMA_CTRL)
    rrca
    jr c, wt_loop
    ret

dma_lx_busy:
    ld a, DMA_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (DMA_CTRL)
    and 0x01
    ret

; ---- HL = direccion de la CPU -> DEHL = fisica
;   fisica = slot << 22 | banco << 14 | (HL & 3FFFh)
dma_lx_phys:
    ld a, h
    rlca
    rlca
    and 0x03
    ld b, a                     ; B = ventana
    in a, (PORT_SUPER_SLOT)     ; 2 bits por ventana
    inc b
ph_sh:
    dec b
    jr z, ph_got
    rrca
    rrca
    jr ph_sh
ph_got:
    and 0x03
    ld d, a                     ; D = slot
    ld a, h
    rlca
    rlca
    and 0x03                    ; ventana
    ld c, a
    ld a, d
    add a, a
    add a, a
    or c
    or PORT_BANK_BASE
    ld c, a
    in a, (c)                   ; A = banco
    ld c, a
    ; H = (banco & 3) << 6 | (H & 3Fh)
    rrca
    rrca
    and 0xC0
    ld b, a
    ld a, h
    and 0x3F
    or b
    ld h, a
    ; E = slot << 6 | banco >> 2
    ld a, c
    srl a
    srl a
    ld e, a
    ld a, d
    rrca
    rrca
    and 0xC0
    or e
    ld e, a
    ld d, 0
    ret

SECTION DRV_DATA

info:
    dw info_name
    db 1, 0
    dw 0x0006                   ; estatico, usa DMA
    db 0, 0
info_name:
    db "DMA LX blitter", 0
