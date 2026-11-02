; =============================================================================
; SND_MS2.ASM - Sonido con la Magic Sound 2 del Aleste LX (pagina MMIO 7)
; Shaeon (Carlos Palmero). Registros: doc/aleste-lx.md.
;
; Las rutinas de un canal desactivan las interrupciones mientras escriben
; sus registros, para que una rutina de interrupcion (un reproductor de
; musica) no se mezcle con ellas.
; =============================================================================

module snd_ms2

defc PORT_MMIO_PAGE = 0xF1
defc MS2_PAGE       = 7
defc MS2_CTRL       = 0x00
defc MS2_VOL_L      = 0x01
defc MS2_VOL_R      = 0x02
defc MS2_STATUS     = 0x03
defc MS2_IRQ_CTRL   = 0x04
defc MS2_IRQ_STAT   = 0x05
defc MS2_TIMER_LO   = 0x10
defc MS2_TIMER_HI   = 0x11
defc MS2_CH0        = 0x20
defc MS2_IRQ_LINE   = 3

EXTERN __int_set_handler, __int_enable, __int_disable

SECTION DRV_CODE

PUBLIC __snd_ms2_vtable
__snd_ms2_vtable:
    jp ms2_detect
    jp ms2_install
    jp ms2_get_info
    jp ms2_command
    jp ms2_uninstall
    jp ms2_play
    jp ms2_stop
    jp ms2_set_volume
    jp ms2_set_step
    jp ms2_master
    jp ms2_status
    jp ms2_set_timer

; ---- detect: VOL_L se lee como se escribe
ms2_detect:
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (MS2_VOL_L)
    ld c, a
    ld a, 0x3C
    out (MS2_VOL_L), a
    in a, (MS2_VOL_L)
    ld b, a
    ld a, c
    out (MS2_VOL_L), a
    ld a, b
    cp 0x3C
    ld a, 1
    ret z
    xor a
    ret

ms2_install:
    call ms2_uninstall
    ld hl, 0
    ld (user_handler), hl
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    ld a, 0xFF
    out (MS2_VOL_L), a
    out (MS2_VOL_R), a
    ld a, 0x0F
    out (MS2_STATUS), a         ; borra los fines de muestra
    ld a, 0x03
    out (MS2_IRQ_STAT), a
    ld a, 1
    out (MS2_CTRL), a           ; en marcha
    xor a
    ret

; ---- todo parado: los cuatro canales y el temporizador
ms2_uninstall:
    di
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    xor a
    out (MS2_TIMER_LO), a
    out (MS2_TIMER_HI), a
    out (MS2_IRQ_CTRL), a
    out (MS2_CH0 + 0x00), a
    out (MS2_CH0 + 0x10), a
    out (MS2_CH0 + 0x20), a
    out (MS2_CH0 + 0x30), a
    ei
    ret

ms2_get_info:
    ld hl, info
    ret

ms2_command:
    ld hl, 0
    ret

; Cierra las interrupciones guardando como estaban (P/V = IFF2):
;   call irq_off ... call irq_on   (irq_on las abre solo si estaban abiertas)
irq_off:
    push af
    ld a, i
    di
    ld a, 0
    jp po, io_was_off
    inc a
io_was_off:
    ld (irq_was_on), a
    pop af
    ret
irq_on:
    push af
    ld a, (irq_was_on)
    or a
    jr z, io_keep
    ei
io_keep:
    pop af
    ret

; A = canal -> C = puerto base del canal (20h + canal * 10h)
ch_base:
    and 0x03
    rlca
    rlca
    rlca
    rlca
    add a, MS2_CH0
    ld c, a
    ret

; ---- HL = voz
ms2_play:
    ld a, (hl)                  ; canal
    inc hl
    call ch_base
    ld b, (hl)                  ; control
    inc hl
    call irq_off
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    xor a
    out (c), a                  ; parado: al ponerlo en marcha empieza en START
    push bc
    inc c                       ; +1: inicio, fin, bucle, volumenes y paso
    ld b, 14
pl_loop:
    ld a, (hl)
    out (c), a
    inc hl
    inc c
    djnz pl_loop
    pop bc
    ld a, b
    and 0x0E
    or 0x01                     ; suena
    out (c), a
    call irq_on
    ret

; ---- A = canal
ms2_stop:
    call ch_base
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    xor a
    out (c), a
    ret

; ---- A = canal, D = izquierdo, E = derecho
ms2_set_volume:
    call ch_base
    ld a, c
    add a, 0x0A
    ld c, a
    call irq_off
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    out (c), d
    inc c
    out (c), e
    call irq_on
    ret

; ---- A = canal, E:HL = paso
ms2_set_step:
    call ch_base
    ld a, c
    add a, 0x0C
    ld c, a
    call irq_off
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    out (c), l
    inc c
    out (c), h
    inc c
    out (c), e                  ; el byte alto aplica el valor
    call irq_on
    ret

; ---- D = izquierdo, E = derecho
ms2_master:
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    ld a, d
    out (MS2_VOL_L), a
    ld a, e
    out (MS2_VOL_R), a
    ret

ms2_status:
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (MS2_STATUS)
    ret

; ---- HL = periodo en muestras, DE = rutina (0 = parar)
ms2_set_timer:
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    xor a
    out (MS2_TIMER_LO), a       ; parado mientras se cambia
    out (MS2_TIMER_HI), a
    ld (user_handler), de
    ld a, d
    or e
    jr z, tm_stop
    push hl
    ld a, MS2_IRQ_LINE
    ld hl, ms2_isr
    call __int_set_handler
    ld a, MS2_IRQ_LINE
    call __int_enable
    pop hl
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    ld a, 0x03
    out (MS2_IRQ_STAT), a
    ld a, 0x02                  ; IRQ del temporizador
    out (MS2_IRQ_CTRL), a
    ld a, l
    out (MS2_TIMER_LO), a
    ld a, h
    out (MS2_TIMER_HI), a       ; el byte alto lo pone en marcha
    ret
tm_stop:
    xor a
    out (MS2_IRQ_CTRL), a
    ld a, MS2_IRQ_LINE
    jp __int_disable

; ---- rutina del PIC (linea 3): borra y llama a la del usuario
ms2_isr:
    ld a, MS2_PAGE
    out (PORT_MMIO_PAGE), a
    in a, (MS2_IRQ_STAT)
    out (MS2_IRQ_STAT), a
    and 0x02
    ret z
    ld hl, (user_handler)
    ld a, h
    or l
    ret z
    jp (hl)

SECTION DRV_DATA

info:
    dw info_name
    db 1, 0
    dw 0x0007                   ; IRQ, estatico, DMA
    db MS2_IRQ_LINE, 0
info_name:
    db "SND Magic Sound 2", 0

user_handler: dw 0
irq_was_on:   db 0
