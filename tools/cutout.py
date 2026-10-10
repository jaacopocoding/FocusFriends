#!/usr/bin/env python3
"""Ritaglia Spidy dallo sfondo bianco: assets/original.png -> assets/spidy.png"""
from collections import deque
import numpy as np
from PIL import Image, ImageFilter

src = Image.open("assets/original.png").convert("RGB")
rgb = np.asarray(src).astype(np.int16)
h, w, _ = rgb.shape

# Candidati sfondo: pixel chiari e poco saturati (bianco, grigio dell'ombra, filo di ragnatela).
mx, mn = rgb.max(axis=2), rgb.min(axis=2)
candidate = ((mx - mn) < 26) & (mx > 150)

# Sfondo vero = candidati collegati al bordo dell'immagine (così il bianco degli occhi resta).
background = np.zeros((h, w), dtype=bool)
queue = deque()
for x in range(w):
    for y in (0, h - 1):
        if candidate[y, x] and not background[y, x]:
            background[y, x] = True
            queue.append((y, x))
for y in range(h):
    for x in (0, w - 1):
        if candidate[y, x] and not background[y, x]:
            background[y, x] = True
            queue.append((y, x))
while queue:
    y, x = queue.popleft()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w and candidate[ny, nx] and not background[ny, nx]:
            background[ny, nx] = True
            queue.append((ny, nx))

foreground = ~background

# Tieni solo il blocco più grande (scarta eventuali residui isolati): bounding box dei pixel di figura
# calcolata sulle righe/colonne con abbastanza pixel.
cols = np.where(foreground.sum(axis=0) > 3)[0]
rows = np.where(foreground.sum(axis=1) > 3)[0]
x0, x1, y0, y1 = cols.min(), cols.max(), rows.min(), rows.max()
print("bbox:", x0, y0, x1, y1, "size:", x1 - x0 + 1, y1 - y0 + 1)

# Alpha morbido: erode di 1px per togliere l'alone bianco, poi sfuma leggermente il bordo.
alpha = Image.fromarray((foreground * 255).astype(np.uint8))
alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.9))

out = src.convert("RGBA")
out.putalpha(alpha)
pad = 6
out = out.crop((max(x0 - pad, 0), max(y0 - pad, 0), min(x1 + pad + 1, w), min(y1 + pad + 1, h)))
out.save("assets/spidy.png")
print("Scritto assets/spidy.png", out.size)
