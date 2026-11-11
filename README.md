# Aleste LX for MiSTer

MiSTer core of the **Aleste LX**, the machine designed by Valery (hww) as the
successor of the Aleste 520EX ([aleste-lx-fpga-sv](https://github.com/hww/aleste-lx-fpga-sv)),
completed: PIC and system timer, Magic Sound 2 (4 DMA sample channels at
48 kHz), DMA/blitter, PS/2 keyboard, and hww's
[aleste-xi-bios](https://github.com/hww/aleste-xi-bios) fixed and extended with
drivers, an 80x25 console and a small monitor.

Copy the `.rbf` to `_Computer/` and `sd/LX.ROM` to `games/AlesteLX/boot.rom`;
`sd/LXDOS.DSK` is the LX-DOS boot floppy.

The BIOS, LX-DOS and their tools live in hww's repository, which this core
uses as a submodule (`lx/aleste-xi-bios`). `sh lx/build.sh` builds them with
its Makefile (z88dk; python3 for the floppy) into `lx/build/`, and
`sh lx/build.sh --sd` also updates `sd/`.

Documentation (Spanish): [README_es.md](README_es.md), [doc/aleste-lx.md](doc/aleste-lx.md).

The Aleste 520EX is a separate core: [Aleste520EX_MiSTer](https://github.com/shaeon/Aleste520EX_MiSTer).
