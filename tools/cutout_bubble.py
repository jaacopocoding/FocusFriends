#!/usr/bin/env python3
"""Ritaglia il fumetto dalla carta: assets/bubble_original.png -> assets/bubble.png

Il contorno nero è un "muro": lo sfondo è tutto ciò che si raggiunge dal bordo dell'immagine
senza attraversarlo. Quello che resta (contorno + interno) è il fumetto.
"""
from collections import deque
import numpy as np
from PIL import Image, ImageFilter

src = Image.open("assets/bubble_original.png").convert("RGB")
rgb = np.asarray(src).astype(np.float32)
h, w, _ = rgb.shape
lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
wall = lum < 120

def flood(passable, seeds):
    seen = np.zeros((h, w), dtype=bool)
    q = deque()
    for y, x in seeds:
        if passable[y, x] and not seen[y, x]:
            seen[y, x] = True
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen

border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] \
       + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
background = flood(~wall, border)
shape = ~background

# Tieni solo il pezzo più grande (scarta macchie scure isolate nella carta).
best = None
labeled = np.zeros((h, w), dtype=bool)
for y in range(h):
    for x in range(w):
        if shape[y, x] and not labeled[y, x]:
            comp = flood(shape & ~labeled, [(y, x)])
            labeled |= comp
            if best is None or comp.sum() > best.sum():
                best = comp
shape = best

ys, xs = np.where(shape)
x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
print("bbox:", x0, y0, x1, y1)

alpha = Image.fromarray((shape * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
out = src.convert("RGBA")
out.putalpha(alpha)
pad = 4
box = (max(x0 - pad, 0), max(y0 - pad, 0), min(x1 + pad + 1, w), min(y1 + pad + 1, h))
out = out.crop(box)
out.save("assets/bubble.png")
W, H = out.size
print("Scritto assets/bubble.png", out.size)

# Geometria utile al disegno: dove finisce l'ovale (prima della codina) e dove sta la punta.
sh = shape[box[1]:box[3], box[0]:box[2]]
widths = sh.sum(axis=1)
body_rows = np.where(widths > 0.5 * widths.max())[0]
ellipse_bottom = body_rows.max() + 1
tip_row = np.where(widths > 0)[0].max()
tip_x = np.where(sh[tip_row])[0].mean()
print(f"larghezza={W} altezza={H}")
print(f"fondo ovale = {ellipse_bottom / H:.3f} dell'altezza")
print(f"punta codina x = {tip_x / W:.3f} della larghezza")
