;; ============================================================
;; vbuf_64k8b.asm - Driver vbuf 320x200, 256 colores (8 bpp lineal)
;; Shaeon (Carlos Palmero), para la BIOS del Aleste LX (aleste-xi-bios, hww).
;;
;; Modo 10 de la tabla del CRTC (__mode_64k8b: R18 8 bpp, R20 lineal con 8
;; bytes por caracter, R21) con la VRAM en C50000 (R19 = C5h): un byte por
;; pixel, 320 por linea, 64000 bytes. Con doble bufer, la pagina de atras es
;; C60000 y swap_buffers las intercambia cambiando R19.
;;
;; Todo se escribe con la DMA/blitter, por direcciones fisicas: no usa
;; ninguna ventana de la CPU (el LX-DOS tiene la suya en la ventana 2).
;;
;; Registros de los metodos (los de hww donde ya los habia):
;;   init, get_mode_info -> HL; command A = orden, DE = parametro -> A
;;   clear A = color                       scroll_up / scroll_down A = lineas
;;   clear_rect, fill_rect, draw_rect      DE -> {x, y, w, h}, A = color
;;   set_clip_rect / get_clip_rect         DE -> {x, y, w, h}
;;   copy_rect                             DE -> {sx, sy, dx, dy, w, h}
;;   get_addr BC = x, DE = y -> A:HL fisica
;;   put_pixel_fast, put_pixel             BC = x, DE = y, A = color (put_pixel -> A = 1 si se recorto)
;;   get_pixel BC = x, DE = y -> A
;;   draw_hline, draw_vline                BC = x, DE = y, HL = longitud, A = color
;;   draw_line                             DE -> {x1, y1, x2, y2}, A = color
;;   draw_char_at_addr                     HL = 8 bytes del caracter, DE = desplazamiento en la VRAM
;;   draw_char                             HL = fuente (desde el caracter 20h, 8 bytes cada uno),
;;                                         A = codigo, BC = x, DE = y
;;   draw_bitmap                           HL = pixeles (memoria de la CPU), DE -> {x, y, w, h}
;;   swap_buffers; get_backbuf -> A:HL; clear_backbuf A = color
;; Ordenes (command): 00 reiniciar, 01/02 doble bufer si/no, 10 tinta = E,
;;   11 fondo = E, 12 fondo transparente = E (0/1), 13 color transparente de
;;   los mapas de bits: E = color, D = 0/1 (desactivado/activado),
;;   14 pagina de la VRAM (byte alto) = E (la de atras, E + 1)
;; ============================================================
module vbuf_64k8b

EXTERN __crtc_set_mode
EXTERN __dma_start, __dma_wait, __dma_phys

defc SCR_W          = 320
defc SCR_H          = 200
defc VRAM_HI        = 0xC5          ; C50000
defc CRTC_MODE      = 10            ; __mode_64k8b
defc PORT_MMIO_PAGE = 0xF1
defc CRTC_PAGE      = 2
defc CRTC_ADDR      = 0x20
defc CRTC_DATA      = 0x21
defc DMA_COPY       = 0
defc DMA_FILL       = 1
defc DMA_KEY        = 2

; ---- Tabla del driver
section DRV_VTABLE
PUBLIC __drv_64k8b_vtable
__drv_64k8b_vtable:
    jp d8_init
    jp d8_get_mode_info
    jp d8_command
    jp d8_clear
    jp d8_fill_rect             ; clear_rect
    jp d8_scroll_up
    jp d8_scroll_down
    jp d8_set_clip_rect
    jp d8_get_clip_rect
    jp d8_copy_rect
    jp d8_get_addr
    jp d8_put_pixel_fast
    jp d8_put_pixel
    jp d8_get_pixel
    jp d8_draw_hline
    jp d8_draw_vline
    jp d8_draw_line
    jp d8_draw_rect
    jp d8_fill_rect
    jp d8_draw_char_at_addr
    jp d8_draw_char
    jp d8_draw_bitmap
    jp d8_swap_buffers
    jp d8_get_backbuf
    jp d8_clear_backbuf

; ---- Datos
section DRV_DATA
d8_mode_info:
    dw SCR_W, SCR_H
    db 8                        ; bpp
    db 0                        ; bytes por linea: 320 no cabe en un byte
    dw 64000
    db 0x04                     ; lineal
d8_clip:    dw 0, 0, SCR_W, SCR_H
d8_front:   db VRAM_HI
d8_back:    db VRAM_HI + 1
d8_base:    db VRAM_HI          ; donde se dibuja
d8_dbl:     db 0
d8_fg:      db 15
d8_bg:      db 0
d8_bgtr:    db 0
d8_key:     db 0
d8_keyen:   db 0
d8_color:   db 0
; rectangulo de trabajo (x, y, w, h) y lo que se recorta por la izquierda y arriba
d8_rx:      dw 0
d8_ry:      dw 0
d8_rw:      dw 0
d8_rh:      dw 0
d8_skx:     dw 0
d8_sky:     dw 0
d8_tmp:     dw 0, 0, 0, 0, 0, 0
d8_err:     dw 0
; peticion de la DMA: origen (3), destino (3), ancho, alto, pasos, clave, modo
d8_rq:      ds 16
d8_pix:     db 0
d8_glyph:   ds 64

section DRV_CODE

; ---- utilidades -------------------------------------------------------------

; Lanza d8_rq y espera
d8_go:
    ld hl, d8_rq
    call __dma_start
    jp __dma_wait

; HL = desplazamiento -> destino de d8_rq en la pagina de dibujo
d8_set_dst:
    ld (d8_rq + 3), hl
    ld a, (d8_base)
    ld (d8_rq + 5), a
    ret

; BC = x, DE = y -> HL = y * 320 + x (cabe en 16 bits); conserva BC, DE
d8_offset:
    push de
    ld h, e
    ld l, 0                     ; y * 256
    push hl
    ex de, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                  ; y * 64
    pop de
    add hl, de
    add hl, bc
    pop de
    ret

; Rellena el rectangulo de trabajo ya recortado con A (pasos de 320)
d8_fill_work:
    ld (d8_rq + 14), a
    ld a, DMA_FILL
    ld (d8_rq + 15), a
    ld bc, (d8_rx)
    ld de, (d8_ry)
    call d8_offset
    call d8_set_dst
    ld hl, (d8_rw)
    ld (d8_rq + 6), hl
    ld hl, (d8_rh)
    ld (d8_rq + 8), hl
    ld hl, SCR_W
    ld (d8_rq + 10), hl
    ld (d8_rq + 12), hl
    jp d8_go

; Recorta el rectangulo de trabajo contra d8_clip. Carry = vacio.
; Deja en d8_skx / d8_sky lo que se ha quitado por la izquierda y arriba.
d8_clip_work:
    ld hl, 0
    ld (d8_skx), hl
    ld (d8_sky), hl
    ; ---- x
    ld hl, (d8_clip)            ; cx
    ld de, (d8_rx)
    or a
    sbc hl, de                  ; cx - rx
    jr c, @x_ok                 ; rx > cx
    jr z, @x_ok
    ld (d8_skx), hl             ; se quitan cx - rx
    ex de, hl                   ; DE = cx - rx
    ld hl, (d8_rw)
    or a
    sbc hl, de
    ret c                       ; todo a la izquierda
    jr z, @empty
    ld (d8_rw), hl
    ld hl, (d8_clip)
    ld (d8_rx), hl
@x_ok:
    ; derecha: rx + rw <= cx + cw
    ld hl, (d8_clip)
    ld de, (d8_clip + 4)
    add hl, de                  ; HL = cx2
    ld de, (d8_rx)
    or a
    sbc hl, de                  ; cx2 - rx
    jr c, @empty
    jr z, @empty
    ex de, hl                   ; DE = sitio que queda
    ld hl, (d8_rw)
    or a
    sbc hl, de
    jr c, @y
    ld (d8_rw), de              ; rw = cx2 - rx
@y:
    ld hl, (d8_clip + 2)        ; cy
    ld de, (d8_ry)
    or a
    sbc hl, de
    jr c, @y_ok
    jr z, @y_ok
    ld (d8_sky), hl
    ex de, hl
    ld hl, (d8_rh)
    or a
    sbc hl, de
    ret c
    jr z, @empty
    ld (d8_rh), hl
    ld hl, (d8_clip + 2)
    ld (d8_ry), hl
@y_ok:
    ld hl, (d8_clip + 2)
    ld de, (d8_clip + 6)
    add hl, de
    ld de, (d8_ry)
    or a
    sbc hl, de
    jr c, @empty
    jr z, @empty
    ex de, hl
    ld hl, (d8_rh)
    or a
    sbc hl, de
    jr c, @ok
    ld (d8_rh), de
@ok:
    ld hl, (d8_rw)
    ld a, h
    or l
    jr z, @empty
    ld hl, (d8_rh)
    ld a, h
    or l
    jr z, @empty
    or a                        ; NC: hay algo
    ret
@empty:
    scf
    ret

; DE -> {x, y, w, h}: al rectangulo de trabajo
d8_load_rect:
    ex de, hl
    ld de, d8_rx
    ld bc, 8
    ldir
    ret

; ---- metodos ----------------------------------------------------------------

d8_init:
    xor a
    ld (d8_dbl), a
    ld (d8_bgtr), a
    ld (d8_keyen), a
    ld (d8_bg), a
    ld a, 15
    ld (d8_fg), a
    ld a, (d8_front)
    ld (d8_base), a
    ld hl, 0
    ld (d8_clip), hl
    ld (d8_clip + 2), hl
    ld hl, SCR_W
    ld (d8_clip + 4), hl
    ld hl, SCR_H
    ld (d8_clip + 6), hl
    ld a, CRTC_MODE
    call __crtc_set_mode
    ld a, (d8_front)
    call d8_set_r19
    xor a
    ret

; A = byte alto de la pagina que se ve
d8_set_r19:
    push af
    ld a, CRTC_PAGE
    out (PORT_MMIO_PAGE), a
    ld a, 0x13
    out (CRTC_ADDR), a
    pop af
    out (CRTC_DATA), a
    ret

d8_get_mode_info:
    ld hl, d8_mode_info
    ret

d8_command:
    or a
    jr z, d8_init_state
    cp 0x01
    jr z, @dbl_on
    cp 0x02
    jr z, @dbl_off
    cp 0x10
    jr z, @fg
    cp 0x11
    jr z, @bg
    cp 0x12
    jr z, @bgtr
    cp 0x13
    jr z, @key
    cp 0x14
    jr z, @page
    ld a, 0xFF
    ret
@dbl_on:
    ld a, 1
    ld (d8_dbl), a
    ld a, (d8_back)
    ld (d8_base), a
    xor a
    ret
@dbl_off:
    xor a
    ld (d8_dbl), a
    ld a, (d8_front)
    ld (d8_base), a
    xor a
    ret
@fg:
    ld a, e
    ld (d8_fg), a
    xor a
    ret
@bg:
    ld a, e
    ld (d8_bg), a
    xor a
    ret
@bgtr:
    ld a, e
    ld (d8_bgtr), a
    xor a
    ret
@key:
    ld a, e
    ld (d8_key), a
    ld a, d
    ld (d8_keyen), a
    xor a
    ret
@page:
    ld a, e
    ld (d8_front), a
    ld (d8_base), a
    inc a
    ld (d8_back), a
    ld a, e
    call d8_set_r19
    xor a
    ret
d8_init_state:
    xor a
    ld (d8_bgtr), a
    ld (d8_keyen), a
    ret

; A = color: toda la pagina de dibujo
d8_clear:
    ld b, a
    ld a, (d8_base)
d8_clear_page:                  ; A = pagina, B = color
    ld (d8_rq + 5), a
    ld a, b
    ld (d8_rq + 14), a
    ld a, DMA_FILL
    ld (d8_rq + 15), a
    ld hl, 0
    ld (d8_rq + 3), hl
    ld (d8_rq + 8), hl          ; una linea
    ld hl, 64000
    ld (d8_rq + 6), hl
    jp d8_go

d8_clear_backbuf:
    ld b, a
    ld a, (d8_back)
    jr d8_clear_page

; A = lineas: la pagina sube; abajo queda el color de fondo
d8_scroll_up:
    or a
    ret z
    cp SCR_H
    jr c, @part
    ld a, (d8_bg)
    jr d8_clear
@part:
    ld e, a
    ld d, 0
    ld bc, 0
    call d8_offset              ; HL = n * 320
    push hl
    ld (d8_rq + 0), hl          ; origen: base + n * 320
    ld a, (d8_base)
    ld (d8_rq + 2), a
    ld hl, 0
    call d8_set_dst
    pop de
    ld hl, 64000
    or a
    sbc hl, de                  ; (200 - n) * 320
    push hl
    ld (d8_rq + 6), hl
    ld hl, 0
    ld (d8_rq + 8), hl
    xor a
    ld (d8_rq + 15), a
    call d8_go
    pop hl                      ; donde empieza lo que queda abajo
    call d8_set_dst
    ex de, hl
    ld hl, 64000
    or a
    sbc hl, de
    ld (d8_rq + 6), hl
    ld a, (d8_bg)
    ld (d8_rq + 14), a
    ld a, DMA_FILL
    ld (d8_rq + 15), a
    jp d8_go

; A = lineas: la pagina baja (de abajo arriba, pasos de -320)
d8_scroll_down:
    or a
    ret z
    cp SCR_H
    jr c, @part
    ld a, (d8_bg)
    jp d8_clear
@part:
    push af
    ld c, a
    ld a, SCR_H - 1
    sub c
    ld e, a
    ld d, 0
    ld bc, 0
    call d8_offset              ; origen: linea 199 - n
    ld (d8_rq + 0), hl
    ld a, (d8_base)
    ld (d8_rq + 2), a
    ld hl, (SCR_H - 1) * SCR_W
    call d8_set_dst
    ld hl, SCR_W
    ld (d8_rq + 6), hl
    pop af
    push af
    ld c, a
    ld a, SCR_H
    sub c
    ld l, a
    ld h, 0
    ld (d8_rq + 8), hl          ; 200 - n lineas
    ld hl, -SCR_W
    ld (d8_rq + 10), hl
    ld (d8_rq + 12), hl
    xor a
    ld (d8_rq + 15), a
    call d8_go
    pop af                      ; arriba, n lineas de fondo
    ld e, a
    ld d, 0
    ld bc, 0
    call d8_offset
    ld (d8_rq + 6), hl
    ld hl, 0
    ld (d8_rq + 8), hl
    call d8_set_dst
    ld a, (d8_bg)
    ld (d8_rq + 14), a
    ld a, DMA_FILL
    ld (d8_rq + 15), a
    jp d8_go

d8_set_clip_rect:
    ex de, hl
    ld de, d8_clip
    ld bc, 8
    ldir
    ret

d8_get_clip_rect:
    ld hl, d8_clip
    ld bc, 8
    ldir
    ret

; BC = x, DE = y -> A:HL fisica
d8_get_addr:
    call d8_offset
    ld a, (d8_base)
    ret

d8_put_pixel_fast:
    ld (d8_color), a
    call d8_offset
d8_put_at:                      ; HL = desplazamiento, (d8_color)
    call d8_set_dst
    ld hl, 1
    ld (d8_rq + 6), hl
    dec hl
    ld (d8_rq + 8), hl
    ld a, (d8_color)
    ld (d8_rq + 14), a
    ld a, DMA_FILL
    ld (d8_rq + 15), a
    jp d8_go

; Con recorte: A = 0 dibujado, 1 recortado
d8_put_pixel:
    ld (d8_color), a
    ld (d8_rx), bc
    ld (d8_ry), de
    ld hl, 1
    ld (d8_rw), hl
    ld (d8_rh), hl
    push bc
    push de
    call d8_clip_work
    pop de
    pop bc
    ld a, 1
    ret c
    call d8_offset
    call d8_put_at
    xor a
    ret

d8_get_pixel:
    call d8_offset
    ld (d8_rq + 0), hl
    ld a, (d8_base)
    ld (d8_rq + 2), a
    ld hl, d8_pix               ; la ventana 3 es el banco 3 de la BIOS: C00000 + direccion
    ld (d8_rq + 3), hl
    ld a, 0xC0
    ld (d8_rq + 5), a
    ld hl, 1
    ld (d8_rq + 6), hl
    dec hl
    ld (d8_rq + 8), hl
    xor a
    ld (d8_rq + 15), a
    call d8_go
    ld a, (d8_pix)
    ret

; BC = x, DE = y, HL = longitud, A = color
d8_draw_hline:
    ld (d8_rw), hl
    ld hl, 1
    ld (d8_rh), hl
    jr d8_line_rect
d8_draw_vline:
    ld (d8_rh), hl
    ld hl, 1
    ld (d8_rw), hl
d8_line_rect:
    ld (d8_rx), bc
    ld (d8_ry), de
    ld (d8_color), a
    call d8_clip_work
    ret c
    ld a, (d8_color)
    jp d8_fill_work

; DE -> {x, y, w, h}, A = color
d8_fill_rect:
    ld (d8_color), a
    call d8_load_rect
    call d8_clip_work
    ret c
    ld a, (d8_color)
    jp d8_fill_work

; DE -> {x, y, w, h}, A = color: el marco
d8_draw_rect:
    ld (d8_color), a
    ex de, hl
    ld de, d8_tmp
    ld bc, 8
    ldir
    ld bc, (d8_tmp)             ; arriba
    ld de, (d8_tmp + 2)
    ld hl, (d8_tmp + 4)
    ld a, (d8_color)
    call d8_draw_hline
    ld bc, (d8_tmp)             ; abajo: y + h - 1
    ld hl, (d8_tmp + 2)
    ld de, (d8_tmp + 6)
    add hl, de
    dec hl
    ex de, hl
    ld hl, (d8_tmp + 4)
    ld a, (d8_color)
    call d8_draw_hline
    ld bc, (d8_tmp)             ; izquierda
    ld de, (d8_tmp + 2)
    ld hl, (d8_tmp + 6)
    ld a, (d8_color)
    call d8_draw_vline
    ld hl, (d8_tmp)             ; derecha: x + w - 1
    ld de, (d8_tmp + 4)
    add hl, de
    dec hl
    ld b, h
    ld c, l
    ld de, (d8_tmp + 2)
    ld hl, (d8_tmp + 6)
    ld a, (d8_color)
    jp d8_draw_vline

; DE -> {x1, y1, x2, y2}, A = color: Bresenham con put_pixel (con recorte)
; d8_tmp: +0 x, +2 y, +4 x2, +6 y2, +8 dx, +10 -dy; d8_err: error (put_pixel usa d8_rx)
d8_draw_line:
    ld (d8_color), a
    ex de, hl
    ld de, d8_tmp
    ld bc, 8
    ldir
    ; dx = |x2 - x1|, sx
    ld hl, (d8_tmp + 4)
    ld de, (d8_tmp)
    or a
    sbc hl, de
    ld a, 1
    jp p, @dxp
    ex de, hl
    ld hl, 0
    or a
    sbc hl, de
    ld a, -1
@dxp:
    ld (d8_tmp + 8), hl
    ld (@sx + 1), a
    ; dy = -|y2 - y1|, sy
    ld hl, (d8_tmp + 6)
    ld de, (d8_tmp + 2)
    or a
    sbc hl, de
    ld a, 1
    jp p, @dyp
    ex de, hl
    ld hl, 0
    or a
    sbc hl, de
    ld a, -1
@dyp:
    ex de, hl
    ld hl, 0
    or a
    sbc hl, de
    ld (d8_tmp + 10), hl        ; -dy
    ld (@sy + 1), a
    ld de, (d8_tmp + 8)
    add hl, de
    ld (d8_err), hl              ; err = dx - dy
@loop:
    ld bc, (d8_tmp)
    ld de, (d8_tmp + 2)
    ld a, (d8_color)
    call d8_put_pixel
    ; fin?
    ld hl, (d8_tmp)
    ld de, (d8_tmp + 4)
    or a
    sbc hl, de
    jr nz, @step
    ld hl, (d8_tmp + 2)
    ld de, (d8_tmp + 6)
    or a
    sbc hl, de
    ret z
@step:
    ld hl, (d8_err)
    add hl, hl                  ; e2 = 2 * err
    push hl
    ld de, (d8_tmp + 10)        ; -dy
    or a
    sbc hl, de                  ; e2 - (-dy) = e2 + dy
    jp m, @nox                  ; e2 < -dy: no avanza x
    ld hl, (d8_err)
    add hl, de
    ld (d8_err), hl
    ld hl, (d8_tmp)
@sx:
    ld de, 1                    ; (se modifica: +1 / -1)
    ld a, e
    ld e, a
    ld d, 0
    bit 7, a
    jr z, @sx1
    dec d
@sx1:
    add hl, de
    ld (d8_tmp), hl
@nox:
    pop hl                      ; e2
    ld de, (d8_tmp + 8)         ; dx
    or a
    sbc hl, de                  ; e2 - dx
    jr z, @ystep                ; e2 == dx: avanza y
    jp p, @loop                 ; e2 > dx: no avanza y
@ystep:
    ld hl, (d8_err)
    add hl, de
    ld (d8_err), hl
    ld hl, (d8_tmp + 2)
@sy:
    ld de, 1
    ld a, e
    ld e, a
    ld d, 0
    bit 7, a
    jr z, @sy1
    dec d
@sy1:
    add hl, de
    ld (d8_tmp + 2), hl
    jp @loop

; HL = 8 bytes del caracter, DE = desplazamiento en la pagina de dibujo
d8_draw_char_at_addr:
    push de
    call d8_build_glyph
    pop hl
    jr d8_blit_glyph

; HL = fuente, A = codigo, BC = x, DE = y
d8_draw_char:
    push bc
    push de
    sub 0x20                    ; la fuente de la BIOS empieza en el espacio
    jr nc, @cok
    xor a
@cok:
    ld e, a
    ld d, 0
    ex de, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, de                  ; fuente + codigo * 8
    call d8_build_glyph
    pop de
    pop bc
    ; fuera de la pantalla: nada (sin recorte fino)
    ld hl, SCR_W - 8
    or a
    sbc hl, bc
    ret c
    ld hl, SCR_H - 8
    or a
    sbc hl, de
    ret c
    call d8_offset
d8_blit_glyph:                  ; HL = desplazamiento del destino
    call d8_set_dst
    ld hl, d8_glyph
    ld (d8_rq + 0), hl
    ld a, 0xC0
    ld (d8_rq + 2), a
    ld hl, 8
    ld (d8_rq + 6), hl
    ld (d8_rq + 8), hl
    ld (d8_rq + 10), hl
    ld hl, SCR_W
    ld (d8_rq + 12), hl
    ld a, (d8_bgtr)
    or a
    ld a, DMA_COPY
    jr z, @mode
    ld a, (d8_fg)               ; fondo transparente: el fondo es fg + 1, la clave
    inc a
    ld (d8_rq + 14), a
    ld a, DMA_KEY
@mode:
    ld (d8_rq + 15), a
    jp d8_go

; HL = 8 bytes de un caracter -> d8_glyph (64 bytes de tinta o fondo)
d8_build_glyph:
    ld de, d8_glyph
    ld a, (d8_bgtr)
    or a
    ld a, (d8_bg)
    jr z, @bgok
    ld a, (d8_fg)
    inc a
@bgok:
    ld (@bgv + 1), a
    ld a, (d8_fg)
    ld (@fgv + 1), a
    ld c, 8
@row:
    ld a, (hl)
    inc hl
    push hl
    ld h, a
    ld b, 8
@bit:
    sla h
@fgv:
    ld a, 0
    jr c, @put
@bgv:
    ld a, 0
@put:
    ld (de), a
    inc de
    djnz @bit
    pop hl
    dec c
    jr nz, @row
    ret

; HL = pixeles (memoria de la CPU), DE -> {x, y, w, h}
d8_draw_bitmap:
    push hl
    call d8_load_rect
    ld hl, (d8_rw)
    ld (d8_tmp), hl             ; ancho original (paso del origen)
    call d8_clip_work
    pop hl
    ret c
    call __dma_phys             ; DEHL = fisica del origen
    ; + sky * ancho + skx
    push de
    push hl
    ld hl, 0
    ld de, (d8_sky)
    ld a, d
    or e
    jr z, @nomul
    ld bc, (d8_tmp)
@mul:
    add hl, bc
    dec de
    ld a, d
    or e
    jr nz, @mul
@nomul:
    ld bc, (d8_skx)
    add hl, bc
    ex de, hl                   ; DE = salto
    pop hl
    pop bc                      ; BC = parte alta (C)
    add hl, de
    jr nc, @nc
    inc c
@nc:
    ld (d8_rq + 0), hl
    ld a, c
    ld (d8_rq + 2), a
    ld bc, (d8_rx)
    ld de, (d8_ry)
    call d8_offset
    call d8_set_dst
    ld hl, (d8_rw)
    ld (d8_rq + 6), hl
    ld hl, (d8_rh)
    ld (d8_rq + 8), hl
    ld hl, (d8_tmp)
    ld (d8_rq + 10), hl
    ld hl, SCR_W
    ld (d8_rq + 12), hl
    ld a, (d8_keyen)
    or a
    ld a, DMA_COPY
    jr z, @bm
    ld a, (d8_key)
    ld (d8_rq + 14), a
    ld a, DMA_KEY
@bm:
    ld (d8_rq + 15), a
    jp d8_go

; DE -> {sx, sy, dx, dy, w, h}
d8_copy_rect:
    ex de, hl
    ld de, d8_tmp
    ld bc, 12
    ldir
    ld hl, (d8_tmp + 4)
    ld (d8_rx), hl
    ld hl, (d8_tmp + 6)
    ld (d8_ry), hl
    ld hl, (d8_tmp + 8)
    ld (d8_rw), hl
    ld hl, (d8_tmp + 10)
    ld (d8_rh), hl
    call d8_clip_work           ; el destino manda
    ret c
    ; origen + lo recortado
    ld hl, (d8_tmp)
    ld de, (d8_skx)
    add hl, de
    ld b, h
    ld c, l
    ld hl, (d8_tmp + 2)
    ld de, (d8_sky)
    add hl, de
    ex de, hl
    ; si el destino esta mas abajo, de abajo arriba (pasos negativos)
    ld hl, (d8_ry)
    or a
    sbc hl, de                  ; dy - sy
    jr z, @down_no
    jr c, @down_no
    ld hl, (d8_rh)
    dec hl
    add hl, de
    ex de, hl                   ; ultima linea del origen
    call d8_offset
    ld (d8_rq + 0), hl
    ld bc, (d8_rx)
    ld hl, (d8_ry)
    ld de, (d8_rh)
    add hl, de
    dec hl
    ex de, hl
    call d8_offset
    call d8_set_dst
    ld hl, -SCR_W
    jr @common
@down_no:
    call d8_offset
    ld (d8_rq + 0), hl
    ld bc, (d8_rx)
    ld de, (d8_ry)
    call d8_offset
    call d8_set_dst
    ld hl, SCR_W
@common:
    ld (d8_rq + 10), hl
    ld (d8_rq + 12), hl
    ld a, (d8_base)
    ld (d8_rq + 2), a
    ld hl, (d8_rw)
    ld (d8_rq + 6), hl
    ld hl, (d8_rh)
    ld (d8_rq + 8), hl
    xor a
    ld (d8_rq + 15), a
    jp d8_go

d8_swap_buffers:
    ld a, (d8_dbl)
    or a
    ret z
    ld a, (d8_front)
    ld b, a
    ld a, (d8_back)
    ld (d8_front), a
    ld a, b
    ld (d8_back), a
    ld (d8_base), a
    ld a, (d8_front)
    jp d8_set_r19

d8_get_backbuf:
    ld hl, 0
    ld a, (d8_back)
    ret
