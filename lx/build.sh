#!/bin/sh
# lx/build.sh - Compila la BIOS del Aleste LX (LX.ROM) y el LX-DOS (LXDOS.SYS,
# LXDOS.DSK) con el Makefile del submodulo aleste-xi-bios de hww, donde viven
# los dos desde noviembre de 2026, y deja los resultados en lx/build/.
#
#   sh lx/build.sh          ->  lx/build/LX.ROM, bios_abi.asm, LXDOS.SYS, LXDOS.DSK
#   sh lx/build.sh --sd     ->  ademas, sd/LX.ROM y sd/LXDOS.DSK
#
# Necesita z88dk (zcc en el PATH, o Z88DK_PATH=...); el disco, python3. Sin
# instalar z88dk, con Docker (el disco se monta despues, fuera, con --sd):
#   docker run --rm -v "$PWD":/src -w /src/lx z88dk/z88dk sh build.sh
#
# LX.ROM es la ROM de arranque del core: en la SD, games/AlesteLX/boot.rom.
set -e
cd "$(dirname "$0")"
BIOS=aleste-xi-bios
[ -f "$BIOS/Makefile" ] || { echo "falta el submodulo: git submodule update --init"; exit 1; }

MAKE_ARGS=""
[ -n "$Z88DK_PATH" ] && MAKE_ARGS="Z88DK_PATH=$Z88DK_PATH"
if command -v zcc > /dev/null 2>&1 || [ -n "$Z88DK_PATH" ]; then
    # shellcheck disable=SC2086
    make -C "$BIOS" $MAKE_ARGS rom dos
else
    echo "sin z88dk: uso lo ya compilado en $BIOS/output"
fi
if command -v python3 > /dev/null 2>&1; then
    # shellcheck disable=SC2086
    make -C "$BIOS" $MAKE_ARGS disk
else
    echo "sin python3: no se monta LXDOS.DSK"
fi

mkdir -p build
for f in LX.ROM bios_abi.asm LXDOS.SYS LXDOS.DSK; do
    [ -f "$BIOS/output/$f" ] && cp "$BIOS/output/$f" build/ && echo "lx/build/$f"
done
if [ "$1" = "--sd" ]; then
    cp build/LX.ROM ../sd/LX.ROM && echo "sd/LX.ROM"
    [ -f build/LXDOS.DSK ] && cp build/LXDOS.DSK ../sd/LXDOS.DSK && echo "sd/LXDOS.DSK"
fi
