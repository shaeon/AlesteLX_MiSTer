# Aleste LX para MiSTer

Core del **Aleste LX** para MiSTer: la máquina que diseñó Valery (hww) como
evolución del Aleste 520EX ([aleste-lx-fpga-sv](https://github.com/hww/aleste-lx-fpga-sv),
[aleste-xi-doc](https://github.com/hww/aleste-xi-doc)), terminada y llevada a MiSTer.

El proyecto de hww se quedó a medias: la parte compatible con el CPC/520EX
funcionaba, pero los periféricos nuevos no estaban integrados y su BIOS
([aleste-xi-bios](https://github.com/hww/aleste-xi-bios)) no arrancaba en
hardware. Este core añade:

- **PIC** de 16 líneas y **temporizador** del sistema.
- **Magic Sound 2**: 4 canales de muestras de 8/16 bits por DMA a 48 kHz,
  con volumen por canal, bucle e interrupciones.
- **DMA / blitter**: copia, relleno y copia con transparente de rectángulos.
- **Teclado** PS/2 con cola de eventos y lectura de la matriz del 520EX.
- La **BIOS LX** de hww arreglada y ampliada con drivers de interrupciones,
  temporizador, DMA, teclado y sonido, una consola de 80x25, un pequeño
  monitor y un **reproductor de MOD** de ProTracker.

El Aleste 520EX sigue siendo un core aparte:
[Aleste520EX_MiSTer](https://github.com/shaeon/Aleste520EX_MiSTer).

## Uso

Copia el `.rbf` a `_Computer/` y `sd/LX.ROM` como `games/AlesteLX/boot.rom`.
Al arrancar sale el monitor (`LX>`); `HELP` lista las órdenes. Para oír un
MOD de 4 canales: "Load MOD" en el OSD y la orden `MOD`.

## Organización

| Carpeta | |
|---|---|
| `AlesteLX.sv` | top de MiSTer (hps_io, OSD, vídeo, audio) |
| `rtl/core` | núcleo (`aleste_lx_core.sv`) y periféricos LX (`rtl/core/lx`) |
| `rtl/hww` | ficheros de aleste-lx-fpga-sv que usa el núcleo |
| `lx` | BIOS: aleste-xi-bios (submódulo, sin tocar), `patches/` (arreglos), `overlay/` (drivers nuevos y monitor), `build.sh` |
| `lx/test` | ROMs de prueba de PIC, MS2 y DMA |
| `sim` | simulación con Verilator (`make`) |
| `doc/aleste-lx.md` | hardware, registros y API de los drivers |

La BIOS se compila con z88dk: `sh lx/build.sh` (o con Docker:
`docker run --rm -v "$PWD":/src -w /src/lx z88dk/z88dk sh build.sh`).

## Créditos

- Aleste LX, aleste-xi-bios y diseño original: Valery (hww).
- Port, periféricos LX, drivers y MiSTer: Shaeon (Carlos Palmero).
- Marco de MiSTer: MiSTer-devel.

Licencia GPL v3 (ver `LICENSE`); los ficheros de hww mantienen la suya
(`rtl/hww/LICENSE`).
