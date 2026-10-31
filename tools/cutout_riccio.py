#!/usr/bin/env python3
"""Ritaglia il riccio: le tavole in assets/riccio/ -> assets/riccio/frame1..23.png e assets/garden/growth_riccio_1..5.png

Tavole su fondo bianco, con i disegni ben staccati (3 colonne per 2 righe, o in fila):
  idle_original.png    il riccio fermo (un solo disegno)
  walk_original.png    la camminata: 6 fotogrammi
  eat_original.png     mangia uno spicchio di mela: 5 fotogrammi
  sleep_original.png   dorme: 6 fotogrammi (il primo in piedi, assopito)
  roll_original.png    si arrotola e si riapre: 5 fotogrammi
  growth_original.png  la schiena che si riempie di foglia, fungo, mela e ghianda: 5 immagini (gli stadi del focus)
  picked_original.png  (a parte) sollevato dalle mani, spaventato: lo ritaglia tools/cutout_picked.py -> picked.png

Escono immagini tutte sulla stessa tela, con il corpo al centro e le zampe sulla stessa linea di terra:
  frame1       fermo
  frame2..7    i 6 passi
  frame8..12   mangia
  frame13..18  dorme
  frame19..23  si arrotola
  growth_riccio_1..5  (in assets/garden, come le carote del porcellino) la schiena che si riempie (tela più alta: ci stanno il fungo e la mela; stessa scala e stessi piedi)

Ogni tavola ha il riccio di una grandezza un po' diversa (un generatore di immagini non tiene la scala fra un foglio
e l'altro): lo porto alla scala della camminata, misurando la larghezza del riccio in piedi (per chi mangia, seduto,
la distanza fra l'occhio e il naso). Dentro la tavola i fotogrammi si sovrappongono sul corpo, così il riccio non
scivola da un fotogramma all'altro.

Con --preview scrive anche fogli di controllo in build/riccio-*.png (i fotogrammi su fondo colorato).
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

DIR = "assets/riccio"
SHEETS = {  # nome: (file, fotogrammi attesi)
    "idle": ("idle_original.png", 1),
    "walk": ("walk_original.png", 6),
    "eat": ("eat_original.png", 5),
    "sleep": ("sleep_original.png", 6),
    "roll": ("roll_original.png", 5),
    "growth": ("growth_original.png", 5),
}
BG_MIN = 240            # sul bianco: sopra questo canale minimo un pixel è sfondo
MIN_PART = 60           # macchioline staccate più piccole di così si tolgono
SIDE_PAD = 10           # aria ai lati
TOP_PAD = 8
GROUND_PAD = 26         # sotto i piedi (c'è l'ombra dell'app)
EAT_SCALE = 1.12
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
    """I disegni di una tavola, in ordine di lettura: ognuno con RGBA e la riga dei piedi."""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    minc = rgb.min(axis=2)
    nonwhite = minc < 235
    frames = []
    for (ry0, ry1) in groups(nonwhite.any(axis=1), 25, 60):
        for (cx0, cx1) in groups(nonwhite[ry0:ry1 + 1].any(axis=0), 6, 40):
            x0, y0 = max(cx0 - 6, 0), max(ry0 - 6, 0)
            x1, y1 = min(cx1 + 6, rgb.shape[1] - 1), min(ry1 + 6, rgb.shape[0] - 1)
            block = rgb[y0:y1 + 1, x0:x1 + 1]
            bmin = minc[y0:y1 + 1, x0:x1 + 1]
            h, w = bmin.shape
            # Sfondo = bianco raggiungibile dal bordo: il bianco chiuso dal contorno (l'occhio, la mela) resta.
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


def size_of(rgba):
    ys, xs = np.where(solid(rgba))
    return float(xs.max() - xs.min()), float(ys.max() - ys.min())


def ground_of(rgba):
    return int(np.where(solid(rgba).any(axis=1))[0][-1])


def torso_band(rgba):
    """Il dorso e il fianco, senza testa né zampe che si muovono: tiene fermo il riccio da un fotogramma all'altro."""
    alpha = solid(rgba)
    rows = np.where(alpha.any(axis=1))[0]
    top, bottom = rows[0], rows[-1]
    band = np.zeros_like(alpha)
    lo, hi = int(top + 0.25 * (bottom - top)), int(top + 0.75 * (bottom - top))
    cols = np.where(alpha.any(axis=0))[0]
    # solo la metà di dietro (a sinistra): la testa guarda a destra e cambia da una posa all'altra
    left, right = cols[0], cols[-1]
    cut = int(left + 0.62 * (right - left))
    band[lo:hi, :cut] = alpha[lo:hi, :cut]
    return band


def shift_for(ref_band, band, reach=40):
    """Di quanti pixel (in x) spostare `band` per sovrapporsi meglio a `ref_band`."""
    h = max(ref_band.shape[0], band.shape[0])
    w = max(ref_band.shape[1], band.shape[1]) + 2 * reach

    def put(m, dx):
        out = np.zeros((h, w), dtype=bool)
        out[:m.shape[0], reach + dx:reach + dx + m.shape[1]] = m
        return out
    ref = put(ref_band, 0)
    best, best_score = 0, -1
    for dx in range(-reach, reach + 1):
        score = int((ref & put(band, dx)).sum())
        if score > best_score:
            best, best_score = dx, score
    return best


def eye_nose(rgba):
    """Distanza fra l'occhio e il naso (due macchie scure, quasi nere), o None se l'occhio è chiuso."""
    r, g, b = (rgba[..., i].astype(int) for i in range(3))
    dark = solid(rgba) & (r + g + b < 170) & (r < 80)
    seen = np.zeros_like(dark)
    comps = []
    for py, px in zip(*np.where(dark)):
        if seen[py, px]:
            continue
        comp = flood(dark & ~seen, [(py, px)], diagonal=True)
        seen |= comp
        if 25 <= comp.sum() <= 600:
            ys, xs = np.where(comp)
            comps.append((xs.mean(), ys.mean(), comp.sum()))
    if len(comps) < 2:
        return None
    comps.sort(key=lambda c: c[0])
    nose, eye = comps[-1], comps[-2]
    return float(np.hypot(nose[0] - eye[0], nose[1] - eye[1]))


def rescale(rgba, k):
    if abs(k - 1.0) < 0.003:
        return rgba
    img = Image.fromarray(rgba, "RGBA")
    return np.asarray(img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS))


def main():
    sheets = {}
    for name, (file, count) in SHEETS.items():
        path = os.path.join(DIR, file)
        sheets[name] = load_sheet(path, count)

    walk = sheets["walk"]
    ref_w = float(np.median([size_of(f)[0] for f in walk]))
    ref_en = eye_nose(walk[0])
    print(f"camminata: larghezza {ref_w:.0f}, occhio-naso {ref_en and round(ref_en)}")

    # La scala di ogni tavola, perché il riccio risulti grande come nella camminata.
    scale = {"walk": 1.0}
    scale["idle"] = ref_w / size_of(sheets["idle"][0])[0]
    scale["sleep"] = ref_w / size_of(sheets["sleep"][0])[0]                       # il primo è in piedi
    scale["roll"] = ref_w / float(np.median([size_of(sheets["roll"][i])[0] for i in (0, 3, 4)]))   # quelli in piedi
    scale["growth"] = ref_w / float(np.median([size_of(f)[0] for f in sheets["growth"]]))
    # Seduto, il riccio ha la testa piccola rispetto al corpo (il generatore lo disegna più tondo): pareggiando la testa
    # con quella della camminata il corpo uscirebbe enorme (1,38), e a grandezza di partenza la testa è troppo piccola.
    # Una via di mezzo: il corpo un po' più alto di quando sta in piedi (è seduto), la testa appena più piccola.
    scale["eat"] = EAT_SCALE
    eat_en = eye_nose(sheets["eat"][0])
    if ref_en and eat_en:
        print(f"  (a titolo di confronto: per pareggiare la testa servirebbe {ref_en / eat_en:.3f})")
    for k, v in scale.items():
        print(f"  {k}: scala {v:.3f}")

    scaled = {n: [rescale(f, scale[n]) for f in fs] for n, fs in sheets.items()}

    # Ancora x: il dorso del primo passo; tutti gli altri si sovrappongono a lui. Chi mangia (seduto) ha un altro
    # dorso: lo allineo sul primo fotogramma della sua tavola, con il bordo di dietro dove sta nella camminata.
    ref_band = torso_band(scaled["walk"][0])
    ref_left = float(np.where(solid(scaled["walk"][0]).any(axis=0))[0][0])
    ref_cx = float(np.where(ref_band)[1].mean())

    def anchor(rgba, how):
        if how == "torso":
            band = torso_band(rgba)
            return ref_cx - shift_for(ref_band, band)
        return float(np.where(solid(rgba).any(axis=0))[0][0]) + (ref_cx - ref_left)    # il bordo di dietro

    order = [("idle", 0, "torso"), *[("walk", i, "torso") for i in range(6)], *[("eat", i, "rear") for i in range(5)],
             *[("sleep", i, "torso") for i in range(6)], *[("roll", i, "torso") for i in range(5)]]
    frames = []
    for name, i, how in order:
        rgba = scaled[name][i]
        frames.append(dict(name=f"{name}{i + 1}", rgba=rgba, ax=anchor(rgba, how), ground=ground_of(rgba)))
    growth = [dict(name=f"growth{i + 1}", rgba=f, ax=anchor(f, "torso"), ground=ground_of(f)) for i, f in enumerate(scaled["growth"])]

    def extents(items):
        left = max(f["ax"] for f in items)
        right = max(f["rgba"].shape[1] - f["ax"] for f in items)
        up = max(f["ground"] for f in items)
        return left, right, up

    for label, items in (("pose", frames), ("crescita", growth)):
        l, r, u = extents(items)
        print(f"  {label}: a sinistra {l:.0f}, a destra {r:.0f}, in alto {u:.0f}")
    half = max(extents(frames)[0], extents(frames)[1], extents(growth)[0], extents(growth)[1]) + SIDE_PAD
    width = int(round(2 * half))

    def compose(items, tag, fname_fmt):
        up = extents(items)[2]
        height = int(round(up + 1 + TOP_PAD + GROUND_PAD))
        ground_y = height - GROUND_PAD - 1
        out = []
        for n, f in enumerate(items, 1):
            canvas = Image.new("RGBA", (width, height), (255, 255, 255, 0))
            img = Image.fromarray(f["rgba"], "RGBA")
            x = int(round(width / 2 - f["ax"]))
            y = int(round(ground_y - f["ground"]))
            canvas.alpha_composite(img, (x, y)) if (x >= 0 and y >= 0) else canvas.paste(img, (x, y), img)
            canvas.save(fname_fmt.format(n))
            out.append(canvas)
        print(f"  {tag}: {len(out)} immagini {width}x{height}, piedi a {GROUND_PAD / height:.4f} dal fondo")
        return out

    out_frames = compose(frames, "pose", os.path.join(DIR, "frame{}.png"))
    out_growth = compose(growth, "crescita", "assets/garden/growth_riccio_{}.png")

    if PREVIEW:
        os.makedirs("build", exist_ok=True)
        for tag, imgs in (("pose", out_frames), ("crescita", out_growth)):
            cols = 6
            rows = (len(imgs) + cols - 1) // cols
            w, h = imgs[0].size
            sheet = Image.new("RGB", (cols * w, rows * h), (214, 232, 204))
            for k, im in enumerate(imgs):
                tile = Image.new("RGB", im.size, (214, 232, 204))
                tile.paste(im, (0, 0), im)
                sheet.paste(tile, ((k % cols) * w, (k // cols) * h))
            sheet.save(f"build/riccio-{tag}.png")
        gif = []
        for im in out_frames[1:7]:
            tile = Image.new("RGB", im.size, (214, 232, 204))
            tile.paste(im, (0, 0), im)
            gif.append(tile)
        gif[0].save("build/riccio-camminata.gif", save_all=True, append_images=gif[1:], duration=150, loop=0)
        print("anteprime in build/riccio-pose.png, riccio-crescita.png e riccio-camminata.gif")


if __name__ == "__main__":
    main()
