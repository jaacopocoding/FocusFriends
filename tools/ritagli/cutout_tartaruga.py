#!/usr/bin/env python3
"""Ritaglia la tartaruga: le tavole in assets/tartaruga/ -> assets/tartaruga/frame1..23.png

Tavole su fondo bianco, con i disegni ben staccati (3 colonne per 2 righe):
  idle_original.png    la tartaruga ferma (un solo disegno, più grande degli altri)
  walk_original.png    la camminata: 6 fotogrammi
  eat_original.png     mangia una fragola: 5 fotogrammi (la fragola per terra fa parte del disegno)
  sleep_original.png   si addormenta: 6 fotogrammi (assonnata, sbadiglia, si sdraia, dorme)
  shell_original.png   si ritira nel guscio e ne riesce: 5 fotogrammi
  picked_original.png  (a parte) sollevata dalle mani: la ritaglia tools/ritagli/cutout_picked.py -> picked.png

Escono immagini tutte sulla stessa tela, con il guscio nello stesso punto e le zampe sulla stessa linea di terra:
  frame1       ferma
  frame2..7    i 6 passi
  frame8..12   mangia
  frame13..18  dorme
  frame19..23  si ritira nel guscio

Il guscio è l'unica cosa che non cambia da una posa all'altra (la testa entra ed esce, le zampe si piegano): lo riconosco dal
colore (verde oliva e caramello, poco blu: la pelle è verde salvia, con più blu, e la fragola è rossa) e lo uso per tutto.
Ogni tavola ha la tartaruga di una grandezza un po' diversa (un generatore di immagini non tiene la scala fra un foglio e
l'altro): la porto alla scala della camminata pareggiando la larghezza del guscio, e ogni fotogramma si allinea sul centro
del guscio.

Con --preview scrive anche fogli di controllo in build/tartaruga-*.png (i fotogrammi su fondo colorato) e la camminata
in build/tartaruga-camminata.gif.
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

DIR = "assets/tartaruga"
SHEETS = {  # nome: (file, fotogrammi attesi)
    "idle": ("idle_original.png", 1),
    "walk": ("walk_original.png", 6),
    "eat": ("eat_original.png", 5),
    "sleep": ("sleep_original.png", 6),
    "shell": ("shell_original.png", 5),
}
BG_MIN = 240            # sul bianco: sopra questo canale minimo un pixel è sfondo
MIN_PART = 60           # macchioline staccate più piccole di così si tolgono
SIDE_PAD = 10           # aria ai lati
TOP_PAD = 8
GROUND_PAD = 26         # sotto i piedi (c'è l'ombra dell'app)
SHELL_COLUMN = 10       # una colonna fa parte del guscio se ha almeno tanti pixel del suo colore
PREVIEW = "--preview" in sys.argv


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


def groups(mask_1d, gap, min_len):
    idx = np.where(mask_1d)[0]
    out, start, prev = [], idx[0], idx[0]
    for v in idx[1:]:
        if v - prev > gap:
            out.append((start, prev))
            start = v
        prev = v
    out.append((start, prev))
    return [g for g in out if g[1] - g[0] >= min_len]


def load_sheet(path, expected):
    """I disegni di una tavola, in ordine di lettura, in RGBA."""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    minc = rgb.min(axis=2)
    nonwhite = minc < 235
    frames = []
    third = rgb.shape[1] / 3
    for (ry0, ry1) in groups(nonwhite.any(axis=1), 25, 60):
        # le tavole sono a tre colonne: ogni pezzo staccato della riga va alla colonna in cui cade il suo centro (la fragola
        # sta quasi a cavallo fra due colonne, e un taglio sui vuoti la attaccherebbe alla tartaruga accanto)
        cells = {}
        for a, b in groups(nonwhite[ry0:ry1 + 1].any(axis=0), 6, 0):
            c = int((a + b) / 2 // third) if expected > 1 else 0
            lo, hi = cells.get(c, (a, b))
            cells[c] = (min(lo, a), max(hi, b))
        for (cx0, cx1) in [cells[c] for c in sorted(cells) if cells[c][1] - cells[c][0] >= 40]:
            x0, y0 = max(cx0 - 6, 0), max(ry0 - 6, 0)
            x1, y1 = min(cx1 + 6, rgb.shape[1] - 1), min(ry1 + 6, rgb.shape[0] - 1)
            block = rgb[y0:y1 + 1, x0:x1 + 1]
            bmin = minc[y0:y1 + 1, x0:x1 + 1]
            h, w = bmin.shape
            # Sfondo = bianco raggiungibile dal bordo: il bianco chiuso dal contorno (l'occhio) resta.
            cand = bmin >= BG_MIN
            border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] \
                   + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
            bg = flood(cand, border)
            fg = ~bg
            # Via le macchioline staccate (polvere dello sfondo).
            labeled = np.zeros_like(fg)
            for py, px in zip(*np.where(fg)):
                if labeled[py, px]:
                    continue
                comp = flood(fg & ~labeled, [(py, px)], diagonal=True)
                labeled |= comp
                if comp.sum() < MIN_PART:
                    fg &= ~comp
            edge = fg & dilate(~fg, 2)
            soft = np.clip((255 - bmin) / 90.0, 0.0, 1.0)
            alpha = np.where(edge, soft, fg.astype(np.float32))
            a = np.maximum(alpha, 1e-3)[..., None]
            color = np.clip(np.where(edge[..., None], (block - 255.0 * (1 - a)) / a, block), 0, 255)
            rgba = np.dstack([color, alpha * 255]).astype(np.uint8)
            frames.append(rgba)
    assert len(frames) == expected, f"{path}: attesi {expected} disegni, trovati {len(frames)}"
    return frames


def solid(rgba):
    return rgba[..., 3] > 128


def ground_of(rgba):
    return int(np.where(solid(rgba).any(axis=1))[0][-1])


def shell_span(rgba):
    """Da dove a dove (in x) va il guscio: le colonne con abbastanza pixel verde oliva o caramello."""
    r, g, b = (rgba[..., i].astype(int) for i in range(3))
    mask = solid(rgba) & (b < 0.68 * g) & (r > 0.7 * g) & (r < 1.45 * g) & (g > 60) & (g < 215)
    cols = np.where(mask.sum(axis=0) >= SHELL_COLUMN)[0]
    # il pezzo più lungo di colonne contigue (via i ciuffetti d'erba e le foglie della fragola)
    best = max(groups(np.isin(np.arange(rgba.shape[1]), cols), 3, 0), key=lambda g: g[1] - g[0])
    return float(best[0]), float(best[1])


def rescale(rgba, k):
    if abs(k - 1.0) < 0.003:
        return rgba
    img = Image.fromarray(rgba, "RGBA")
    return np.asarray(img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS))


def main():
    sheets = {name: load_sheet(os.path.join(DIR, file), count) for name, (file, count) in SHEETS.items()}

    def shell_width(rgba):
        left, right = shell_span(rgba)
        return right - left

    ref = float(np.median([shell_width(f) for f in sheets["walk"]]))
    print(f"camminata: guscio largo {ref:.0f}")
    # La scala di ogni tavola, perché il guscio risulti largo come nella camminata. Per la tavola del guscio conto solo
    # i fotogrammi in cui la tartaruga è fuori (nel terzo il guscio poggia a terra ed è disegnato un po' diverso).
    picks = {"shell": (0, 1, 3, 4)}
    scale = {}
    for name, frames in sheets.items():
        chosen = [frames[i] for i in picks.get(name, range(len(frames)))]
        scale[name] = ref / float(np.median([shell_width(f) for f in chosen]))
        print(f"  {name}: scala {scale[name]:.3f}")

    scaled = {n: [rescale(f, scale[n]) for f in fs] for n, fs in sheets.items()}

    order = [("idle", 0), *[("walk", i) for i in range(6)], *[("eat", i) for i in range(5)],
             *[("sleep", i) for i in range(6)], *[("shell", i) for i in range(5)]]
    frames = []
    for name, i in order:
        rgba = scaled[name][i]
        left, right = shell_span(rgba)
        frames.append(dict(name=f"{name}{i + 1}", rgba=rgba, ax=(left + right) / 2, ground=ground_of(rgba)))

    left = max(f["ax"] for f in frames)
    right = max(f["rgba"].shape[1] - f["ax"] for f in frames)
    up = max(f["ground"] for f in frames)
    # il guscio un po' a sinistra del centro: davanti c'è la testa (e la fragola), dietro solo la coda
    width = int(round(left + right + 2 * SIDE_PAD))
    height = int(round(up + 1 + TOP_PAD + GROUND_PAD))
    ground_y = height - GROUND_PAD - 1
    shell_x = left + SIDE_PAD
    out = []
    for n, f in enumerate(frames, 1):
        canvas = Image.new("RGBA", (width, height), (255, 255, 255, 0))
        img = Image.fromarray(f["rgba"], "RGBA")
        x = int(round(shell_x - f["ax"]))
        y = int(round(ground_y - f["ground"]))
        canvas.alpha_composite(img, (x, y))
        canvas.save(os.path.join(DIR, f"frame{n}.png"))
        out.append(canvas)
    print(f"  {len(out)} immagini {width}x{height}, piedi a {GROUND_PAD / height:.4f} dal fondo, guscio a {shell_x / width:.3f} della larghezza")

    if PREVIEW:
        os.makedirs("build", exist_ok=True)
        cols = 6
        rows = (len(out) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * width, rows * height), (214, 232, 204))
        for k, im in enumerate(out):
            tile = Image.new("RGB", im.size, (214, 232, 204))
            tile.paste(im, (0, 0), im)
            sheet.paste(tile, ((k % cols) * width, (k // cols) * height))
        sheet.save("build/tartaruga-pose.png")
        gif = []
        for im in out[1:7]:
            tile = Image.new("RGB", im.size, (214, 232, 204))
            tile.paste(im, (0, 0), im)
            gif.append(tile)
        gif[0].save("build/tartaruga-camminata.gif", save_all=True, append_images=gif[1:], duration=150, loop=0)
        print("anteprime in build/tartaruga-pose.png e build/tartaruga-camminata.gif")


if __name__ == "__main__":
    main()
