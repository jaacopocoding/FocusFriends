#!/usr/bin/env python3
"""Ritaglia i 5 stadi della succulenta: assets/pianty/original.png -> assets/pianty/stage1.png ... stage5.png

Come tools/cutout_bonsy.py: stessa scala e stesso formato per tutti gli stadi, allineati sul piano
di appoggio e centrati sul vaso. Qui il terreno è disegnato con una riga, due trattini e un sassolino:
vengono tolti lasciando intatti il vaso (terracotta) e le foglie cadute (verdi).
"""
from collections import deque
import numpy as np
from PIL import Image

SRC = "assets/pianty/original.png"
BG_MIN = 246          # sopra questo (canale minimo) un pixel è sfondo bianco
MIN_POCKET = 40       # sacche di bianco più piccole di così sono riflessi, non sfondo
PAD = 4

src = Image.open(SRC).convert("RGB")
rgb = np.asarray(src).astype(np.float32)
H, W, _ = rgb.shape
minc, maxc = rgb.min(axis=2), rgb.max(axis=2)

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


def dilate(mask, n):
    out = mask.copy()
    for _ in range(n):
        p = np.pad(out, 1)
        out = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return out


def flood(passable, seeds):
    h, w = passable.shape
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


stages = []
for i, (gx0, gx1) in enumerate(groups):
    x0 = max(gx0 - 6, 0)
    x1 = min(gx1 + 6, W - 1)
    block = rgb[:, x0:x1 + 1, :]
    bmin, bmax = minc[:, x0:x1 + 1], maxc[:, x0:x1 + 1]
    r, g, b = block[..., 0], block[..., 1], block[..., 2]
    h, w = bmin.shape

    # Vaso = terracotta nella parte bassa; verde = foglie/piantina.
    terra = (r > 150) & (r - b > 60) & (g > 70) & (g < 170)
    rows = np.arange(h)[:, None]
    pot = terra & (rows >= 380)
    pot_rows = np.where(pot.any(axis=1))[0]
    widest = np.where(pot.sum(axis=1) > 0.9 * pot.sum(axis=1).max())[0]
    pot_cols = np.where(pot[widest].any(axis=0))[0]
    ground = int(pot_rows.max())                         # fondo del vaso = piano d'appoggio
    cx = (pot_cols.min() + pot_cols.max()) / 2.0

    green = (g > r + 8) & (g > b + 8)

    # Via riga di terra, trattini e sassolino: pixel scuri/neutri in basso, lontani dal vaso e dalle foglie.
    neutral = (bmax - bmin < 45) & (bmin < BG_MIN)   # anche i grigi chiari della riga, non solo i neri
    keep = dilate(pot, 3) | dilate(green, 3)
    ground_zone = rows >= (ground - 8)
    erase = neutral & ground_zone & ~keep
    # anche il riempimento chiaro del sassolino: poco saturo, sotto il piano del vaso
    pebble = (bmax - bmin < 40) & (rows > ground + 1) & ~keep
    erase |= pebble & (bmin < 246)

    work = bmin.copy()
    work[erase] = 255.0          # trattali come sfondo bianco

    # Sfondo = bianco raggiungibile dal bordo. Poi le sacche di bianco chiuse fra le foglie.
    cand = work >= BG_MIN
    border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] \
           + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    bg = flood(cand, border)

    remaining = cand & ~bg
    seen = np.zeros_like(remaining)
    for y0, x0_ in zip(*np.where(remaining)):
        if seen[y0, x0_]:
            continue
        comp = flood(remaining & ~seen, [(y0, x0_)])
        seen |= comp
        if comp.sum() >= MIN_POCKET:
            bg |= comp

    fg = ~bg
    fg &= ~erase                               # i pixel cancellati restano trasparenti

    # Alpha: pieno dentro, morbido sul bordo; sul bordo tolgo il bianco "mescolato" (matte bianco).
    edge = fg & dilate(bg | erase, 2)
    soft = np.clip((255 - bmin) / 90.0, 0.0, 1.0)
    alpha = np.where(edge, soft, fg.astype(np.float32))
    a = np.maximum(alpha, 1e-3)[..., None]
    color = np.where(edge[..., None], (block - 255.0 * (1 - a)) / a, block)
    color = np.clip(color, 0, 255)

    rgba = np.dstack([color, alpha * 255]).astype(np.uint8)
    yy, xx = np.where(alpha > 0.02)
    stages.append(dict(
        rgba=rgba, cx=cx, ground=ground,
        up=ground - yy.min(), down=max(yy.max() - ground, 0),
        left=cx - xx.min(), right=xx.max() - cx,
    ))
    s = stages[-1]
    print(f"stadio {i + 1}: su={s['up']} giù={s['down']} sx={s['left']:.0f} dx={s['right']:.0f}")

up = int(max(s["up"] for s in stages)) + PAD
down = int(max(s["down"] for s in stages)) + PAD
half = int(max(max(s["left"], s["right"]) for s in stages)) + PAD
CW, CH = 2 * half, up + down + 1
print(f"formato comune: {CW}x{CH}  (piano d'appoggio a riga {up}, {(down + 1) / CH:.3f} dal fondo)")

for i, s in enumerate(stages, 1):
    canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    img = Image.fromarray(s["rgba"], "RGBA")
    canvas.paste(img, (int(round(half - s["cx"])), int(up - s["ground"])), img)
    canvas.save(f"assets/pianty/stage{i}.png")
print("Scritti assets/pianty/stage1.png ... stage5.png")
