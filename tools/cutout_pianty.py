#!/usr/bin/env python3
"""Ritaglia Pianty che cammina: assets/pianty/sheets/stage1..5.png -> assets/pianty/stage{S}_{F}.png

Ogni tavola ha un solo stadio di crescita con 5 fotogrammi in fila (fermo, passo, passaggio, passo,
passaggio). Qui si tolgono lo sfondo bianco e le sacche di bianco fra le foglie, e si porta tutto
sulla stessa scala e sullo stesso colore:

* la scala si ricava dal vaso (larghezza e altezza dal bordo ai piedi), con lo stadio 5 come
  riferimento: Gemini disegna il vaso un po' diverso da una tavola all'altra;
* il colore della terracotta è riportato su un valore unico (un guadagno per canale per tavola);
* tutti i 25 fotogrammi stanno su una tela comune, appoggiati sui piedi e centrati sul vaso,
  così cambiando fotogramma o stadio nulla "salta".
"""
from collections import deque
import numpy as np
from PIL import Image

SHEET = "assets/pianty/sheets/stage{}.png"
OUT = "assets/pianty/stage{}_{}.png"
STAGES, FRAMES = 5, 5
REFERENCE_STAGE = 5
BG_MIN = 246          # sopra questo (canale minimo) un pixel è sfondo bianco
HALO_MIN = 205        # lungo il bordo, i pixel più chiari di così diventano trasparenti
MIN_POCKET = 40       # sacche di bianco più piccole di così sono riflessi, non sfondo
PAD = 4
TERRACOTTA = np.array([216.0, 144.0, 104.0])   # colore comune del vaso


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
    for gx0, gx1 in column_groups(minc, FRAMES):
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


def main():
    sheets = {s: load_sheet(SHEET.format(s)) for s in range(1, STAGES + 1)}

    # Misure di riferimento: lo stadio finale.
    ref = sheets[REFERENCE_STAGE]
    ref_w = np.median([f["pot_w"] for f in ref])
    ref_h = np.median([f["bottom"] - f["rim"] for f in ref])

    # Colore: mediana della terracotta di ogni tavola -> guadagno verso il colore comune.
    scales, gains = {}, {}
    for s, frames in sheets.items():
        w = np.median([f["pot_w"] for f in frames])
        h = np.median([f["bottom"] - f["rim"] for f in frames])
        scales[s] = (ref_w / w + ref_h / h) / 2.0
        samples = []
        for f in frames:
            rows = np.arange(f["block"].shape[0])[:, None]
            m = f["terra"] & (rows >= f["rim"] - 25) & f["fg"]
            samples.append(f["block"][m])
        median = np.median(np.concatenate(samples), axis=0)
        gains[s] = TERRACOTTA / median
        print(f"stadio {s}: vaso {w:.0f}x{h:.0f} -> scala {scales[s]:.3f}, "
              f"colore {median.astype(int).tolist()} -> {TERRACOTTA.astype(int).tolist()}")

    # Ritaglio, scala e misure rispetto ai piedi (riga più bassa) e al centro del vaso.
    images = {}
    for s, frames in sheets.items():
        for i, f in enumerate(frames, 1):
            rgba = Image.fromarray(to_rgba(f, gains[s]), "RGBA")
            k = scales[s]
            rgba = rgba.resize((round(rgba.width * k), round(rgba.height * k)), Image.LANCZOS)
            a = np.asarray(rgba)[..., 3]
            ys, xs = np.where(a > 5)
            solid = np.where((a > 80).any(axis=1))[0]
            ground = int(solid.max())
            cx = f["cx"] * k
            images[(s, i)] = dict(
                img=rgba, ground=ground, cx=cx,
                up=ground - ys.min(), down=max(ys.max() - ground, 0),
                left=cx - xs.min(), right=xs.max() - cx,
            )

    up = int(max(v["up"] for v in images.values())) + PAD
    down = int(max(v["down"] for v in images.values())) + PAD
    half = int(np.ceil(max(max(v["left"], v["right"]) for v in images.values()))) + PAD
    cw, ch = 2 * half, up + down + 1
    print(f"formato comune: {cw}x{ch}  (piedi a riga {up}, {(down + 1) / ch:.4f} dal fondo)")

    for (s, i), v in images.items():
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        canvas.paste(v["img"], (int(round(half - v["cx"])), int(up - v["ground"])), v["img"])
        canvas.save(OUT.format(s, i))
    print(f"Scritti {len(images)} fotogrammi: assets/pianty/stage1_1.png ... stage5_5.png")


if __name__ == "__main__":
    main()
