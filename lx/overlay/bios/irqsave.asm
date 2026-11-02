; =============================================================================
; IRQSAVE.ASM - Cerrar y volver a abrir las interrupciones como estaban
; Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
;
;   call __irq_off ... call __irq_on
; __irq_on solo las abre si estaban abiertas al llamar a __irq_off (P/V de
; LD A,I = IFF2), asi que sirve tambien dentro de una rutina de interrupcion.
; Una sola variable basta: mientras estan cerradas no puede entrar otra.
; Conservan todos los registros.
; =============================================================================

module irqsave

SECTION DRV_CODE

PUBLIC __irq_off, __irq_on

__irq_off:
    push af
    ld a, i
    di
    ld a, 0
    jp po, was_off
    inc a
was_off:
    ld (irq_was_on), a
    pop af
    ret

__irq_on:
    push af
    ld a, (irq_was_on)
    or a
    jr z, keep_off
    ei
keep_off:
    pop af
    ret

SECTION DRV_DATA
irq_was_on: db 0
