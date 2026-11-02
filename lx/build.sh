#!/bin/sh
# lx/build.sh - Compila la BIOS del Aleste LX (submodulo aleste-xi-bios de hww,
# sin tocar) con los parches de lx/patches (arreglos a ficheros de hww) y
# lx/overlay (codigo nuestro: drivers nuevos y main.c, que se copian encima),
# y monta lx/build/LX.ROM (64 KB).
#
# Necesita z88dk (zcc en el PATH). Sin instalarlo, con Docker:
#   docker run --rm -v "$PWD":/src -w /src/lx z88dk/z88dk sh build.sh
#
# LX.ROM es la ROM de arranque del core: en la SD, games/AlesteLX/boot.rom.
set -e
cd "$(dirname "$0")"
rm -rf build/src
mkdir -p build
cp -r aleste-xi-bios build/src
rm -rf build/src/.git build/src/build build/src/output
for p in patches/*.patch; do
    echo "== $p"
    (cd build/src && patch -p1 -s < "../../$p")
done
cp -r overlay/. build/src/
cd build/src
mkdir -p build
zcc +z80 -vn -O3 --no-crt -m -Iinclude -I. -s -clib=sdcc_iy -o build/aleste \
    asm/sections.asm asm/crt0_aleste.asm fonts/font_win1252.asm \
    bios/errors.asm bios/undefined_method.asm \
    drivers/mmu/mmu.asm drivers/mmu/mmu_mem.asm drivers/crtc/crtc.asm \
    drivers/palette/palette.asm drivers/palette/palette_12b.asm \
    drivers/vbuf/vbuf_16k1b.asm drivers/vbuf/vbuf.asm \
    drivers/audio/aduio_ay8910.asm drivers/audio/audio.asm \
    drivers/int/int.asm drivers/int/int_lx.asm \
    drivers/timer/timer.asm drivers/timer/timer_lx.asm \
    drivers/dma/dma.asm drivers/dma/dma_lx.asm \
    drivers/kbd/kbd.asm drivers/kbd/kbd_lx.asm \
    drivers/snd/snd.asm drivers/snd/snd_ms2.asm bios/irqsave.asm bios/boot.asm bios/dosgate.asm \
    drivers/fdc/fdc.asm drivers/fdc/fdc_765.asm \
    src/drivers/mmu.c src/drivers/mmu_mem.c src/drivers/crtc.c src/drivers/palette.c \
    src/drivers/vbuf.c src/drivers/audio.c \
    src/drivers/int.c src/drivers/timer.c src/drivers/dma.c src/drivers/kbd.c src/drivers/snd.c src/drivers/fdc.c \
    src/console.c src/tune.c src/mod.c src/fat.c main.c
# LX.ROM: 64 KB con cada seccion en su direccion (sin Python: vale en la
# imagen de Docker de z88dk)
head -c 65536 /dev/zero > build/LX.ROM
put() { dd if="build/aleste_$1.bin" of=build/LX.ROM bs=1 seek=$(($2)) conv=notrunc 2>/dev/null; }
put code_crt_start 0x0000
put code_compiler  0x0200
put DRV_CODE       0xC000
put FONT_DATA      0xE000
put DRV_DATA       0xF000
put DRV_VTABLE     0xFD00
[ "$(wc -c < build/LX.ROM)" -eq 65536 ] || { echo "LX.ROM no mide 64 KB: alguna seccion se sale"; exit 1; }
cp build/LX.ROM ../LX.ROM
echo "lx/build/LX.ROM"

# ---- ABI de la ROM: los simbolos publicos de la parte residente (ventana 3:
# drivers, sus VTables, datos y fuente), para los programas que se enlazan
# aparte (LXDOS.SYS). Cambian si cambia la ROM: se compilan juntos.
awk '$1 !~ /_(head|tail|size)$/ && $6 == "public," && ($9 == "DRV_CODE," || $9 == "DRV_DATA," || $9 == "DRV_VTABLE," || $9 == "FONT_DATA,") {
        a = substr($3, 2); print "PUBLIC " $1; print "defc " $1 " = 0x" a }' \
    build/aleste.map > ../bios_abi.asm
echo "lx/build/bios_abi.asm: $(grep -c '^PUBLIC' ../bios_abi.asm) simbolos"

# ---- LXDOS.SYS: el sistema que la ROM arranca del disco (lx/dos)
cd ../..
rm -rf build/dos
mkdir -p build/dos
cp dos/*.c dos/*.h dos/*.asm build/dos/
cd build/dos
zcc +z80 -vn -O3 --no-crt -m -I../src/include -I../src -s -clib=sdcc_iy -o lxdos \
    sections.asm crt0_dos.asm ../bios_abi.asm \
    ../src/src/drivers/int.c ../src/src/drivers/timer.c ../src/src/drivers/dma.c \
    ../src/src/drivers/kbd.c ../src/src/drivers/snd.c ../src/src/drivers/fdc.c \
    ../src/src/drivers/vbuf.c ../src/src/console.c ../src/src/fat.c bdos.c main.c
cat lxdos_code_crt_start.bin > LXDOS.SYS
head -c $((0x100 - $(wc -c < lxdos_code_crt_start.bin))) /dev/zero >> LXDOS.SYS
cat lxdos_code_compiler.bin >> LXDOS.SYS
[ "$(wc -c < LXDOS.SYS)" -le 32768 ] || { echo "LXDOS.SYS pasa de 32 KB"; exit 1; }
cp LXDOS.SYS ../LXDOS.SYS
echo "lx/build/LXDOS.SYS: $(wc -c < LXDOS.SYS) bytes"
