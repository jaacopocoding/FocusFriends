#!/usr/bin/env python3
"""Ritaglia Ciccio, la cocorita: assets/ciccio/walk_original.png + flap_original.png -> assets/ciccio/frame1..13.png

Due tavole, ognuna con 6 fotogrammi (2 righe da 3):
  walk_original.png   la camminata
  flap_original.png   lo sbattere le ali sul posto

Escono 13 immagini, tutte sulla stessa tela, appoggiate sui piedi e allineate sul becco:
  frame1       fermo (il passaggio della camminata, con le zampe vicine)
  frame2..7    i 6 fotogrammi della camminata
  frame8..13   i 6 fotogrammi delle ali

La seconda tavola ha la cocorita un po' più piccola della prima: la porto alla stessa scala
dal confronto fra la sagoma dei fotogrammi con le ali chiuse.
"""
from collections import deque
import numpy as np
from PIL import Image

WALK = "assets/ciccio/walk_original.png"
FLAP = "assets/ciccio/flap_original.png"
OUT = "assets/ciccio/frame{}.png"
REST_FROM_WALK = 2          # il passaggio con le zampe vicine (1..6)
BG_MIN = 246
HALO_MIN = 228              # le penne chiare delle ali: più alto che per le piante
MIN_POCKET = 40
MIN_PART = 14               # macchioline staccate più piccole di così si tolgono
PAD = 4


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


def load_sheet(path):
    """Ritorna i 6 fotogrammi in ordine di lettura: ognuno con RGBA, ancora x (becco) e riga dei piedi."""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    minc = rgb.min(axis=2)
    nonwhite = minc < 235
    frames = []
    for (ry0, ry1) in groups(nonwhite.any(axis=1), 25, 60):
        for (cx0, cx1) in groups(nonwhite[ry0:ry1 + 1].any(axis=0), 10, 40):
            x0, y0 = max(cx0 - 6, 0), max(ry0 - 6, 0)
            x1, y1 = min(cx1 + 6, rgb.shape[1] - 1), min(ry1 + 6, rgb.shape[0] - 1)
            block = rgb[y0:y1 + 1, x0:x1 + 1]
            bmin = minc[y0:y1 + 1, x0:x1 + 1]
            h, w = bmin.shape

            # Sfondo = bianco raggiungibile dal bordo (poi le sacche chiuse, p.es. fra ala e corpo).
            cand = bmin >= BG_MIN
            border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] \
                   + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
            bg = flood(cand, border)
            remaining = cand & ~bg
            seen = np.zeros_like(remaining)
            for py, px in zip(*np.where(remaining)):
                if seen[py, px]:
                    continue
                comp = flood(remaining & ~seen, [(py, px)])
                seen |= comp
                if comp.sum() >= MIN_POCKET:
                    bg |= comp
            halo = ~bg & dilate(bg, 2) & (bmin > HALO_MIN)
            bg = bg | halo
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

            # Ancora orizzontale: il bordo destro del becco (il blu più a destra).
            r, g, b = block[..., 0], block[..., 1], block[..., 2]
            blue = fg & (b > r + 30) & (b > g + 8)
            xs = np.where(blue.any(axis=0))[0]
            anchor_x = float(xs.max())
            # Piedi: la riga più bassa nella fascia sotto il corpo (la coda scende più in basso, a sinistra).
            ys, cols = np.where(fg)
            body_x0, body_x1 = anchor_x - 190, anchor_x - 20
            in_band = (cols >= body_x0) & (cols <= body_x1)
            ground = float(ys[in_band].max())
            frames.append(dict(rgba=rgba, ax=anchor_x, ground=ground, fg=fg))
    assert len(frames) == 6, f"{path}: attesi 6 fotogrammi, trovati {len(frames)}"
    return frames


def head_width(frame):
    """Larghezza della testa gialla, per confrontare la scala fra le due tavole."""
    rgba = frame["rgba"].astype(int)
    r, g, b, a = rgba[..., 0], rgba[..., 1], rgba[..., 2], rgba[..., 3]
    yellow = (a > 200) & (r > 200) & (g > 180) & (b < 150) & (r - b > 80)
    ys, xs = np.where(yellow)
    return float(np.sqrt(yellow.sum()))


def main():
    walk = load_sheet(WALK)
    flap = load_sheet(FLAP)

    # Scala: la cocorita con le ali chiuse (ultimo e primo fotogramma delle ali) rispetto alla camminata.
    def body_size(frame):
        ys, xs = np.where(frame["rgba"][..., 3] > 128)
        return float(np.hypot(xs.max() - xs.min(), ys.max() - ys.min()))
    walk_size = np.median([body_size(f) for f in walk])
    flap_size = np.median([body_size(flap[0]), body_size(flap[5])])
    flap_scale = walk_size / flap_size
    print(f"scala delle ali rispetto alla camminata: {flap_scale:.3f}")

    # Tutte le immagini nell'ordine finale, ognuna con la sua scala.
    sources = [(walk[REST_FROM_WALK - 1], 1.0)] + [(f, 1.0) for f in walk] + [(f, flap_scale) for f in flap]
    items = []
    for f, k in sources:
        img = Image.fromarray(f["rgba"], "RGBA")
        if abs(k - 1.0) > 1e-6:
            img = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
        items.append(dict(img=img, ax=f["ax"] * k, ground=f["ground"] * k))

    left = int(np.ceil(max(i["ax"] for i in items)))
    right = int(np.ceil(max(i["img"].width - i["ax"] for i in items)))
    up = int(np.ceil(max(i["ground"] for i in items)))
    down = int(np.ceil(max(i["img"].height - i["ground"] for i in items)))
    cw, ch = left + right + 2 * PAD, up + down + 2 * PAD
    print(f"formato comune: {cw}x{ch}  (piedi a riga {up + PAD}, {(down + PAD) / ch:.4f} dal fondo)")

    for n, i in enumerate(items, 1):
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        canvas.paste(i["img"], (int(round(left + PAD - i["ax"])), int(round(up + PAD - i["ground"]))), i["img"])
        canvas.save(OUT.format(n))
    print(f"Scritti {len(items)} fotogrammi: assets/ciccio/frame1.png ... frame{len(items)}.png")


if __name__ == "__main__":
    main()
