; =============================================================================
; TIMER_LX.ASM - Temporizador del sistema del modo LX (pagina MMIO 0, 40h)
; Shaeon (Carlos Palmero). Registros: doc/10-modo-lx.md del core.
;
; get_ms y delay_ms usan el contador libre de milisegundos del hardware (no
; necesitan interrupciones). El periodico usa la linea 6 del PIC por el
; driver de interrupciones.
; =============================================================================

module timer_lx

defc PORT_MMIO_PAGE = 0xF1
defc TMR_PAGE       = 0
defc TMR_CTRL       = 0x40
defc TMR_RELOAD_LO  = 0x41
defc TMR_RELOAD_HI  = 0x42
defc TMR_TICKS_LO   = 0x45
defc TMR_TICKS_HI   = 0x46
defc TMR_IRQ_LINE   = 6

EXTERN __int_set_handler, __int_enable, __int_disable

SECTION DRV_CODE

PUBLIC __timer_lx_vtable
__timer_lx_vtable:
    jp timer_lx_detect
    jp timer_lx_install
    jp timer_lx_get_info
    jp timer_lx_command
    jp timer_lx_uninstall
    jp timer_lx_get_ms
    jp timer_lx_delay_ms
    jp timer_lx_set_periodic
    jp timer_lx_get_count

; ---- detect: el periodo (RELOAD_LO) se lee como se escribe
timer_lx_detect:
    ld a, TMR_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (TMR_RELOAD_LO)
    ld c, a
    ld a, 0xA5
    out (TMR_RELOAD_LO), a
    in a, (TMR_RELOAD_LO)
    ld b, a
    ld a, c
    out (TMR_RELOAD_LO), a
    ld a, b
    cp 0xA5
    ld a, 1
    ret z
    xor a
    ret

timer_lx_install:
    ld hl, 0
    ld (count), hl
    ld (user_handler), hl
    ld a, TMR_PAGE
    out (PORT_MMIO_PAGE), a
    xor a
    out (TMR_CTRL), a
    ret

timer_lx_uninstall:
    ld hl, 0
    ld de, 0
    jr timer_lx_set_periodic

timer_lx_get_info:
    ld hl, info
    ret

timer_lx_command:
    ld hl, 0
    ret

; ---- HL = milisegundos (leer el byte bajo congela el alto)
timer_lx_get_ms:
    ld a, TMR_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (TMR_TICKS_LO)
    ld l, a
    in a, (TMR_TICKS_HI)
    ld h, a
    ret

; ---- espera HL milisegundos
timer_lx_delay_ms:
    ex de, hl                   ; DE = espera
    call timer_lx_get_ms
    ld b, h
    ld c, l                     ; BC = inicio
dly_loop:
    push bc
    call timer_lx_get_ms
    pop bc
    or a
    sbc hl, bc                  ; HL = transcurrido
    or a
    sbc hl, de
    jr c, dly_loop
    ret

; ---- HL = periodo en us, DE = rutina (0 = parar)
timer_lx_set_periodic:
    push hl
    ld a, TMR_PAGE
    out (PORT_MMIO_PAGE), a
    xor a
    out (TMR_CTRL), a           ; parado mientras se cambia
    ld (user_handler), de
    ld a, d
    or e
    jr z, per_stop
    ld hl, 0
    ld (count), hl
    ld a, TMR_IRQ_LINE
    ld hl, timer_isr
    call __int_set_handler
    ld a, TMR_IRQ_LINE
    call __int_enable
    pop hl
    ld a, TMR_PAGE
    out (PORT_MMIO_PAGE), a
    ld a, l
    out (TMR_RELOAD_LO), a
    ld a, h
    out (TMR_RELOAD_HI), a
    ld a, 0x03                  ; marcha + periodico
    out (TMR_CTRL), a
    ret
per_stop:
    pop hl
    ld a, TMR_IRQ_LINE
    call __int_disable
    ret

timer_lx_get_count:
    ld hl, (count)
    ret

; ---- rutina del PIC: cuenta y llama a la del usuario
timer_isr:
    ld hl, (count)
    inc hl
    ld (count), hl
    ld hl, (user_handler)
    ld a, h
    or l
    ret z
    jp (hl)

SECTION DRV_DATA

info:
    dw info_name
    db 1, 0
    dw 0x0003
    db TMR_IRQ_LINE, 0
info_name:
    db "TIMER LX", 0

count:        dw 0
user_handler: dw 0
