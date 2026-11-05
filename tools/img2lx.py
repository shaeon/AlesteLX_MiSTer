#!/usr/bin/env python3
# img2lx.py - Imagen (PNG, JPG...) -> .LXI para el modo 320x200x256 del Aleste LX
# Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.
#
#   python3 img2lx.py foto.jpg FOTO.LXI [--fill] [--no-dither] [--colors N]
#
# Ajusta la imagen a 320x200 (por defecto entera, con bandas; --fill la
# recorta para llenar la pantalla; el pixel del LX es mas alto que ancho, como
# el de 320x200 en un monitor 4:3, y se tiene en cuenta), la reduce a N
# colores (256) con median cut, redondea la paleta a 12 bits (0RGB, como la del
# LX) y vuelve a cuantizar contra esa paleta real con tramado Floyd-Steinberg.
# El color 0 es el mas oscuro (con el se borran las bandas).
#
# Formato .LXI: "LXI1", ancho y alto (16 bits), numero de colores (16 bits),
# la paleta (2 bytes por color: 0RGB de 12 bits, byte bajo primero) y los
# pixeles (un byte cada uno, linea a linea). Byte bajo primero en todo.
import argparse, struct
from PIL import Image

W, H = 320, 200
PIXEL_ASPECT = (4 / 3) / (W / H)          # 1,2: el pixel es mas alto que ancho

ap = argparse.ArgumentParser()
ap.add_argument('src'); ap.add_argument('dst')
ap.add_argument('--fill', action='store_true', help='recortar para llenar la pantalla')
ap.add_argument('--no-dither', action='store_true')
ap.add_argument('--colors', type=int, default=256)
a = ap.parse_args()

im = Image.open(a.src).convert('RGB')
# tamano en "pixeles del LX": el ancho se mide en pixeles cuadrados / 1,2
sw, sh = im.size
src_aspect = sw / sh
scr_aspect = (W / H) * PIXEL_ASPECT                     # 4:3
if (src_aspect > scr_aspect) != a.fill:
    w = W; h = round(W * PIXEL_ASPECT / src_aspect)
else:
    h = H; w = round(H * src_aspect / PIXEL_ASPECT)
im = im.resize((w, h), Image.LANCZOS)
if a.fill:                                               # recorte centrado
    x0, y0 = (w - W) // 2, (h - H) // 2
    im = im.crop((x0, y0, x0 + W, y0 + H)); w, h = W, H
w, h = min(w, W), min(h, H)
im = im.crop((0, 0, w, h))

dither = Image.Dither.NONE if a.no_dither else Image.Dither.FLOYDSTEINBERG
q = im.quantize(colors=a.colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
pal = q.getpalette()[:a.colors * 3]
n = len(pal) // 3
# paleta de 12 bits y nueva cuantizacion contra ella, con tramado
pal12 = []
flat = []
for i in range(n):
    r, g, b = (round(pal[i * 3 + k] / 17) for k in range(3))
    pal12.append((r << 8) | (g << 4) | b)
    flat += [r * 17, g * 17, b * 17]
# el color 0 sera el mas oscuro: con el se borran las bandas si la imagen
# no llena la pantalla
order = sorted(range(n), key=lambda i: 0.299 * flat[i*3] + 0.587 * flat[i*3+1] + 0.114 * flat[i*3+2])
pal12 = [pal12[i] for i in order]
flat = [v for i in order for v in flat[i*3:i*3+3]]
pimg = Image.new('P', (1, 1))
pimg.putpalette(flat + [0] * (768 - len(flat)))
q = im.quantize(palette=pimg, dither=dither)
pixels = q.tobytes()

out = b'LXI1' + struct.pack('<HHH', w, h, n)
out += b''.join(struct.pack('<H', c) for c in pal12)
out += pixels
open(a.dst, 'wb').write(out)
print(f"{a.dst}: {w}x{h}, {n} colours, {len(out)} bytes")
