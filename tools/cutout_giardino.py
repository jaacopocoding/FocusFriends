#!/usr/bin/env python3
"""Ritaglia gli oggetti del giardino: assets/giardino/<foglio>_original.png -> assets/giardino/<id>.png

Ogni foglio ha 12 oggetti in una griglia di 4 colonne per 3 righe, in ordine di lettura, ognuno nella sua cella:
  fiori_original.png       su fondo bianco
  compagni_original.png    su fondo magenta (#FF00FF): le case e le cose per i compagni
  arredi_original.png      su fondo magenta

Il fondo magenta si toglie meglio di quello bianco (non confonde i petali o le campanule bianche con lo sfondo);
sul bianco, invece, il bianco chiuso fra gli steli e le foglie è sfondo, tranne dove sta dentro un fiore bianco
(KEEP_POCKETS). I bordi si ripuliscono dal rosa che il magenta lascia sui contorni.

Il prato (prato_original.png, 1024x506) viene ingrandito 2x con una buona interpolazione -> prato.png.

Uso, dalla cartella principale:  python3 tools/cutout_giardino.py
"""
from collections import deque
import numpy as np
from PIL import Image

DIR = "assets/giardino"
# (foglio, sfondo, gli id degli oggetti in ordine di lettura, oggetti con il bianco chiuso da tenere)
SHEETS = [
    ("fiori_original.png", "white",
     ["margherite", "tulipani", "lavanda", "girasole", "papaveri", "erbe", "funghi", "felci", "rosaio", "trifoglio",
      "mughetti", "erba-alta"],
     {"margherite", "mughetti"}),
    ("compagni_original.png", "magenta",
     ["casetta-gatto", "tiragraffi", "cesto-cuscino", "casetta-porcellino", "tunnel", "cesto-carote", "casetta-uccelli",
      "altalena-uccelli", "bagnetto", "vaso-grande", "annaffiatoio", "aiuola"],
     set()),
    ("arredi_original.png", "magenta",
     ["panchina", "altalena", "amaca", "tavolino", "picnic", "sdraio", "lampione", "bandierine", "carillon",
      "cancelletto", "arco-rose", "ponticello"],
     set()),
]
COLUMNS, ROWS = 4, 3
BG_MIN = 240            # sul bianco: sopra questo canale minimo un pixel è sfondo
MIN_SPECK = 25          # macchioline staccate più piccole di così si tolgono (sfondo bianco)
MIN_PIECE = 150         # idem sul magenta: i pezzi veri (le aste delle bandierine) sono più grandi
PAD = 3


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


def keep_pieces(mask, min_size):
    """Tiene solo i pezzi connessi (anche in diagonale) di almeno `min_size` pixel."""
    keep = np.zeros_like(mask)
    seen = np.zeros_like(mask)
    for y, x in zip(*np.where(mask)):
        if seen[y, x]:
            continue
        piece = flood(mask & ~seen, [(y, x)], diagonal=True)
        seen |= piece
        if piece.sum() >= min_size:
            keep |= piece
    return keep


def border_seeds(h, w):
    return [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] \
         + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]


def white_object(rgb, keep_pockets):
    """Un oggetto su fondo bianco -> RGBA."""
    minc = rgb.min(axis=2)
    cand = minc >= BG_MIN
    h, w = cand.shape
    bg = flood(cand, border_seeds(h, w))            # il bianco raggiungibile dal bordo
    if not keep_pockets:
        # anche il bianco chiuso fra gli steli e le foglie è sfondo
        rest = cand & ~bg
        seen = np.zeros_like(rest)
        for y, x in zip(*np.where(rest)):
            if seen[y, x]:
                continue
            pocket = flood(rest & ~seen, [(y, x)])
            seen |= pocket
            if pocket.sum() >= 6:
                bg |= pocket
    bg = bg | (dilate(bg, 1) & (minc > 225))        # l'alone chiaro
    fg = keep_pieces(~bg, MIN_SPECK)
    edge = fg & dilate(~fg, 1)
    alpha = np.where(edge, np.clip((255 - minc) / 70, 0.3, 1), fg.astype(np.float32))
    a = np.maximum(alpha, 1e-3)[..., None]
    color = np.clip(np.where(edge[..., None], (rgb - 255 * (1 - a)) / a, rgb), 0, 255)
    return np.dstack([color, alpha * 255]).astype(np.uint8)


def magenta_object(rgb):
    """Un oggetto su fondo magenta -> RGBA, con i bordi ripuliti dal rosa dello sfondo."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    magenta = np.minimum(r, b) - g                  # quanto un pixel è magenta
    alpha = np.clip(1 - (magenta - 60) / (170 - 60), 0, 1)
    keep = keep_pieces(alpha > 0.5, MIN_PIECE)
    alpha = np.where(dilate(keep, 3), alpha, 0)
    out = rgb.copy()
    edge = dilate(alpha < 0.5, 5) & (alpha > 0.02)
    spill = np.maximum(0, np.minimum(out[..., 0], out[..., 2]) - out[..., 1])
    k = np.where(edge, 0.9, 0.0)
    out[..., 0] -= k * spill
    out[..., 2] -= k * spill
    return np.dstack([np.clip(out, 0, 255), alpha * 255]).astype(np.uint8)


def crop(rgba):
    ys, xs = np.where(rgba[..., 3] > 25)
    y0, y1 = max(ys.min() - PAD, 0), min(ys.max() + PAD + 1, rgba.shape[0])
    x0, x1 = max(xs.min() - PAD, 0), min(xs.max() + PAD + 1, rgba.shape[1])
    return rgba[y0:y1, x0:x1]


def main():
    written = 0
    for name, background, ids, keep in SHEETS:
        sheet = np.asarray(Image.open(f"{DIR}/{name}").convert("RGB")).astype(np.float32)
        height, width, _ = sheet.shape
        ch, cw = height / ROWS, width / COLUMNS
        assert len(ids) == COLUMNS * ROWS, f"{name}: servono {COLUMNS * ROWS} id"
        for n, item in enumerate(ids):
            row, col = divmod(n, COLUMNS)
            cell = sheet[int(row * ch):int((row + 1) * ch), int(col * cw):int((col + 1) * cw)]
            rgba = white_object(cell, item in keep) if background == "white" else magenta_object(cell)
            Image.fromarray(crop(rgba), "RGBA").save(f"{DIR}/{item}.png", optimize=True)
            written += 1
    meadow = Image.open(f"{DIR}/prato_original.png").convert("RGB")
    meadow.resize((meadow.width * 2, meadow.height * 2), Image.LANCZOS).save(f"{DIR}/prato.png", optimize=True)
    print(f"Scritti {written} oggetti e il prato in {DIR}/")


if __name__ == "__main__":
    main()
