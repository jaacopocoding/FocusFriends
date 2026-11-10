#!/usr/bin/env python3
"""Pianty che cammina: assets/pianty/sheets/stage1..5.png -> assets/pianty/stage{S}_{F}.png

Ogni tavola ha un solo stadio di crescita (un vaso con due piedini). Di ogni tavola si usa il
primo fotogramma, "fermo". Da lì:

1. si tolgono lo sfondo bianco e le sacche di bianco fra le foglie;
2. si portano tutti gli stadi sulla stessa scala (dal vaso, con lo stadio 5 come riferimento: Gemini
   disegna il vaso un po' diverso da una tavola all'altra) e sullo stesso colore di terracotta;
3. si genera il passo muovendo solo le gambe: la pianta e il vaso sono sempre lo stesso disegno, quindi
   le foglie non cambiano da un fotogramma all'altro.

Per ogni stadio escono 7 immagini: _1 = fermo, _2.._7 = i 6 fotogrammi del ciclo di passi.
Tutte hanno la stessa tela, appoggiata sui piedi e centrata sul vaso.
"""
from collections import deque
import math
import numpy as np
from PIL import Image

SHEET = "assets/pianty/sheets/stage{}.png"
OUT = "assets/pianty/stage{}_{}.png"
STAGES, SHEET_FRAMES = 5, 5
REFERENCE_STAGE = 5
BG_MIN = 246          # sopra questo (canale minimo) un pixel è sfondo bianco
HALO_MIN = 205        # lungo il bordo, i pixel più chiari di così diventano trasparenti
MIN_POCKET = 40       # sacche di bianco più piccole di così sono riflessi, non sfondo
PAD = 4
TERRACOTTA = np.array([216.0, 144.0, 104.0])   # colore comune del vaso

# Il passo (in pixel dell'immagine). Va con Walker: a 42 pt/s e ~0,4 pt per pixel il corpo avanza di
# circa 105 px/s, e con un ciclo di 6 fotogrammi a 15 al secondo il piede appoggiato non scivola.
CYCLE = 6
STRIDE = 10.0         # quanto il piede va avanti e indietro rispetto al vaso
LIFT = 4.0            # quanto si solleva il piede mentre va avanti
TILT = 1.5            # gradi di dondolio del vaso
BOB = 1.0             # rimbalzo del vaso
EXT = 10              # la gamba si prolunga sotto il vaso, così non resta un buco quando si muove
EXTRA = 24            # spazio in più nella tela di lavoro


# ----- ritaglio dallo sfondo bianco -----

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


def column_groups(minc, expected):
    cols = (minc < 240).any(axis=0)
    groups, start, prev = [], None, None
    for x, v in enumerate(cols):
        if v:
            if start is None:
                start = x
            elif x - prev > 8:                 # un buco di colonne bianche = fine del fotogramma
                groups.append((start, prev))
                start = x
            prev = x
    if start is not None:
        groups.append((start, prev))
    groups = [g for g in groups if g[1] - g[0] > 30]
    assert len(groups) == expected, f"attesi {expected} fotogrammi, trovati {len(groups)}: {groups}"
    return groups


def terracotta_mask(block):
    r, g, b = block[..., 0], block[..., 1], block[..., 2]
    return (r > 150) & (r - b > 60) & (g > 70) & (g < 190) & (r > g + 25)


def load_sheet(path):
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    minc = rgb.min(axis=2)
    frames = []
    for gx0, gx1 in column_groups(minc, SHEET_FRAMES):
        x0, x1 = max(gx0 - 6, 0), min(gx1 + 6, rgb.shape[1] - 1)
        block = rgb[:, x0:x1 + 1, :]
        bmin = minc[:, x0:x1 + 1]
        h, w = bmin.shape

        # Sfondo = bianco raggiungibile dal bordo; poi le sacche di bianco chiuse fra le foglie.
        cand = bmin >= BG_MIN
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

        # Alone: i pixel chiari lungo il bordo sono sfumature fra il tratto scuro e il bianco, non disegno.
        halo = ~bg & dilate(bg, 2) & (bmin > HALO_MIN)
        bg = bg | halo
        fg = ~bg

        # Misure del vaso: dove è più largo (il bordo) e fin dove arrivano i piedi.
        terra = terracotta_mask(block)
        per_row = terra.sum(axis=1)
        wide = np.where(per_row >= 0.92 * per_row.max())[0]
        pot_cols = np.where(terra[wide].any(axis=0))[0]
        rows = np.where(fg.any(axis=1))[0]
        frames.append(dict(
            block=block, bmin=bmin, bg=bg, fg=fg, terra=terra,
            rim=int(wide.min()), bottom=int(rows.max()),
            pot_w=float(pot_cols.max() - pot_cols.min() + 1),
            cx=float((pot_cols.min() + pot_cols.max()) / 2.0),
        ))
    return frames


def to_rgba(f, gain):
    """Alpha morbido sul bordo (togliendo il bianco mescolato), terracotta riportata al colore comune."""
    block, bmin, bg, fg = f["block"], f["bmin"], f["bg"], f["fg"]
    edge = fg & dilate(bg, 2)
    soft = np.clip((255 - bmin) / 90.0, 0.0, 1.0)
    alpha = np.where(edge, soft, fg.astype(np.float32))
    a = np.maximum(alpha, 1e-3)[..., None]
    color = np.where(edge[..., None], (block - 255.0 * (1 - a)) / a, block)

    # Solo la terracotta della parte bassa (bordo del vaso e giù): così non tocco le punte rosate.
    rows = np.arange(block.shape[0])[:, None]
    pot = f["terra"] & (rows >= f["rim"] - 25) & fg
    color = np.where(pot[..., None], color * gain, color)
    color = np.clip(color, 0, 255)
    return np.dstack([color, alpha * 255]).astype(np.uint8)


# ----- il passo -----

def runs(row, thr=60):
    cols = np.where(row > thr)[0]
    out = []
    if len(cols) == 0:
        return out
    s = p = cols[0]
    for c in cols[1:]:
        if c - p > 1:
            out.append((int(s), int(p)))
            s = c
        p = c
    out.append((int(s), int(p)))
    return out


def find_legs(arr):
    """Ritorna (riga più bassa, prima riga con due gambe separate, colonna che le divide)."""
    a = arr[..., 3]
    bottom = int(np.where((a > 80).any(axis=1))[0].max())
    y = bottom - 4
    while y > 0 and len(runs(a[y])) >= 2:
        y -= 1
    y0 = y + 1
    r = runs(a[y0 + 4])
    return bottom, y0, (r[0][1] + r[-1][0]) / 2.0


def leg_images(arr, y0, bottom, split):
    h, w = arr.shape[:2]
    out = []
    for side in (0, 1):
        seg = arr[y0:bottom + 1].copy()
        cols = np.arange(w)[None, :]
        mask = (cols < split) if side == 0 else (cols >= split)
        seg[~np.broadcast_to(mask, seg.shape[:2])] = 0
        xs = np.where((seg[..., 3] > 0).any(axis=0))[0]
        x0, x1 = int(xs.min()), int(xs.max())
        seg = seg[:, x0:x1 + 1]
        img = np.vstack([np.repeat(seg[:1], EXT, axis=0), seg])   # prolungata verso l'alto, sotto il vaso
        top_cols = np.where(seg[:4, :, 3] > 60)[1]
        out.append((Image.fromarray(img, "RGBA"), x0, float(top_cols.mean()) + x0))
    return out


def foot(q):
    """q in [0,1): fase della gamba. Ritorna (spostamento in x, sollevamento)."""
    if q < 0.5:                      # appoggiata: il piede scivola indietro rispetto al corpo
        u = q / 0.5
        return STRIDE * (1 - 2 * u), 0.0
    u = (q - 0.5) / 0.5              # in volo: va avanti, sollevato
    e = 0.5 - 0.5 * math.cos(math.pi * u)
    return -STRIDE + 2 * STRIDE * e, LIFT * math.sin(math.pi * u)


def shear_leg(limg, dx, lift):
    """Sposta il piede di dx tenendo ferma la cima (taglio orizzontale: la suola resta piatta) e lo
    solleva comprimendo la gamba in verticale."""
    w, h = limg.size
    hip = EXT
    length = max(h - hip, 1)
    s = length / max(length - lift, 1)
    pad = 24
    big = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    big.paste(limg, (pad, pad))
    hy = hip + pad
    coeffs = (1.0, -dx / length, dx * hy / length, 0.0, s, hy - hy * s)
    return big.transform(big.size, Image.AFFINE, coeffs, resample=Image.BICUBIC), pad


def walk_frame(arr, k):
    h, w = arr.shape[:2]
    bottom, y0, split = find_legs(arr)
    legs = leg_images(arr, y0, bottom, split)
    body = arr.copy()
    body[y0:] = 0
    body = Image.fromarray(body, "RGBA")

    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for idx, (limg, x0, _hip_x) in enumerate(legs):
        q = (k / CYCLE + (0.5 if idx == 1 else 0.0)) % 1.0
        dx, lift = foot(q)
        sheared, pad = shear_leg(limg, dx, lift)
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        layer.paste(sheared, (int(round(x0 - pad)), int(round(y0 - EXT - pad))), sheared)
        canvas = Image.alpha_composite(canvas, layer)

    phi = 2 * math.pi * k / CYCLE
    pivot = ((legs[0][2] + legs[1][2]) / 2.0, bottom)
    tilted = body.rotate(TILT * math.sin(phi), resample=Image.BICUBIC, center=pivot)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    layer.paste(tilted, (0, -int(round(BOB * abs(math.sin(phi))))), tilted)
    return Image.alpha_composite(canvas, layer)


# ----- tutto insieme -----

def main():
    sheets = {s: load_sheet(SHEET.format(s)) for s in range(1, STAGES + 1)}

    # Misure di riferimento: lo stadio finale.
    ref = sheets[REFERENCE_STAGE]
    ref_w = np.median([f["pot_w"] for f in ref])
    ref_h = np.median([f["bottom"] - f["rim"] for f in ref])

    # Scala dal vaso; colore: mediana della terracotta di ogni tavola -> colore comune.
    scales, gains = {}, {}
    for s, frames in sheets.items():
        w = np.median([f["pot_w"] for f in frames])
        h = np.median([f["bottom"] - f["rim"] for f in frames])
        scales[s] = (ref_w / w + ref_h / h) / 2.0
        samples = []
        for f in frames:
            rows = np.arange(f["block"].shape[0])[:, None]
            m = f["terra"] & (f["rim"] - 25 <= rows) & f["fg"]
            samples.append(f["block"][m])
        median = np.median(np.concatenate(samples), axis=0)
        gains[s] = TERRACOTTA / median
        print(f"stadio {s}: vaso {w:.0f}x{h:.0f} -> scala {scales[s]:.3f}, "
              f"colore {median.astype(int).tolist()} -> {TERRACOTTA.astype(int).tolist()}")

    # Il fotogramma "fermo" di ogni stadio, in scala, su una tela di lavoro comune (piedi e centro del vaso).
    rests = {}
    for s, frames in sheets.items():
        f = frames[0]
        rgba = Image.fromarray(to_rgba(f, gains[s]), "RGBA")
        k = scales[s]
        rgba = rgba.resize((round(rgba.width * k), round(rgba.height * k)), Image.LANCZOS)
        a = np.asarray(rgba)[..., 3]
        ground = int(np.where((a > 80).any(axis=1))[0].max())
        rests[s] = (rgba, ground, f["cx"] * k)

    half0 = int(max(max(c, img.width - c) for img, _, c in rests.values())) + EXTRA
    up0 = int(max(g for _, g, _ in rests.values())) + EXTRA
    down0 = int(max(img.height - g for img, g, _ in rests.values())) + EXTRA
    cw0, ch0 = 2 * half0, up0 + down0 + 1

    frames_out = {}
    for s, (img, ground, cx) in rests.items():
        canvas = Image.new("RGBA", (cw0, ch0), (0, 0, 0, 0))
        canvas.paste(img, (int(round(half0 - cx)), int(up0 - ground)), img)
        arr = np.asarray(canvas).copy()
        frames_out[s] = [canvas] + [walk_frame(arr, k) for k in range(CYCLE)]

    # Misure finali: l'unione di tutti i fotogrammi, con un piccolo margine.
    top = bottom = left = right = None
    for fs in frames_out.values():
        for f in fs:
            ys, xs = np.where(np.asarray(f)[..., 3] > 5)
            t, b, l, r = ys.min(), ys.max(), xs.min(), xs.max()
            top = t if top is None else min(top, t)
            bottom = b if bottom is None else max(bottom, b)
            left = l if left is None else min(left, l)
            right = r if right is None else max(right, r)
    half = int(math.ceil(max(half0 - left, right - half0 + 1))) + PAD
    up = up0 - top + PAD
    down = max(bottom - up0, 0) + PAD
    cw, ch = 2 * half, up + down + 1
    print(f"formato comune: {cw}x{ch}  (piedi a riga {up}, {(down + 1) / ch:.4f} dal fondo)")

    for s, fs in frames_out.items():
        for i, f in enumerate(fs, 1):
            f.crop((half0 - half, up0 - up, half0 + half, up0 - up + ch)).save(OUT.format(s, i))
    print(f"Scritti {STAGES * (CYCLE + 1)} fotogrammi: assets/pianty/stage1_1.png ... stage5_{CYCLE + 1}.png")


if __name__ == "__main__":
    main()
