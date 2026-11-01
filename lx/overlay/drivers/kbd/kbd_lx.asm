; =============================================================================
; KBD_LX.ASM - Teclado del modo LX (pagina MMIO 8, FF0400)
; Shaeon (Carlos Palmero). Registros: doc/10-modo-lx.md del core.
;
; La interrupcion (linea 7) vacia la cola de eventos PS/2 del hardware,
; lleva el estado de mayusculas/control/bloq mayus y deja los caracteres en
; un bufer circular de 32.
; =============================================================================

module kbd_lx

defc PORT_MMIO_PAGE = 0xF1
defc KIN_PAGE       = 8
defc KIN_STATUS     = 0x00
defc KIN_FLAGS      = 0x01
defc KIN_CODE       = 0x02
defc KIN_CTRL       = 0x03
defc KIN_ROW        = 0x10
defc KIN_IRQ_LINE   = 7

defc SH_SHIFT = 0x01
defc SH_CTRL  = 0x02
defc SH_CAPS  = 0x04

EXTERN __int_set_handler, __int_enable, __int_disable

SECTION DRV_CODE

PUBLIC __kbd_lx_vtable
__kbd_lx_vtable:
    jp kbd_lx_detect
    jp kbd_lx_install
    jp kbd_lx_get_info
    jp kbd_lx_command
    jp kbd_lx_uninstall
    jp kbd_lx_hit
    jp kbd_lx_getc
    jp kbd_lx_shift_state
    jp kbd_lx_row

; ---- detect: CTRL se lee como se escribe
kbd_lx_detect:
    ld a, KIN_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (KIN_CTRL)
    ld c, a
    ld a, 0x5A
    out (KIN_CTRL), a
    in a, (KIN_CTRL)
    ld b, a
    ld a, c
    out (KIN_CTRL), a
    ld a, b
    cp 0x5A
    ld a, 1
    ret z
    xor a
    ret

kbd_lx_install:
    di
    xor a
    ld (head), a
    ld (tail), a
    ld (shift), a
    ld (lshift), a
    ld (rshift), a
    ld a, KIN_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (KIN_STATUS)          ; borra el desbordamiento
kin_drain:
    in a, (KIN_STATUS)
    rrca
    jr nc, kin_empty
    in a, (KIN_CODE)
    jr kin_drain
kin_empty:
    ei
    ld a, KIN_IRQ_LINE
    ld hl, kbd_isr
    call __int_set_handler
    ld a, KIN_PAGE
    out (PORT_MMIO_PAGE), a
    ld a, 1
    out (KIN_CTRL), a           ; interrupcion con eventos
    ld a, KIN_IRQ_LINE
    call __int_enable
    xor a
    ret

kbd_lx_uninstall:
    ld a, KIN_IRQ_LINE
    call __int_disable
    ld a, KIN_PAGE
    out (PORT_MMIO_PAGE), a
    xor a
    out (KIN_CTRL), a
    ret

kbd_lx_get_info:
    ld hl, info
    ret

kbd_lx_command:
    ld hl, 0
    ret

kbd_lx_hit:
    ld a, (head)
    ld b, a
    ld a, (tail)
    cp b
    ld a, 0
    ret z
    inc a
    ret

kbd_lx_getc:
    call kbd_lx_hit
    or a
    jr z, kbd_lx_getc
    ld a, (tail)
    ld e, a
    ld d, 0
    ld hl, buffer
    add hl, de
    ld c, (hl)
    inc a
    and 31
    ld (tail), a
    ld a, c
    ret

kbd_lx_shift_state:
    ld a, (shift)
    ret

kbd_lx_row:
    and 0x0F
    or KIN_ROW
    ld c, a
    ld a, KIN_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (c)
    ret

; ---- rutina del PIC: vacia la cola del hardware
kbd_isr:
    ld a, KIN_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (KIN_STATUS)
    rrca
    ret nc
    in a, (KIN_FLAGS)
    ld b, a                     ; bit 0 pulsada, bit 1 extendida
    in a, (KIN_CODE)
    ld c, a
    call kbd_event
    jr kbd_isr

; B = flags, C = codigo
kbd_event:
    ld a, c
    cp 0x12
    jr z, ev_lshift
    cp 0x59
    jr z, ev_rshift
    cp 0x14
    jr z, ev_ctrl
    bit 0, b
    ret z                       ; soltar una tecla normal: nada
    cp 0x58
    jr z, ev_caps
    bit 1, b
    jr nz, ev_ext
    cp 0x80
    ret nc
    ; normal: tabla segun mayusculas
    ld e, a
    ld d, 0
    ld a, (shift)
    and SH_SHIFT
    ld hl, kbd_tab_normal
    jr z, ev_tab
    ld hl, kbd_tab_shift
ev_tab:
    add hl, de
    ld a, (hl)
    or a
    ret z
    ; bloq mayus invierte las letras
    ld c, a
    ld a, (shift)
    and SH_CAPS
    ld a, c
    jr z, ev_ctrlk
    call is_alpha
    jr nc, ev_ctrlk
    xor 0x20
ev_ctrlk:
    ld c, a
    ld a, (shift)
    and SH_CTRL
    ld a, c
    jr z, put_char
    call is_alpha
    jr nc, put_char
    and 0x1F                    ; control+letra
    jr put_char

ev_ext:
    ld hl, kbd_tab_ext
ext_loop:
    ld a, (hl)
    or a
    ret z
    inc hl
    cp c
    ld a, (hl)
    inc hl
    jr nz, ext_loop
    jr put_char

ev_lshift:
    ld a, b
    and 1
    ld (lshift), a
    jr upd_shift
ev_rshift:
    ld a, b
    and 1
    ld (rshift), a
upd_shift:
    ld a, (lshift)
    ld c, a
    ld a, (rshift)
    or c
    ld c, a                     ; C = 1 si alguna pulsada
    ld a, (shift)
    and ~SH_SHIFT & 0xFF
    or c
    ld (shift), a
    ret
ev_ctrl:
    ld a, (shift)
    and ~SH_CTRL & 0xFF
    bit 0, b
    jr z, ev_ctrl_set
    or SH_CTRL
ev_ctrl_set:
    ld (shift), a
    ret
ev_caps:
    ld a, (shift)
    xor SH_CAPS
    ld (shift), a
    ret

; A = caracter -> carry si es letra (A-Z, a-z); conserva A
is_alpha:
    push af
    and 0xDF
    cp 'A'
    jr c, ia_no
    cp 'Z'+1
    jr nc, ia_no
    pop af
    scf
    ret
ia_no:
    pop af
    or a
    ret

; A = caracter: al bufer (si esta lleno, se pierde)
put_char:
    ld c, a
    ld a, (head)
    ld e, a
    inc a
    and 31
    ld b, a
    ld a, (tail)
    cp b
    ret z
    ld d, 0
    ld hl, buffer
    add hl, de
    ld (hl), c
    ld a, b
    ld (head), a
    ret

; Tablas PS/2 (juego 2) -> ASCII, teclado de EE. UU. Generadas por script.
; 80h arriba, 81h abajo, 82h izquierda, 83h derecha, 84h inicio, 85h fin,
; 86h re pag, 87h av pag, 88h insert, 7Fh suprimir, 90h-99h F1-F10.
kbd_tab_normal:
    db 0x00, 0x98, 0x00, 0x94, 0x92, 0x90, 0x91, 0x00, 0x00, 0x99, 0x97, 0x95, 0x93, 0x09, 0x60, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x71, 0x31, 0x00, 0x00, 0x00, 0x7A, 0x73, 0x61, 0x77, 0x32, 0x00
    db 0x00, 0x63, 0x78, 0x64, 0x65, 0x34, 0x33, 0x00, 0x00, 0x20, 0x76, 0x66, 0x74, 0x72, 0x35, 0x00
    db 0x00, 0x6E, 0x62, 0x68, 0x67, 0x79, 0x36, 0x00, 0x00, 0x00, 0x6D, 0x6A, 0x75, 0x37, 0x38, 0x00
    db 0x00, 0x2C, 0x6B, 0x69, 0x6F, 0x30, 0x39, 0x00, 0x00, 0x2E, 0x2F, 0x6C, 0x3B, 0x70, 0x2D, 0x00
    db 0x00, 0x00, 0x27, 0x00, 0x5B, 0x3D, 0x00, 0x00, 0x00, 0x00, 0x0D, 0x5D, 0x00, 0x5C, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x31, 0x00, 0x34, 0x37, 0x00, 0x00, 0x00
    db 0x30, 0x2E, 0x32, 0x35, 0x36, 0x38, 0x1B, 0x00, 0x00, 0x2B, 0x33, 0x2D, 0x2A, 0x39, 0x00, 0x00
kbd_tab_shift:
    db 0x00, 0x98, 0x00, 0x94, 0x92, 0x90, 0x91, 0x00, 0x00, 0x99, 0x97, 0x95, 0x93, 0x09, 0x7E, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x51, 0x21, 0x00, 0x00, 0x00, 0x5A, 0x53, 0x41, 0x57, 0x40, 0x00
    db 0x00, 0x43, 0x58, 0x44, 0x45, 0x24, 0x23, 0x00, 0x00, 0x20, 0x56, 0x46, 0x54, 0x52, 0x25, 0x00
    db 0x00, 0x4E, 0x42, 0x48, 0x47, 0x59, 0x5E, 0x00, 0x00, 0x00, 0x4D, 0x4A, 0x55, 0x26, 0x2A, 0x00
    db 0x00, 0x3C, 0x4B, 0x49, 0x4F, 0x29, 0x28, 0x00, 0x00, 0x3E, 0x3F, 0x4C, 0x3A, 0x50, 0x5F, 0x00
    db 0x00, 0x00, 0x22, 0x00, 0x7B, 0x2B, 0x00, 0x00, 0x00, 0x00, 0x0D, 0x7D, 0x00, 0x7C, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x31, 0x00, 0x34, 0x37, 0x00, 0x00, 0x00
    db 0x30, 0x2E, 0x32, 0x35, 0x36, 0x38, 0x1B, 0x00, 0x00, 0x2B, 0x33, 0x2D, 0x2A, 0x39, 0x00, 0x00
; extendidas (E0): pares codigo, caracter; 0 = fin
kbd_tab_ext:
    db 0x75, 0x80
    db 0x72, 0x81
    db 0x6B, 0x82
    db 0x74, 0x83
    db 0x6C, 0x84
    db 0x69, 0x85
    db 0x7D, 0x86
    db 0x7A, 0x87
    db 0x70, 0x88
    db 0x71, 0x7F
    db 0x5A, 0x0D
    db 0x4A, 0x2F
    db 0x00

SECTION DRV_DATA

info:
    dw info_name
    db 1, 0
    dw 0x0003
    db KIN_IRQ_LINE, 0
info_name:
    db "KBD LX PS/2", 0

head:   db 0
tail:   db 0
shift:  db 0
lshift: db 0
rshift: db 0
buffer: ds 32
