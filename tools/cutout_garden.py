#!/usr/bin/env python3
"""Ritaglia una collezione del giardino: un foglio con 5 stadi in fila -> assets/garden/garden_<personaggio>_1..5.png

    python3 tools/cutout_garden.py assets/garden/ciccio_nido_original.png ciccio [scala]

Ogni stadio finisce sulla stessa tela delle piantine di Pianty (208x341, piedi a 1,76% dal fondo), così il
giardino li disegna alla stessa misura. Il "piede" di un nido è il suo bordo più basso, e il centro è il
centro di quel bordo; se l'adulto sporge (la coda) viene spostato quanto basta per restare nella tela.
"""
import sys
from collections import deque
import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "assets/garden/ciccio_nido_original.png"
PET = sys.argv[2] if len(sys.argv) > 2 else "ciccio"
SCALE = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
STAGES = 5
CANVAS_W, CANVAS_H = 208, 341
FEET_FRACTION = 0.0176
BG_MIN = 246
HALO_MIN = 205
MIN_POCKET = 40
MIN_PART = 14
MARGIN = 3


def dilate(mask, n):
    out = mask.copy()
    for _ in range(n):
        p = np.pad(out, 1)
        out = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return out


def flood(passable, seeds, diagonal=False):
    h, w = passable.shape
    seen = np.zeros((h, w), dtype=bool)
    q = deque()
    for y, x in seeds:
        if passable[y, x] and not seen[y, x]:
            seen[y, x] = True
            q.append((y, x))
    steps = ((1, 0), (-1, 0), (0, 1), (0, -1))
    if diagonal:
        steps += ((1, 1), (1, -1), (-1, 1), (-1, -1))
    while q:
        y, x = q.popleft()
        for dy, dx in steps:
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


rgb = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float32)
H, W, _ = rgb.shape
minc = rgb.min(axis=2)
ink = minc < 235

# 1) I cinque stadi: gruppi di colonne; se due si toccano, taglio nella colonna meno "inchiostrata".
cols = ink.any(axis=0)
groups, start, prev = [], None, None
for x, v in enumerate(cols):
    if v:
        if start is None:
            start = x
        elif x - prev > 8:
            groups.append((start, prev))
            start = x
        prev = x
if start is not None:
    groups.append((start, prev))
groups = [g for g in groups if g[1] - g[0] > 30]
exact_cuts = False
if len(groups) != STAGES:
    xs = np.where(cols)[0]
    x0, x1 = xs.min(), xs.max()
    per_col = ink.sum(axis=0)
    cuts = []
    for i in range(1, STAGES):
        guess = x0 + (x1 - x0 + 1) * i // STAGES
        lo, hi = guess - 45, guess + 45
        window = per_col[lo:hi]
        # La colonna più "vuota" è spesso una striscia di colonne vuote: taglio a metà della striscia più lunga.
        best, run_start, runs = window.min(), None, []
        for j, v in enumerate(window):
            if v <= best + 0:
                run_start = j if run_start is None else run_start
            elif run_start is not None:
                runs.append((run_start, j - 1)); run_start = None
        if run_start is not None:
            runs.append((run_start, len(window) - 1))
        a, b = max(runs, key=lambda r: r[1] - r[0])
        cuts.append(lo + (a + b) // 2)
    edges = [x0] + cuts + [x1 + 1]
    groups = [(edges[i], edges[i + 1] - 1) for i in range(STAGES)]
    exact_cuts = True
assert len(groups) == STAGES, groups
print("stadi:", groups)

frames = []
for gx0, gx1 in groups:
    margin = 0 if exact_cuts else 4          # con i tagli a mano non allargo: finirei nel vicino
    x0, x1 = max(gx0 - margin, 0), min(gx1 + margin, W - 1)
    block = rgb[:, x0:x1 + 1, :]
    bmin = minc[:, x0:x1 + 1]
    h, w = bmin.shape
    cand = bmin >= BG_MIN
    border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] \
           + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    bg = flood(cand, border)
    rem = cand & ~bg
    seen = np.zeros_like(rem)
    for y, x in zip(*np.where(rem)):
        if seen[y, x]:
            continue
        comp = flood(rem & ~seen, [(y, x)])
        seen |= comp
        if comp.sum() >= MIN_POCKET:
            bg |= comp
    halo = ~bg & dilate(bg, 2) & (bmin > HALO_MIN)
    bg |= halo
    fg = ~bg
    labeled = np.zeros_like(fg)
    for y, x in zip(*np.where(fg)):
        if labeled[y, x]:
            continue
        comp = flood(fg & ~labeled, [(y, x)], diagonal=True)
        labeled |= comp
        cx = np.where(comp.any(axis=0))[0]
        touches_cut = exact_cuts and (cx.min() == 0 or cx.max() == w - 1)
        if comp.sum() < MIN_PART or (touches_cut and comp.sum() < 120):   # pezzetti del vicino tagliati a metà
            fg &= ~comp
    edge = fg & dilate(~fg, 2)
    soft = np.clip((255 - bmin) / 90.0, 0.0, 1.0)
    alpha = np.where(edge, soft, fg.astype(np.float32))
    a = np.maximum(alpha, 1e-3)[..., None]
    color = np.clip(np.where(edge[..., None], (block - 255.0 * (1 - a)) / a, block), 0, 255)
    rgba = np.dstack([color, alpha * 255]).astype(np.uint8)

    ys, xs = np.where(fg)
    bottom = int(ys.max())
    base = fg[max(bottom - 30, 0):bottom + 1]          # il bordo basso del nido
    bx = np.where(base.any(axis=0))[0]
    center = (bx.min() + bx.max()) / 2.0
    frames.append(dict(img=Image.fromarray(rgba, "RGBA"), bottom=bottom, center=center, left=xs.min(), right=xs.max(), top=ys.min()))

out_dir = "assets/garden"
for i, f in enumerate(frames, 1):
    k = SCALE
    img = f["img"].resize((round(f["img"].width * k), round(f["img"].height * k)), Image.LANCZOS)
    bottom, center = f["bottom"] * k, f["center"] * k
    left, right = f["left"] * k, f["right"] * k
    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    feet_y = CANVAS_H * (1 - FEET_FRACTION)
    ox = CANVAS_W / 2 - center
    # Se la coda (o altro) uscirebbe dalla tela, sposto quanto basta.
    if left + ox < MARGIN:
        ox = MARGIN - left
    if right + ox > CANVAS_W - MARGIN:
        ox = CANVAS_W - MARGIN - right
    oy = feet_y - bottom
    canvas.paste(img, (int(round(ox)), int(round(oy))), img)
    top = f["top"] * k + oy
    path = f"{out_dir}/garden_{PET}_{i}.png"
    canvas.save(path)
    print(f"stadio {i}: nido largo {right - left:.0f}px, cima a {top:.0f}, spostamento {ox - (CANVAS_W/2 - center):+.0f}px -> {path}")
