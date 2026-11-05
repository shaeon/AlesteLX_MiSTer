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

### Modo compatible Aleste 520EX

Si `boot.rom` lleva AL512.BIN (la ROM del 520EX, MAME `al520ex`, CRC32
e8c2a9a1) detrás de LX.ROM, el cargador la deja en 400000, donde la busca el
modo legacy. La orden `520EX` del monitor hace lo mismo que el arranque del
core del 520EX: apaga los periféricos LX, pone `OUT (0F0h),A` en FFFEh y salta
allí con A = 0; la MMU pasa a modo legacy y la CPU da la vuelta a 0000h, en la
ROM del 520EX, como tras un reset (AlesteDOS, MSX-DOS, software del CPC). El
reset del OSD vuelve al LX.

    copy /b LX.ROM + AL512.BIN boot.rom

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

**Sonido** (`drivers/snd`, `snd.h`): la Magic Sound 2. `snd_play(&voz)`
programa un canal (inicio, fin, vuelta del bucle, volúmenes izquierdo y
derecho, paso y 8/16 bits) y lo hace sonar desde el principio;
`snd_stop(canal)`, `snd_set_volume(canal, izq, der)`, `snd_set_step(canal,
paso)` (cambia el tono al vuelo), `snd_master(izq, der)`, `snd_status()` y
`snd_set_timer(periodo, rutina)`, el temporizador de la MS2 en muestras de
48 kHz (960 = 50 Hz, el ritmo de los MOD) por la línea 3. Ayudas:
`snd_voice_set` (inicio, longitud y bucle como en un MOD), `snd_step_rate(hz)`
y `snd_step_period(periodo)` (periodo de Amiga PAL → paso). Las rutinas de un
canal guardan y restauran el estado de las interrupciones, así que se pueden
llamar desde una rutina de interrupción (un reproductor).

**Disquetera** (`drivers/fdc`, `fdc.h`): uPD765 sin DMA (los bytes se
recogen sondeando RQM/EXM). `fdc_read(unidad, pista, cara, sector, bufer)` y
`fdc_read_lba(unidad, lba, bufer)` para discos de 720 KB (80 pistas, 2 caras,
9 sectores de 512 bytes); recalibra la primera vez y solo busca si cambia de
pista. `fdc_read_multi` lee varios sectores seguidos de una pista con una
sola orden, sin perder vueltas entre ellos.

**Ficheros** (`fat.h`, `src/fat.c`): discos MSX-DOS (FAT12), directorio raíz,
solo lectura. `fat_mount(unidad)`, `fat_dir(rutina)`, `fat_find(nombre,
&entrada)`, `fat_load(&entrada, direccion_fisica, progreso)` y `fat_free_kb()`.
`fat_load` junta los clústeres seguidos y lee hasta una pista entera de una
vez en un búfer de pista (la ventana 2 pasa un momento del vídeo, banco 10h,
al banco 11h, C44000); la DMA lo lleva luego a su sitio.

**MOD** (`mod.h`, `src/mod.c`): reproductor de MOD de ProTracker de 4
canales (M.K., M!K!, 4CHN, FLT4) y de STM de Scream Tracker 2 (como las
canciones del reproductor MAG de la MagicSound del 520EX) que suena en segundo plano desde la
interrupción del temporizador de la MS2; las muestras se tocan directamente de
la memoria donde está el MOD y cada fila del patrón se lee por DMA.
`mod_load(direccion_fisica)`, `mod_play()`, `mod_stop()`, y `mod_title`,
`mod_position`, `mod_length`, `mod_row`, `mod_patterns`. Efectos: 0 arpegio,
1/2 portamento, 3 portamento hacia la nota, 4 vibrato, 5 y 6, 9
desplazamiento de muestra, A volumen, B salto de posición, C volumen, D salto
de patrón, F velocidad/tempo, E1/E2, EA/EB y EC. Sin afinación fina; muestras
de hasta 64 KB. Canales 0 y 3 a la izquierda, 1 y 2 a la derecha. Los STM
tienen los mismos patrones (64 filas x 4 canales x 4 bytes): cada fila se
traduce al formato del MOD (la nota con la C2SPD del instrumento pasa a
periodo de Amiga; efectos A velocidad, B, C, D, E, F, G, H y J) y la columna
de volumen se aplica aparte; `mod_kind()` dice cuál es.

**Consola** (`console.h`, `src/console.c`): texto de 80x25 sobre el modo 640x200 con
el scroll y el borrado por la DMA; `con_putc`, `con_puts`, `con_putu`,
`con_puthex`, `con_gotoxy`, una ventana de scroll (`con_set_window`), y
`con_getc`/`con_gets` con cursor y una rutina que se llama mientras espera
(`con_set_idle`).

Los textos del monitor (órdenes, ayuda y mensajes) están en inglés.

`main.c` instala todo, da un pitido por la Magic Sound 2 y arranca un monitor
con las órdenes HELP, CLS, TIME, BEEP, DIR (ficheros del disco de la unidad
A), LOAD fichero [dir] (lo carga en memoria física), MOD [fichero|dir] (carga
y toca un MOD o STM del disco, o el que se cargó con "Load MOD" en el OSD, en
000000), PLAY/STOP (`src/tune.c`: el Himno de
la alegría a cuatro canales, con melodía, bajo, arpegio y charles, secuenciado
por el temporizador de la MS2), DUMP (memoria física por la DMA), KEYS
(la matriz del teclado) y DEMO (un bloque que rebota con el blitter
sincronizado con el VBlank). La primera línea lleva el tiempo desde el
arranque.

### Modo 320×200 con 256 colores (8 bpp lineal)

El CRTC extendido ya lo tiene: R18 = 03h (8 bpp), R19 = byte alto de la
VRAM, R20 = 07h (dirección lineal, paso de 4 bytes dos veces por carácter: 8
bytes), R21 = 02h (8 bytes por carácter), R12/R13 = inicio, con R1 = 40,
R6 = 25 y R9 = 7 como el modo de texto. Un byte por píxel, 64 000 bytes; la
paleta da 256 colores de 4096. `lx/dos/test/gfx/gfx8test.asm`
(GFX8TEST.COM) lo prueba con la VRAM en C50000: en simulación, la imagen del
core es idéntica píxel a píxel a la del emulador alestelx.

640×200 con 256 colores necesita 16 bytes por carácter (R21 = 03h), pero el
contador de direcciones lineales avanza como mucho 8 (paso de 4, dos veces
por carácter): hace falta ampliarlo.

## LX-DOS

Sistema de disco propio del LX, compatible con los programas de CP/M 2.2 y
MSX-DOS 1. La ROM, al arrancar (o con la orden `BOOT` del monitor), busca
`LXDOS.SYS` en la unidad A; si está, lo carga en el slot 3, bancos 20h-21h
(C80000), y `__boot_jump` (`bios/boot.asm`, en la ventana 3) pone los bancos
20h-22h en las ventanas 0-2 y salta a 0000h. Sin disco de sistema queda el
monitor. `sd/LXDOS.DSK` es un disco de arranque con `HELLO.COM` de prueba.

`LXDOS.SYS` (`lx/dos`) se compila aparte y usa los drivers de la ROM por sus
direcciones fijas: `lx/build.sh` saca del mapa de la ROM sus símbolos
públicos residentes (ventana 3) a `lx/build/bios_abi.asm`. Las dos cosas se
compilan juntas.

Mapas de memoria (slot 3):

| | Ventanas 0-2 | Ventana 3 |
|---|---|---|
| ROM (monitor) | bancos 0-2 | drivers (banco 3) |
| LX-DOS | bancos 20h-22h (pila en C000h) | drivers |
| programa .COM | bancos 24h-26h (física C90000) | drivers |

La ventana 3 es la única común, así que allí están las puertas
(`bios/dosgate.asm`): `__dos_exec` (pone el mapa del programa y salta a
0100h), `__dos_bdos_gate` (`CALL 5`), `__dos_bios_gate` (tabla del BIOS de
CP/M), `__dos_isr_gate` (interrupciones con el programa en marcha) y
`__dos_wboot_gate` (fin del programa). El LX-DOS ve la memoria del programa
con la DMA (física = C90000 + dirección).

Página cero del programa: 0000h `JP BF06h` (WBOOT), 0005h `JP BF00h` (BDOS),
0038h a la puerta de interrupciones, FCB en 005Ch y 006Ch, línea de órdenes
en 0080h. La TPA llega a BF00h: `JP __dos_bdos_gate` en BF00h, la tabla del
BIOS de CP/M en BF03h y sus entradas (`LD A,n / JP __dos_bios_gate`) en
BF40h.

Funciones: consola (1, 2, 6, 7, 8, 9, 10, 11), versión (12, CP/M 2.2),
unidades (13, 14, 24, 25, 37), DMA (26), usuario (32) y ficheros por FCB:
abrir (15), cerrar (16), buscar (17, 18, con `?`), borrar (19), leer y
escribir secuencial (20, 21) y aleatorio (33, 34, 40), crear (22),
renombrar (23), tamaño (35) y registro aleatorio (36). El estado del fichero
abierto va en los bytes 16-31 del FCB, en los sitios de MSX-DOS 1 (16-19
tamaño, 25 entrada del directorio, 26-27 primer clúster). BIOS de CP/M:
CONST, CONIN, CONOUT y WBOOT.

Funciones de MSX-DOS 1 (además de las de CP/M): 07h y 08h (entrada sin eco,
como en MSX-DOS; no las de IOBYTE de CP/M), 03h-05h (auxiliar e impresora:
nada), 1Bh (asignación: A sectores por clúster, BC 512, DE clústeres, HL
libres), 26h y 27h (bloques: tamaño de registro en los bytes 14-15 del FCB,
registro aleatorio de 4 bytes en 33-36, HL registros; HL = 0 en 26h fija el
tamaño), 28h (= 40), 2Ah-2Dh (fecha y hora, del reloj MC146818), 2Eh
(verificación) y 2Fh/30h (sectores absolutos: DE sector, H cuántos, L unidad).
Las que devuelven varios registros dejan A, BC, DE y HL en `__dos_ret_*` y la
puerta los carga al volver (`__dos_xret`).

Disco: `fat.c` con `FAT_WRITE` (solo en el LX-DOS) escribe. Un sector en
caché agrupa las escrituras de 128 bytes; la FAT está en memoria y
`fat_sync` (al cerrar, al borrar o renombrar y al acabar un programa) la
escribe en sus dos copias. El driver `fdc` escribe con la orden WRITE DATA
del 765 (`fdc_write_multi`).

Música: el LX-DOS lleva el reproductor de MOD y STM (`src/mod.c`) y dos
funciones propias del BDOS, en números que CP/M y MSX-DOS no usan: `A0h`
(DE = nombre ASCIIZ: lo carga en la física 100000h y lo toca de fondo; DE = 0
la para; A = 0 bien, 1 no está, 2 error de disco, 3 formato, 4 demasiado
grande) y `A1h` (DE = 32 bytes: sonando, posición, posiciones, patrones,
fila, tipo y título). `MODPLAY.COM` (`lx/dos/test/modplay.asm`) las usa:
`MODPLAY fichero` toca y vuelve al DOS con la música sonando, `MODPLAY /S`
la para y `MODPLAY` solo dice qué suena. La música sigue mientras se
ejecutan otros programas (la interrupción del temporizador de la MS2 pasa
por la puerta de interrupciones al mapa del LX-DOS). LXDOS.SYS ocupa ahora
los bancos 20h-22h (hasta 44 KB; la pila va arriba de la ventana 2).

Consola de los programas: además de los controles de CP/M, las secuencias de
escape de la BIOS del MSX (VT52) que usan los programas de MSX-DOS: `ESC Y`
fila columna, `ESC A/B/C/D`, `ESC H`, `ESC E`/`ESC j`, `ESC J`, `ESC K`,
`ESC l`, 0Bh, 0Ch y 1Ch-1Fh; `ESC b/c/x/y` y su parámetro se ignoran. Las
filas cuentan desde la primera de la ventana del LX-DOS (debajo del
título).

Teclado: de EE. UU. o español, según la opción Keyboard del OSD al arrancar;
`KEYB US` / `KEYB ES` lo cambia (en el LX-DOS y en el monitor). El español
lleva AltGr (`@ # | \ [ ] { } ~`), la tecla `< >` y ñ, ç, º, ª, ¡, ¿ en
Windows-1252, como la fuente; sin teclas muertas.

Órdenes del LX-DOS: `A:`, `B:`, `DIR`, `TYPE`, `COPY origen destino`
(destino puede ser `B:`), `DEL` (con comodines), `REN`, `CLS`, `VER`,
`MONITOR`, `HELP` y `nombre [argumentos]` para ejecutar `NOMBRE.COM`. Al
arrancar ejecuta `AUTOEXEC.BAT` si lo hay.

## Mapa de E/S nativo

Puerto `F1h` = página MMIO (se puede leer); los puertos `00h-7Fh` acceden a
FF0000 + página × 128 + puerto. Las direcciones de DMA son físicas (24 bits): C00000-C0FFFF es la imagen de la
BIOS, C40000 la memoria de vídeo del modo 16k1b.

| Página | Dirección | Dispositivo | Fichero |
|---|---|---|---|
| 0 | FF0000-FF001F | PIC | rtl/core/lx/lx_sys.sv |
| 0 | FF0040-FF005F | Temporizador del sistema | rtl/core/lx/lx_sys.sv |
| 0 | FF0060-FF0061 | Reloj MC146818 (índice, dato) | rtl/core/cpc/rtc146818.sv |
| 2 | FF0100-FF011F | Paleta | (vídeo del LX) |
| 2 | FF0120-FF013F | CRTC | (vídeo del LX) |
| 6 | FF0300-FF037F | DMA / blitter | rtl/core/lx/lx_dma.sv |
| 7 | FF0380-FF03FF | Magic Sound 2 | rtl/core/lx/lx_ms2.sv |
| 8 | FF0400-FF047F | Teclado | rtl/core/lx/lx_input.sv |
| 9 | FF0480-FF04FF | Disquetera (uPD765) | rtl/core/cpc/u765.sv |
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

### Disquetera (página 9)

El mismo uPD765 del modo legacy (puertos FB7E/FB7F y FA7E del CPC), con las
imágenes que se montan en el OSD (Mount Drive A:/B:; las de 720 KB de
MSX-DOS del 520EX, o DSK/EDSK del CPC). Su interrupción va a la línea 0.

| Puerto | | |
|---|---|---|
| 00 | R | registro de estado principal (RQM, DIO, EXM, CB) |
| 01 | RW | datos |
| 02 | W | motor (D0) |

### Reloj (página 0, 60h-61h)

El mismo MC146818 del 520EX (el que se pone en hora con la de MiSTer y se
guarda en ALESTE.CMO), por índice y dato como en un PC: 60h índice (0-63),
61h dato. Registros 0 segundos, 2 minutos, 4 horas, 6 día de la semana
(1 = domingo), 7 día, 8 mes, 9 año (en BCD 00-99 = 2000-2099; en binario,
años desde 1980) y 0Bh (bit 2 = binario). Usa la puerta de la RAM del reloj
que también usa la copia de ALESTE.CMO, que tiene preferencia.

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

Copia y relleno de rectángulos, byte a byte. Tras cada byte suelta el bus
un ciclo, para que la Magic Sound 2 (que comparte con ella el segundo
maestro) no se quede sin muestras durante una copia larga.

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

### Reloj (página 0, 60h-61h)

El mismo MC146818 del 520EX (el que se pone en hora con la de MiSTer y se
guarda en ALESTE.CMO), por índice y dato como en un PC: 60h índice (0-63),
61h dato. Registros 0 segundos, 2 minutos, 4 horas, 6 día de la semana
(1 = domingo), 7 día, 8 mes, 9 año (en BCD 00-99 = 2000-2099; en binario,
años desde 1980) y 0Bh (bit 2 = binario). Usa la puerta de la RAM del reloj
que también usa la copia de ALESTE.CMO, que tiene preferencia.

### Teclado (página 8)

| Puerto | | |
|---|---|---|
| 00 | R | bit 0 hay eventos, bit 1 la cola se llenó (se borra al leer) |
| 01 | R | del evento más antiguo: bit 0 pulsada, bit 1 extendida (E0) |
| 02 | R | código PS/2 (juego 2) del evento más antiguo; leerlo lo saca de la cola |
| 03 | RW | bit 0 interrupción con eventos (línea 7) |
| 04 | R | bit 0 teclado español elegido en el OSD (Keyboard) |
| 10-1A | R | filas 0-10 de la matriz del 520EX/CPC, activo a 0 (la 9 con el joystick) |

## Pruebas

`sim/tb_lx.sv` (`make ROM=...` en `sim/`) carga la ROM, traza E/S y bus, mide
el audio de la MS2, enseña memoria (`+peek=HEX +peekn=N`), teclea
(`+type=help|`, `_` es el espacio), monta un disco (`+dsk=imagen`; el disco va 3
veces más deprisa que el real salvo con `-DFDC_REAL`), guarda el audio de la MS2 (`+pcm=fichero`, estéreo de 16 bits
a 48 kHz) y vuelca un cuadro. ROMs de prueba en `lx/test/` (pasmo):

| ROM | Resultado en simulación |
|---|---|
| MSXTEST (funciones de MSX-DOS 1) | fecha y hora puestas y leídas, día de la semana, asignación, bloques de 300 × 1 byte con fin de fichero, sector absoluto |
| MODPLAY LXDEMO.MOD | carga y toca el MOD de fondo y vuelve al DOS; MODPLAY sin nada dice qué suena |
| ZEXDOC y ZEXALL (`lx/dos/test/zex`, en `sd/LXDOS.DSK`) | arrancan en el LX-DOS (cabecera y primera prueba); completos, en la placa |
| M80 y L80 (de `alestedos-dev.dsk` del 520EX) con `lx/dos/test/TEST.MAC` | `m80 =test`, `l80 test,test/n/e` y `test`: ensambla, enlaza y el TEST.COM nuevo se ejecuta |
| MSXTEST (`lx/dos/test/msxtest.asm`) | fecha y hora del reloj, 1Bh, bloques 26h/27h (escribe 300, lee 500: fin de fichero y 300 leídos, datos iguales) y sector absoluto 2Fh correctos |
| LX-DOS (`sd/LXDOS.DSK`) | arranca; HELLO (consola, BIOS, argumentos) y FILETEST (crear, escribir, cerrar, abrir, leer, renombrar, buscar y borrar) correctos; el disco queda coherente (`+dsk_out=`) |
| BIOS LX | consola, pitido, órdenes tecleadas; PLAY: melodía E4-E4-F4-G4 y bajo C3/G2 en la salida de la MS2 (`+pcm=fichero` guarda el audio) |
| pictest | 59 interrupciones del temporizador en 60 ms, 4 VBlank |
| ms2test | onda cuadrada a 187,5 Hz, ±4064, 7 fines de muestra y 11 ticks de 300 Hz en 40 ms |
| DIR y MOD SLL1.STM con `mag-player.dsk` (`+dsk=`) | lista los 10 ficheros; carga SLL1.STM (82 KB, 169 sectores) y la toca |
| MOD (`lx/test/LXDEMO.MOD`, de `tools/make_test_mod.py`) | `+mod=` lo carga como el OSD; MOD toca la melodía (E4, F4) y el bajo (C3), con la posición y la fila en la línea de estado |
| dmatest | relleno 8x3, copia 4x2 y copia con transparente correctos, 4 IRQ |

## Pendiente

- Afinación fina de las muestras en el reproductor de MOD y los efectos que faltan
  (E3-E9, EE, 7).
- Teclado español (ahora la tabla es la de EE. UU.).
- IPC (FF0020): en MiSTer el "MCU" podría ser el ARM por hps_io.
- Acelerador gráfico con conversión de formatos de píxel (el blitter cubre
  la copia de rectángulos).
