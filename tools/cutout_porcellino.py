#!/usr/bin/env python3
"""Ritaglia i 5 fotogrammi del porcellino: assets/porcellino/original.png -> assets/porcellino/frame1.png ... frame5.png

Tutti i fotogrammi escono con lo stesso formato, appoggiati sulla stessa linea di terra e centrati
sul corpo (non sulle zampe, che si muovono). Le parti staccate dal corpo (i segnini di movimento
vicino all'orecchio) vengono tolte.
"""
from collections import deque
import numpy as np
from PIL import Image

SRC = "assets/porcellino/original.png"
BG_MIN = 246          # sopra questo (canale minimo) un pixel è sfondo bianco
MIN_PART = 0.02       # le parti staccate più piccole di così (rispetto alla più grande) vengono scartate
PAD = 4

src = Image.open(SRC).convert("RGB")
rgb = np.asarray(src).astype(np.float32)
H, W, _ = rgb.shape
minc = rgb.min(axis=2)

cols = (minc < 240).any(axis=0)
groups, start = [], None
for x, v in enumerate(cols):
    if v and start is None:
        start = x
    if not v and start is not None:
        groups.append((start, x - 1))
        start = None
if start is not None:
    groups.append((start, W - 1))
assert len(groups) == 5, f"attesi 5 fotogrammi, trovati {len(groups)}: {groups}"


def flood(passable, seeds, four=True):
    h, w = passable.shape
    seen = np.zeros((h, w), dtype=bool)
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
            if 0 <= ny < h and 0 <= nx < w and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def dilate(mask, n):
    out = mask.copy()
    for _ in range(n):
        p = np.pad(out, 1)
        out = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return out


frames = []
for i, (gx0, gx1) in enumerate(groups):
    x0 = max(gx0 - 8, 0)
    x1 = min(gx1 + 8, W - 1)
    block = rgb[:, x0:x1 + 1, :]
    bmin = minc[:, x0:x1 + 1]
    h, w = bmin.shape

    # Sfondo = bianco raggiungibile dal bordo.
    cand = bmin >= BG_MIN
    border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] \
           + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    bg = flood(cand, border)
    fg = ~bg

    # Tieni il corpo e le parti attaccate; scarta le macchioline staccate (segnini di movimento).
    # Connessione a 8 vicini, senza "unire" parti vicine: i segnini di movimento stanno a pochi pixel
    # dall'orecchio e vanno trattati come staccati.
    near = fg
    labeled = np.zeros((h, w), dtype=np.int32)
    sizes = []
    label = 0
    for y0, x0_ in zip(*np.where(near)):
        if labeled[y0, x0_]:
            continue
        label += 1
        comp = flood(near & (labeled == 0), [(y0, x0_)], four=False)
        labeled[comp] = label
        sizes.append((label, int((comp & fg).sum())))
    biggest = max(sizes, key=lambda t: t[1])
    keep_labels = {lab for lab, n in sizes if n >= MIN_PART * biggest[1]}
    dropped = [n for lab, n in sizes if lab not in keep_labels]
    fg &= np.isin(labeled, list(keep_labels))

    # Alpha: pieno dentro, morbido sul bordo; sul bordo tolgo il bianco "mescolato" (matte bianco).
    edge = fg & dilate(~fg, 2)
    soft = np.clip((255 - bmin) / 90.0, 0.0, 1.0)
    alpha = np.where(edge, soft, fg.astype(np.float32))
    a = np.maximum(alpha, 1e-3)[..., None]
    color = np.where(edge[..., None], (block - 255.0 * (1 - a)) / a, block)
    color = np.clip(color, 0, 255)

    ys, xs = np.where(fg)
    top, bottom = ys.min(), ys.max()
    # Centro sul corpo: baricentro dei pixel della metà alta (le zampe sono in basso).
    upper = ys < top + 0.6 * (bottom - top)
    cx = xs[upper].mean()

    rgba = np.dstack([color, alpha * 255]).astype(np.uint8)
    frames.append(dict(rgba=rgba, cx=cx, ground=bottom,
                       up=bottom - top, down=0, left=cx - xs.min(), right=xs.max() - cx))
    print(f"fotogramma {i + 1}: alto={bottom - top + 1}  sx={cx - xs.min():.0f} dx={xs.max() - cx:.0f}  "
          f"parti staccate scartate: {dropped if dropped else 'nessuna'}")

up = int(max(f["up"] for f in frames)) + PAD
half = int(np.ceil(max(max(f["left"], f["right"]) for f in frames))) + PAD
down = PAD + 2
CW, CH = 2 * half, up + down + 1
print(f"formato comune: {CW}x{CH}  (appoggio a riga {up}, a {(down + 1) / CH:.3f} dal fondo)")

for i, f in enumerate(frames, 1):
    canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    img = Image.fromarray(f["rgba"], "RGBA")
    canvas.paste(img, (int(round(half - f["cx"])), int(up - f["ground"])), img)
    canvas.save(f"assets/porcellino/frame{i}.png")
print("Scritti assets/porcellino/frame1.png ... frame5.png")
