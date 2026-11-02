#!/usr/bin/env python3
"""make_test_mod.py - Genera LXDEMO.MOD, un MOD de ProTracker (4 canales, M.K.)
para probar el reproductor de la BIOS LX. Todo es propio: muestras
sintetizadas y el Himno de la alegria (Beethoven, dominio publico).
Shaeon (Carlos Palmero), para el core AlesteLX_MiSTer.

    python3 tools/make_test_mod.py [salida.mod]

Efectos que usa: 0xy arpegio, 3xx portamento hacia la nota, Axy
deslizamiento de volumen, Cxx volumen, Dxx salto de patron, Fxx velocidad.
"""
import math, random, struct, sys

# ---- muestras (8 bits con signo)
def sq(n=32):   return [80] * (n // 2) + [-80] * (n // 2)
def sine(n=64): return [round(110 * math.sin(2 * math.pi * i / n)) for i in range(n)]
def saw(n=32):  return [round(-90 + 180 * i / n) for i in range(n)]
def kick(n=2400):
    out, ph = [], 0.0
    for i in range(n):
        f = 180 * (1 - i / n) ** 3 + 45            # Hz a 8287 muestras/s
        ph += 2 * math.pi * f / 8287
        out.append(round(120 * math.sin(ph) * (1 - i / n) ** 1.5))
    return out
def hat(n=700):
    random.seed(3)
    return [round(random.randint(-100, 100) * (1 - i / n) ** 3) for i in range(n)]

# (nombre, datos, volumen, inicio del bucle, longitud del bucle) en muestras
samples = [
    ("cuadrada",  sq(),   48, 0, 32),
    ("senoidal",  sine(), 64, 0, 64),
    ("sierra",    saw(),  30, 0, 32),
    ("bombo",     kick(), 64, 0, 0),
    ("charles",   hat(),  40, 0, 0),
]

# ---- periodos de ProTracker (afinacion 0): C-1 .. B-3
PER = [856,808,762,720,678,640,604,570,538,508,480,453,
       428,404,381,360,339,320,302,285,269,254,240,226,
       214,202,190,180,170,160,151,143,135,127,120,113]
def per(midi):                     # C-2 (428) = MIDI 60 con muestras de 32 por ciclo
    return PER[midi - 48]

E, F, G, D, C = 64, 65, 67, 62, 60
ph1 = [(E,2),(E,2),(F,2),(G,2),(G,2),(F,2),(E,2),(D,2),(C,2),(C,2),(D,2),(E,2),(E,3),(D,1),(D,4)]
ph2 = ph1[:12] + [(D,3),(C,1),(C,4)]
bars = ["C","G","C","G"]

def cell(sample=0, period=0, eff=0, par=0):
    return bytes([(sample & 0xF0) | (period >> 8), period & 0xFF,
                  ((sample & 0x0F) << 4) | eff, par])

def pattern(phrase, last_bars, first):
    rows = [[cell() for _ in range(4)] for _ in range(64)]
    r = 0
    for n, d in phrase:                     # corcheas -> 2 filas cada una
        rows[r][0] = cell(1, per(n), 0xC, 48)
        if d >= 3:                          # nota larga: se apaga poco a poco
            rows[r + 2][0] = cell(0, 0, 0xA, 0x02)
        r += d * 2
    for b, chord in enumerate(last_bars):   # bajo en negras, acorde, bateria
        for q in range(4):
            row = b * 16 + q * 4
            root = {"C": 60, "G": 55}[chord]       # bajo una octava abajo (64 por ciclo)
            rows[row][1] = cell(2, per(root), 0xC, 64 if q in (0, 2) else 44)
            if q == 0:
                rows[row][2] = cell(3, per({"C": 72, "G": 67}[chord]), 0x0, 0x47)
            else:
                rows[row][2] = cell(0, 0, 0x0, 0x47)
            rows[row][3] = cell(4 if q in (0, 2) else 5, per(60))
            rows[row + 2][3] = cell(5, per(60), 0xC, 24)
    if first:
        rows[0][3] = cell(4, per(60), 0xF, 6)       # velocidad 6 (125 BPM)
    else:
        # final: portamento del bajo hacia C y salto al principio del patron 0
        rows[56][1] = cell(2, per(60), 0xC, 64)
        rows[60][1] = cell(0, per(55), 0x3, 0x08)
        rows[63][0] = cell(0, 0, 0xD, 0x00)
    return b"".join(b"".join(c) for c in rows)

pats = [pattern(ph1, bars, True), pattern(ph2, bars, False)]
order = [0, 1]

hdr = b"LX demo - Beethoven".ljust(20, b"\0")
for i in range(31):
    if i < len(samples):
        name, data, vol, ls, ll = samples[i]
        hdr += name.encode().ljust(22, b"\0") + struct.pack(">HBBHH", len(data) // 2, 0, vol,
                                                         ls // 2, (ll // 2) if ll else 1)
    else:
        hdr += bytes(22) + struct.pack(">HBBHH", 0, 0, 0, 0, 1)
hdr += bytes([len(order), 127]) + bytes(order + [0] * (128 - len(order))) + b"M.K."
assert len(hdr) == 1084
body = b"".join(pats)
for _, data, *_ in samples:
    if len(data) % 2: data = data + [0]
    body += bytes((v & 0xFF) for v in data)

out = sys.argv[1] if len(sys.argv) > 1 else "LXDEMO.MOD"
open(out, "wb").write(hdr + body)
print(out, len(hdr + body), "bytes")
