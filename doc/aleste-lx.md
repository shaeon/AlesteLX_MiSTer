# Aleste LX: hardware y BIOS

El Aleste LX de hww (aleste-lx-fpga-sv) se quedó a medias: la parte compatible
(Z80, MMU, CRTC, paleta, SDRAM) funcionaba, pero el PIC, la DMA, la Magic
Sound 2 y el acelerador gráfico estaban sueltos, solo con pruebas unitarias, y
la BIOS (aleste-xi-bios) no llegaba a arrancar en hardware real. Este core lo
completa para MiSTer.

## Arranque

La CPU arranca en modo nativo en C00000 (slot 3, banco 0 tras el reset de la
MMU), donde el cargador deja LX.ROM (índice 0, 64 KB: C00000-C0FFFF). En la SD,
`games/AlesteLX/boot.rom` es LX.ROM y se carga sola; desde el OSD se puede
recargar (Developer → Reload LX ROM).

## La BIOS

`lx/aleste-xi-bios` es el repositorio de hww sin tocar. `lx/build.sh` hace una
copia, le aplica `lx/patches/` (arreglos a ficheros de hww) y copia encima
`lx/overlay/` (código nuestro: drivers nuevos y `main.c`).

Parches:

- `0001`: enlazado (las rutinas de la biblioteca quedaban en 0000h, encima del
  crt0, y DRV_DATA se salía de los 64 KB); puertos (CRTC en 20h/21h de la
  página MMIO 2, slot del supervisor en FAh); los drivers de CRTC y paleta
  eligen su página y conservan los registros; paso de parámetros de
  `vbuf_clear` y `vbuf_draw_char`; modo 16k1b (640x200, 1 bit, lineal, 80
  bytes por línea) con el vídeo en C40000.
- `0002`: el vector de IM 1 (0038h) salta al driver de interrupciones.

### Drivers nuevos

Siguen el esquema de hww: una VTable polimórfica en dirección fija (DRV_VTABLE,
FD00h en adelante) que `xxx_activate_lx()` rellena con la del driver
concreto, interfaz en registros para ensamblador y envoltorios en C
(`include/drivers/*.h`).

**Interrupciones** (`drivers/int`, `int.h`): `int_install()` pone IM 1 con
todo enmascarado; `int_set_handler(linea, rutina)`, `int_enable(linea)`,
`int_disable(linea)`. El despachador guarda los registros y la página MMIO
(puerto F1h, que se puede leer), borra las líneas que va a atender y llama a
la rutina de cada una. Las rutinas en C son funciones normales `void f(void)`.

**Temporizador** (`drivers/timer`, `timer.h`): `timer_get_ms()` y
`timer_delay_ms()` con el contador de milisegundos del hardware (sin
interrupciones); `timer_set_periodic(periodo_us, rutina)` por la línea 6.

**DMA** (`drivers/dma`, `dma.h`): `dma_start(&peticion)`, `dma_wait()`,
`dma_busy()`, y las ayudas `dma_copy`, `dma_fill` y `dma_rect` (rectángulos
con paso de línea, relleno y copia con transparente). `dma_phys(puntero)` da
la dirección física de una dirección de la CPU con el mapa actual de la MMU.

**Teclado** (`drivers/kbd`, `kbd.h`): la interrupción de la línea 7 vacía la
cola del hardware y traduce a ASCII (teclado de EE. UU.) con mayúsculas,
control y bloq mayús; `kbd_hit()`, `kbd_getc()`, `kbd_shift_state()` y
`kbd_row(fila)` para la matriz. Cursores, inicio/fin, páginas e insert dan
80h-88h, suprimir 7Fh y F1-F10 90h-99h.

**Consola** (`con.h`, `src/con.c`): texto de 80x25 sobre el modo 640x200 con
el scroll y el borrado por la DMA; `con_putc`, `con_puts`, `con_putu`,
`con_puthex`, `con_gotoxy`, una ventana de scroll (`con_set_window`), y
`con_getc`/`con_gets` con cursor y una rutina que se llama mientras espera
(`con_set_idle`).

`main.c` instala todo, da un pitido por la Magic Sound 2 y arranca un monitor
con las órdenes HELP, CLS, TIME, BEEP, DUMP (memoria física por la DMA), KEYS
(la matriz del teclado) y DEMO (un bloque que rebota con el blitter
sincronizado con el VBlank). La primera línea lleva el tiempo desde el
arranque.

## Mapa de E/S nativo

Puerto `F1h` = página MMIO (se puede leer); los puertos `00h-7Fh` acceden a
FF0000 + página × 128 + puerto. Las direcciones de DMA son físicas (24 bits): C00000-C0FFFF es la imagen de la
BIOS, C40000 la memoria de vídeo del modo 16k1b.

| Página | Dirección | Dispositivo | Fichero |
|---|---|---|---|
| 0 | FF0000-FF001F | PIC | rtl/core/lx/lx_sys.sv |
| 0 | FF0040-FF005F | Temporizador del sistema | rtl/core/lx/lx_sys.sv |
| 2 | FF0100-FF011F | Paleta | (vídeo del LX) |
| 2 | FF0120-FF013F | CRTC | (vídeo del LX) |
| 6 | FF0300-FF037F | DMA / blitter | rtl/core/lx/lx_dma.sv |
| 7 | FF0380-FF03FF | Magic Sound 2 | rtl/core/lx/lx_ms2.sv |
| 8 | FF0400-FF047F | Teclado | rtl/core/lx/lx_input.sv |
| 8 | FF0400-FF047F | Teclado | rtl/core/lx/lx_input.sv |

### PIC (página 0, 00-08)

Registros como en `wb_z80_pic.sv` de hww, en IM 1 (la CPU va a 0038h):

| Puerto | | |
|---|---|---|
| 00/01 | RW | máscara (1 = habilitada) |
| 02 | RW | vector base para IM 2 |
| 03/04 | R | pendientes y habilitadas |
| 05/06 | R | pendientes |
| 07/08 | W | 1 = borra el pendiente |

Las líneas se capturan por flanco de subida; INT se mantiene mientras haya
alguna pendiente y habilitada, así que el manejador tiene que borrarla.

| Línea | Fuente |
|---|---|
| 0 | STORAGE: disquetera |
| 1 | DMA_COM: fin de la DMA |
| 2 | GPU: VBlank del vídeo nativo |
| 3 | AUDIO: Magic Sound 2 |
| 4 | LEGACY: interrupción del Gate Array (300 Hz) |
| 6 | SYSTIMER: temporizador |
| 7 | INPUT: teclado |
| 7 | INPUT: hay eventos de teclado |

### Temporizador (página 0, 40-46)

| Puerto | | |
|---|---|---|
| 40 | RW | bit 0 marcha, bit 1 periódico |
| 41/42 | RW | periodo en µs (0 = 65536) |
| 43/44 | R | cuenta que queda (leer 43 congela 44) |
| 45/46 | R | contador libre de milisegundos |

### Magic Sound 2 (página 7)

Reescrita a partir de la de hww (allí el control pisaba los volúmenes, el paso
se salía del bloque del canal y el mezclador usaba el canal 0 para los cuatro).
Cuatro canales de muestras con signo (8 o 16 bits) leídas por DMA a 48 kHz.

| Puerto | | |
|---|---|---|
| 00 | RW | bit 0 habilita |
| 01/02 | RW | volumen global izquierdo / derecho |
| 03 | R | [3:0] fin de muestra, [7:4] sonando; W 1 = borra el fin |
| 04 | RW | bit 0 IRQ de fin de muestra, bit 1 IRQ del temporizador |
| 05 | R | bit 0 fin, bit 1 temporizador; W 1 = borra |
| 10/11 | RW | periodo del temporizador en muestras (160 = 300 Hz, 960 = 50 Hz) |
| 20-2F … 50-5F | | canales 0-3 |

Canal (+0 a +F): `+0` CTRL (bit 0 suena, 1 bucle, 2 16 bits, 3 IRQ al
terminar), `+1..+3` START, `+4..+6` END (no incluido), `+7..+9` LOOP,
`+A`/`+B` volumen izquierdo/derecho, `+C..+E` paso 8.16 (010000h = 48 kHz),
`+F` estado. El byte alto (+3, +6, +9, +E) aplica el valor.

### Teclado (página 8)

Cola de 16 eventos del teclado PS/2 (los que manda MiSTer) y lectura directa
de la matriz del 520EX/CPC para juegos.

| Puerto | | |
|---|---|---|
| 00 | R | bit 0 hay eventos, bit 1 se perdieron (se borra al leer) |
| 01 | R | del evento más antiguo: bit 0 pulsada, bit 1 extendida (E0) |
| 02 | R | código PS/2 (juego 2) del evento más antiguo; leerlo lo saca de la cola |
| 03 | RW | bit 0 interrupción mientras haya eventos (línea 7) |
| 10-1A | R | filas 0-10 de la matriz, activo a 0 (la 9 lleva el joystick) |

### DMA / blitter (página 6)

Copia y relleno de rectángulos, byte a byte.

| Puerto | | |
|---|---|---|
| 00 | W | bit 0 arranca, bits 2-1 modo (0 copia, 1 relleno, 2 copia con transparente), bit 3 IRQ al terminar; R bit 0 ocupado |
| 01 | R | bit 0 fin pendiente; W 1 = borra |
| 02-04 | | origen |
| 05-07 | | destino |
| 08/09 | | ancho en bytes |
| 0A/0B | | alto en líneas |
| 0C/0D | | paso de línea del origen (con signo) |
| 0E/0F | | paso de línea del destino |
| 10 | | byte de relleno o color transparente |

### Teclado (página 8)

| Puerto | | |
|---|---|---|
| 00 | R | bit 0 hay eventos, bit 1 la cola se llenó (se borra al leer) |
| 01 | R | del evento más antiguo: bit 0 pulsada, bit 1 extendida (E0) |
| 02 | R | código PS/2 (juego 2) del evento más antiguo; leerlo lo saca de la cola |
| 03 | RW | bit 0 interrupción con eventos (línea 7) |
| 10-1A | R | filas 0-10 de la matriz del 520EX/CPC, activo a 0 (la 9 con el joystick) |

## Pruebas

`sim/tb_lx.sv` (`make ROM=...` en `sim/`) carga la ROM, traza E/S y bus, mide
el audio de la MS2, enseña memoria (`+peek=HEX +peekn=N`), teclea
(`+type=help|`) y vuelca un cuadro. ROMs de prueba en `lx/test/` (pasmo):

| ROM | Resultado en simulación |
|---|---|
| BIOS LX | consola, pitido, órdenes tecleadas (HELP) |
| pictest | 59 interrupciones del temporizador en 60 ms, 4 VBlank |
| ms2test | onda cuadrada a 187,5 Hz, ±4064, 7 fines de muestra y 11 ticks de 300 Hz en 40 ms |
| dmatest | relleno 8x3, copia 4x2 y copia con transparente correctos, 4 IRQ |

## Pendiente

- Driver de la Magic Sound 2 y un reproductor de MOD.
- Teclado español (ahora la tabla es la de EE. UU.).
- IPC (FF0020): en MiSTer el "MCU" podría ser el ARM por hps_io.
- Acelerador gráfico con conversión de formatos de píxel (el blitter cubre
  la copia de rectángulos).
