#!/usr/bin/env python3
"""Ritaglia i fotogrammi del porcellino da più fogli e li scrive su un formato comune.

Fogli (in assets/porcellino/), nell'ordine in cui diventano frame1.png, frame2.png, ...:
  original.png        cammino: 5 fotogrammi (fermo, 3 passi, orecchie)       -> frame1..5
  eat_original.png    mangia la carota                                        -> frame6...
  sleep_original.png  dorme                                                   -> (se presente)
  jump_original.png   popcorning                                              -> (se presente)

I fogli mancanti vengono saltati. Tutti i fotogrammi escono con lo stesso formato, con il corpo nella
stessa posizione e i piedi sulla stessa linea di terra, così passando da un'azione all'altra il
personaggio non "salta". Le parti staccate dal corpo vengono tolte.
"""
import os
from collections import deque
import numpy as np
from PIL import Image

DIR = "assets/porcellino"
# (file, come trovare la linea di terra, come centrare)
#   ground: "bottom" = il punto più basso del disegno; "rear" = il punto più basso della parte posteriore
#           (serve quando c'è un oggetto che sporge sotto i piedi, come la carota);
#           "jump" = per i salti: i fotogrammi a terra si allineano ai propri piedi, quelli in aria usano
#           come terra il piano degli altri (così l'altezza del salto si vede)
SHEETS = [
    ("original.png", "bottom"),
    ("eat_original.png", "rear"),
    ("sleep_original.png", "bottom"),
    ("jump_original.png", "jump"),
]
BG_MIN = 246
MIN_PART = 0.02
PAD = 4
# Spazio vuoto sopra il disegno: serve agli "Zzz" che salgono (e al popcorning, che salta in alto).
HEADROOM = 0     # non serve più: il fotogramma in aria del salto dà già tutto lo spazio sopra


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


def column_groups(minc, thr=240):
    cols = (minc < thr).any(axis=0)
    groups, start = [], None
    for x, v in enumerate(cols):
        if v and start is None:
            start = x
        if not v and start is not None:
            groups.append((start, x - 1))
            start = None
    if start is not None:
        groups.append((start, len(cols) - 1))
    return groups


def cut_sheet(path, ground_mode):
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    H, W, _ = rgb.shape
    minc = rgb.min(axis=2)
    frames = []
    for gx0, gx1 in column_groups(minc):
        x0, x1 = max(gx0 - 8, 0), min(gx1 + 8, W - 1)
        block, bmin = rgb[:, x0:x1 + 1, :], minc[:, x0:x1 + 1]
        h, w = bmin.shape

        cand = bmin >= BG_MIN
        border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] \
               + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
        bg = flood(cand, border)
        fg = ~bg

        # Tieni il corpo e le parti attaccate; scarta le macchioline staccate (segnini).
        labeled = np.zeros((h, w), dtype=np.int32)
        sizes, label = [], 0
        for y0, x0_ in zip(*np.where(fg)):
            if labeled[y0, x0_]:
                continue
            label += 1
            comp = flood(fg & (labeled == 0), [(y0, x0_)], four=False)
            labeled[comp] = label
            sizes.append((label, int(comp.sum())))
        biggest = max(n for _, n in sizes)
        keep = [lab for lab, n in sizes if n >= MIN_PART * biggest]
        fg &= np.isin(labeled, keep)

        edge = fg & dilate(~fg, 2)
        soft = np.clip((255 - bmin) / 90.0, 0.0, 1.0)
        alpha = np.where(edge, soft, fg.astype(np.float32))
        a = np.maximum(alpha, 1e-3)[..., None]
        color = np.clip(np.where(edge[..., None], (block - 255.0 * (1 - a)) / a, block), 0, 255)

        ys, xs = np.where(fg)
        top, bottom = ys.min(), ys.max()
        xmin, xmax = xs.min(), xs.max()
        upper = ys < top + 0.6 * (bottom - top)
        if ground_mode == "rear":
            rear = xs < xmin + 0.4 * (xmax - xmin)       # la parte posteriore: niente carota
            ground = ys[rear].max()
        else:
            ground = bottom
        frames.append(dict(
            rgba=np.dstack([color, alpha * 255]).astype(np.uint8), fg=fg,
            ground=int(ground), bottom=int(bottom), top=int(top), xmin=int(xmin), xmax=int(xmax),
            cx_centroid=float(xs[upper].mean()), xmin_upper=int(xs[upper].min()),
        ))
    return frames


# --- carica i fogli presenti ---
all_frames = []      # (nome foglio, indice, frame)
left_offset = None   # distanza fra il baricentro e il bordo posteriore, misurata sul foglio del cammino
for name, mode in SHEETS:
    path = os.path.join(DIR, name)
    if not os.path.exists(path):
        print(f"(salto {name}: non c'è)")
        continue
    frames = cut_sheet(path, mode)
    if mode == "jump":
        lowest = max(f["bottom"] for f in frames)
        grounded = [f["bottom"] for f in frames if lowest - f["bottom"] <= 10]
        ref = int(np.median(grounded))               # il piano d'appoggio: dove stanno i fotogrammi a terra
        for f in frames:
            f["ground"] = f["bottom"] if lowest - f["bottom"] <= 10 else ref
    if left_offset is None:
        left_offset = float(np.median([f["cx_centroid"] - f["xmin_upper"] for f in frames]))
    for f in frames:
        # Il corpo sta sempre nello stesso punto: allineo sul bordo posteriore (non sul baricentro,
        # che cambia se c'è una carota davanti al muso).
        f["cx"] = f["xmin_upper"] + left_offset
    print(f"{name}: {len(frames)} fotogrammi, piano d'appoggio a riga {[f['ground'] for f in frames]}")
    all_frames += [(name, i, f) for i, f in enumerate(frames)]

assert all_frames, "nessun foglio trovato"

# --- formato comune ---
up = max(f["ground"] - f["top"] for _, _, f in all_frames) + PAD + HEADROOM
down = max(f["bottom"] - f["ground"] for _, _, f in all_frames) + PAD
half = int(np.ceil(max(max(f["cx"] - f["xmin"], f["xmax"] - f["cx"]) for _, _, f in all_frames))) + PAD
CW, CH = 2 * half, int(up + down + 1)
print(f"formato comune: {CW}x{CH}  (terra a riga {up}, a {(down + 1) / CH:.3f} dal fondo)")

for n, (name, i, f) in enumerate(all_frames, 1):
    canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    img = Image.fromarray(f["rgba"], "RGBA")
    canvas.paste(img, (int(round(half - f["cx"])), int(up - f["ground"])), img)
    canvas.save(os.path.join(DIR, f"frame{n}.png"))
print(f"Scritti {len(all_frames)} fotogrammi: frame1.png ... frame{len(all_frames)}.png")
