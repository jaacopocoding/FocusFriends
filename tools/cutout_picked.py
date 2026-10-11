#!/usr/bin/env python3
"""Ritaglia il disegno di un personaggio sollevato dalle mani.

    python3 tools/cutout_picked.py [originale.png [ritaglio.png [soglia_sfondo]]]

Senza argomenti: assets/porcellino/picked_original.png -> assets/porcellino/picked.png
(per Pianty: assets/pianty/picked_original.png assets/pianty/picked.png).

Sfondo = bianco raggiungibile dal bordo. Le macchioline staccate più piccole di MIN_PART pixel
(puntini di polvere) vengono tolte; gocce di sudore e lineette di tremore restano.
"""
from collections import deque
import numpy as np
from PIL import Image

import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "assets/porcellino/picked_original.png"
DST = sys.argv[2] if len(sys.argv) > 2 else "assets/porcellino/picked.png"
# Sopra questa soglia (canale minimo) un pixel è sfondo bianco. Se le maniche sono quasi bianche (Ciccio),
# serve alzarla (es. 252) o si "mangiano" le maniche.
BG_MIN = float(sys.argv[3]) if len(sys.argv) > 3 else 246
MIN_PART = 14
PAD = 4

src = Image.open(SRC).convert("RGB")
rgb = np.asarray(src).astype(np.float32)
h, w, _ = rgb.shape
minc = rgb.min(axis=2)


def flood(passable, seeds, four=True):
    hh, ww = passable.shape
    seen = np.zeros((hh, ww), dtype=bool)
    q = deque()
    for y, x in seeds:
        if passable[y, x] and not seen[y, x]:
            seen[y, x] = True
            q.append((y, x))
    steps = ((1, 0), (-1, 0), (0, 1), (0, -1)) if four else \
        ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
    while q:
        y, x = q.popleft()
        for dy, dx in steps:
            ny, nx = y + dy, x + dx
            if 0 <= ny < hh and 0 <= nx < ww and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def dilate(mask, n):
    out = mask.copy()
    for _ in range(n):
        p = np.pad(out, 1)
        out = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return out


cand = minc >= BG_MIN
border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] \
       + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
bg = flood(cand, border)
fg = ~bg

# Scarta le macchioline minuscole staccate.
labeled = np.zeros((h, w), dtype=bool)
dropped = 0
for y0, x0 in zip(*np.where(fg)):
    if labeled[y0, x0]:
        continue
    comp = flood(fg & ~labeled, [(y0, x0)], four=False)
    labeled |= comp
    if comp.sum() < MIN_PART:
        fg &= ~comp
        dropped += 1
print("macchioline tolte:", dropped)

edge = fg & dilate(~fg, 2)
soft = np.clip((255 - minc) / 90.0, 0.0, 1.0)
alpha = np.where(edge, soft, fg.astype(np.float32))
a = np.maximum(alpha, 1e-3)[..., None]
color = np.clip(np.where(edge[..., None], (rgb - 255.0 * (1 - a)) / a, rgb), 0, 255)

ys, xs = np.where(fg)
box = (max(xs.min() - PAD, 0), max(ys.min() - PAD, 0), min(xs.max() + PAD + 1, w), min(ys.max() + PAD + 1, h))
rgba = np.dstack([color, alpha * 255]).astype(np.uint8)
out = Image.fromarray(rgba, "RGBA").crop(box)
out.save(DST)
print("Scritto", DST, out.size, " (bbox nel foglio:", box, ")")
