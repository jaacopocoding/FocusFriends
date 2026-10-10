#!/usr/bin/env python3
"""Ritaglia i 5 stadi del bonsai: assets/bonsy/original.png -> assets/bonsy/stage1.png ... stage5.png

Tutti gli stadi escono con la stessa scala e lo stesso formato, allineati sulla linea di terra e
centrati sul vaso, così il vaso non "salta" quando si passa da uno stadio all'altro.
"""
from collections import deque
import numpy as np
from PIL import Image

SRC = "assets/bonsy/original.png"
BG_MIN = 246          # sopra questo (canale minimo) un pixel è sfondo bianco
PAD = 4
POT_HEIGHT = 58       # i pixel più in alto di così rispetto alla terra sono sopra il vaso

src = Image.open(SRC).convert("RGB")
rgb = np.asarray(src).astype(np.float32)
H, W, _ = rgb.shape
minc = rgb.min(axis=2)

# 1) Un gruppo di colonne per stadio.
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
assert len(groups) == 5, f"attesi 5 stadi, trovati {len(groups)}: {groups}"


def background_mask(block):
    """Sfondo = bianco raggiungibile dal bordo del blocco. Il bianco dentro il vaso resta."""
    h, w = block.shape
    cand = block >= BG_MIN
    seen = np.zeros((h, w), dtype=bool)
    q = deque()
    for y in range(h):
        for x in (0, w - 1):
            if cand[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for x in range(w):
        for y in (0, h - 1):
            if cand[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and cand[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def dilate(mask, n):
    out = mask.copy()
    for _ in range(n):
        p = np.pad(out, 1)
        out = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return out


stages = []
for i, (x0, x1) in enumerate(groups):
    x0 = max(x0 - 6, 0)
    x1 = min(x1 + 6, W - 1)
    block = rgb[:, x0:x1 + 1, :]
    bmin = block.min(axis=2)
    bg = background_mask(bmin)
    fg = ~bg

    # Linea di terra: la riga più "piena di scuro" nella parte bassa del disegno.
    ys = np.where(fg.any(axis=1))[0]
    top, bottom = ys.min(), ys.max()
    dark = (bmin < 150) & fg
    lower = np.arange(block.shape[0]) > top + 0.6 * (bottom - top)
    counts = np.where(lower, dark.sum(axis=1), 0)
    ground = int(counts.argmax())
    line_cols = np.where(dark[ground])[0]
    cx = (line_cols.min() + line_cols.max()) / 2.0

    # Sacche di bianco chiuse fra i rami e le foglie: sopra il bordo del vaso sono sfondo.
    # (Sotto, il bianco fa parte del vaso e resta.)
    pocket_limit = ground - POT_HEIGHT
    pure = (bmin >= BG_MIN) & fg
    seen = np.zeros_like(pure)
    for y0, x0_ in zip(*np.where(pure)):
        if seen[y0, x0_]:
            continue
        comp, q = [], deque([(y0, x0_)])
        seen[y0, x0_] = True
        while q:
            y, x = q.popleft()
            comp.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < pure.shape[0] and 0 <= nx < pure.shape[1] and pure[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        lowest = max(y for y, _ in comp)
        # Vuoti sopra il vaso (rami) e vuoti schiacciati sulla linea di terra (fra i piedini del vaso).
        if lowest < pocket_limit or lowest >= ground - 4:
            for y, x in comp:
                bg[y, x] = True
    fg = ~bg

    # Alpha: pieno dentro, morbido sul bordo; sul bordo tolgo il bianco "mescolato" (matte bianco).
    edge = fg & dilate(bg, 2)
    soft = np.clip((255 - bmin) / 90.0, 0.0, 1.0)
    alpha = np.where(edge, soft, fg.astype(np.float32))
    a = np.maximum(alpha, 1e-3)[..., None]
    color = np.where(edge[..., None], (block - 255.0 * (1 - a)) / a, block)
    color = np.clip(color, 0, 255)

    alpha[ground - 1:ground + 2, :] = 0     # via la linea di terra (3 righe)

    rgba = np.dstack([color, alpha * 255]).astype(np.uint8)
    # Estensione del disegno rispetto a (cx, ground)
    sub_fg = alpha > 0.02
    yy, xx = np.where(sub_fg)
    stages.append(dict(
        rgba=rgba, cx=cx, ground=ground,
        up=ground - yy.min(), down=yy.max() - ground,
        left=cx - xx.min(), right=xx.max() - cx,
    ))
    print(f"stadio {i + 1}: su={stages[-1]['up']} giù={stages[-1]['down']} "
          f"sx={stages[-1]['left']:.0f} dx={stages[-1]['right']:.0f}")

up = int(max(s["up"] for s in stages)) + PAD
down = int(max(s["down"] for s in stages)) + PAD
half = int(max(max(s["left"], s["right"]) for s in stages)) + PAD
CW, CH = 2 * half, up + down + 1
print(f"formato comune: {CW}x{CH}  (terra a riga {up})")

for i, s in enumerate(stages, 1):
    canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    img = Image.fromarray(s["rgba"], "RGBA")
    ox = int(round(half - s["cx"]))
    oy = int(up - s["ground"])
    canvas.alpha_composite(img, (max(ox, 0), max(oy, 0))) if ox >= 0 and oy >= 0 else canvas.paste(img, (ox, oy), img)
    canvas.save(f"assets/bonsy/stage{i}.png")
print("Scritti assets/bonsy/stage1.png ... stage5.png")
