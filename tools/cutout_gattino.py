#!/usr/bin/env python3
"""Ritaglia il gattino: le tavole in assets/gattino/ -> assets/gattino/frame1..23.png

Tavole su fondo bianco (le prime due sono obbligatorie, le altre si saltano se mancano):
  idle_original.png    il gatto fermo (un solo disegno)
  walk_original.png    la camminata: 6 fotogrammi (2 righe da 3)
  eat_original.png     mangia il pesce: 5 fotogrammi in fila
  sleep_original.png   dorme: 6 fotogrammi (2 righe da 3)
  groom_original.png   si lecca la zampa: 6 fotogrammi (2 righe da 3), il quinto non piace e si salta

Escono immagini tutte sulla stessa tela, con le zampe sulla stessa linea di terra:
  frame1       fermo
  frame2..7    i 6 fotogrammi della camminata (allineati sugli occhi, così la testa non traballa)
  frame8..12   mangia
  frame13..18  dorme
  frame19..23  si lecca la zampa

Ogni tavola ha il gatto di una grandezza un po' diversa (un generatore di immagini non tiene la scala fra
un foglio e l'altro): lo porto alla scala della camminata con un moltiplicatore per tavola (SCALE), scelto
confrontando la grandezza della testa nel foglio di controllo (--preview). Dentro la stessa tavola i fotogrammi si sovrappongono sul corpo, così il gatto
non scivola da un fotogramma all'altro. Le macchie staccate dal gatto (le "z" del sonno, le gocce) si
tolgono: l'app disegna da sé gli "Zzz".

Con --preview scrive anche un foglio di controllo (i fotogrammi su fondo colorato) in PREVIEW.
"""
import sys
from collections import deque
import numpy as np
from PIL import Image

import os

IDLE = "assets/gattino/idle_original.png"
WALK = "assets/gattino/walk_original.png"
# (nome, file, colonne della griglia, fotogrammi attesi, indici da saltare, come separare i gatti)
EXTRA = [
    ("eat", "assets/gattino/eat_original.png", 5, 5, [], "components"),
    ("sleep", "assets/gattino/sleep_original.png", 3, 6, [], "valley"),
    ("groom", "assets/gattino/groom_original.png", 3, 6, [4], "valley"),
]
# Moltiplicatore per tavola, perché la testa risulti grande come nella camminata.
SCALE = {"eat": 0.77, "sleep": 0.84, "groom": 0.82}
OUT = "assets/gattino/frame{}.png"
PREVIEW = "build/gattino-controllo.png"
BG_MIN = 246
MIN_PART = 40               # macchioline staccate più piccole di così si tolgono
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


def grid_columns(nonwhite_band, count):
    """Le colonne di una griglia: i baffi di un gatto toccano la coda del vicino, quindi non c'è un vuoto
    pulito; si taglia dove l'inchiostro è minimo, vicino a dove dovrebbe cadere il confine."""
    width = nonwhite_band.shape[1]
    ink = nonwhite_band.sum(axis=0)
    cuts = [0]
    for k in range(1, count):
        expect = round(k * width / count)
        reach = width // (count * 6)
        lo, hi = expect - reach, expect + reach
        cuts.append(lo + int(np.argmin(ink[lo:hi])))
    cuts.append(width)
    cells = []
    for c0, c1 in zip(cuts, cuts[1:]):
        idx = np.where(ink[c0:c1] > 0)[0]
        cells.append((c0 + int(idx[0]), c0 + int(idx[-1]), c0, c1 - 1))
    return cells


def component_cells(nonwhite, ry0, ry1, count):
    """Un gatto per ogni macchia connessa (i gatti si toccano nelle colonne ma non fra loro): per fogli in cui
    il taglio a colonne taglierebbe una coda. Ogni cella porta la maschera dei pixel suoi."""
    band = np.zeros_like(nonwhite)
    band[ry0:ry1 + 1] = nonwhite[ry0:ry1 + 1]
    joined = dilate(band, 3)
    cells, seen = [], np.zeros_like(joined)
    for py, px in zip(*np.where(joined)):
        if seen[py, px]:
            continue
        comp = flood(joined & ~seen, [(py, px)], diagonal=True)
        seen |= comp
        if comp.sum() < 2000:       # briciole
            continue
        xs = np.where(comp.any(axis=0))[0]
        cells.append((int(xs[0]), int(xs[-1]), 0, band.shape[1] - 1, comp))
    cells.sort(key=lambda c: c[0])
    assert len(cells) == count, f"attesi {count} gatti, trovati {len(cells)}"
    return cells


def load_sheet(path, expected, columns=0, bridge=0, keep_main=False, split="valley"):
    """I fotogrammi in ordine di lettura: ognuno con RGBA, ancora x (gli occhi) e riga delle zampe.
    `columns` = quante colonne ha la griglia (0 = un gatto per gruppo, separati da un vuoto).
    `bridge` = quanto è largo, al massimo, un buco nel contorno da chiudere prima di togliere lo sfondo:
    nel disegno da fermo il petto bianco non ha un contorno continuo e lo sfondo ci entrerebbe.
    `split` = "valley" (taglio dove c'è meno inchiostro) o "components" (una macchia connessa per gatto).
    `keep_main` = tiene solo il gatto: le macchie staccate (le "z", le gocce, i segni del movimento) si tolgono."""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    minc = rgb.min(axis=2)
    nonwhite = minc < 235
    frames = []
    for (ry0, ry1) in groups(nonwhite.any(axis=1), 25, 60):
        if columns and split == "components":
            cells = component_cells(nonwhite, ry0, ry1, columns)
        elif columns:
            cells = [c + (None,) for c in grid_columns(nonwhite[ry0:ry1 + 1], columns)]
        else:
            cells = [(a, b, 0, rgb.shape[1] - 1, None)
                     for a, b in groups(nonwhite[ry0:ry1 + 1].any(axis=0), 10, 40)]
        for (cx0, cx1, lo, hi, own) in cells:
            x0, y0 = max(cx0 - 6, lo), max(ry0 - 6, 0)
            x1, y1 = min(cx1 + 6, hi), min(ry1 + 6, rgb.shape[0] - 1)
            block = rgb[y0:y1 + 1, x0:x1 + 1]
            bmin = minc[y0:y1 + 1, x0:x1 + 1]
            if own is not None:
                # Solo i pixel di questo gatto: il vicino, anche se la sua scatola si sovrappone, diventa sfondo.
                mine = own[y0:y1 + 1, x0:x1 + 1]
                block = np.where(mine[..., None], block, 255.0)
                bmin = np.where(mine, bmin, 255.0)
            h, w = bmin.shape

            # Sfondo = bianco raggiungibile dal bordo. Il bianco chiuso dal contorno (il petto, le zampe)
            # resta: è pelo bianco, non sfondo.
            cand = bmin >= BG_MIN
            border = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] \
                   + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
            if bridge:
                # Il bianco che passa solo da varchi stretti non conta come sfondo.
                core = flood(cand & ~dilate(~cand, bridge), border)
                bg = dilate(core, bridge) & cand
            else:
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

            if keep_main:
                # Il gatto è la parte più grande; i pezzi attaccati a lui (baffi, pesce) restano.
                near = dilate(fg, 2)
                best, best_size = None, 0
                seen = np.zeros_like(near)
                for py, px in zip(*np.where(near)):
                    if seen[py, px]:
                        continue
                    comp = flood(near & ~seen, [(py, px)], diagonal=True)
                    seen |= comp
                    if comp.sum() > best_size:
                        best, best_size = comp, comp.sum()
                fg &= best

            edge = fg & dilate(~fg, 2)
            soft = np.clip((255 - bmin) / 90.0, 0.0, 1.0)
            alpha = np.where(edge, soft, fg.astype(np.float32))
            a = np.maximum(alpha, 1e-3)[..., None]
            color = np.clip(np.where(edge[..., None], (block - 255.0 * (1 - a)) / a, block), 0, 255)
            rgba = np.dstack([color, alpha * 255]).astype(np.uint8)

            # Ancora orizzontale: il centro degli occhi (verde-giallo, ben distinto dal pelo).
            r, g, b = block[..., 0], block[..., 1], block[..., 2]
            eyes = fg & (g > 130) & (g >= r - 12) & (g - b > 50)
            ys, _ = np.where(fg)
            frame = dict(rgba=rgba, ground=float(ys.max()))
            if eyes.sum() >= 6:
                frame["ax"] = float(np.where(eyes)[1].mean())
            frames.append(frame)
    assert len(frames) == expected, f"{path}: attesi {expected} fotogrammi, trovati {len(frames)}"
    return frames


def lower_band(frame, ground, fraction=0.4):
    """La parte bassa del gatto (il corpo, non la testa né le zampe che si muovono): maschera e baricentro in x."""
    alpha = frame["rgba"][..., 3] > 128
    top = np.where(alpha.any(axis=1))[0][0]
    cut = int(ground - fraction * (ground - top))
    band = alpha.copy()
    band[:cut] = False
    return band


def silhouette_size(frame):
    ys, xs = np.where(frame["rgba"][..., 3] > 128)
    return float(xs.max() - xs.min()), float(ys.max() - ys.min())


def shift_for(ref_band, band, reach=24):
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
        cand = put(band, dx)
        score = int((ref & cand).sum())
        if score > best_score:
            best, best_score = dx, score
    return best


def load_extra(sheet):
    name, path, columns, expected, skip, split = sheet
    if not os.path.exists(path):
        print(f"{name}: {path} non c'è, salto")
        return None
    frames = load_sheet(path, expected, columns=columns, keep_main=True, split=split)
    return [f for i, f in enumerate(frames) if i not in skip]


def main():
    idle = load_sheet(IDLE, 1, bridge=8)[0]
    walk = load_sheet(WALK, 6, columns=3)
    assert idle.get("ax") is not None and all(f.get("ax") is not None for f in walk), "occhi non trovati"

    walk_w = np.median([silhouette_size(f)[0] for f in walk])
    walk_h = np.median([silhouette_size(f)[1] for f in walk])
    idle_w, idle_h = silhouette_size(idle)
    scale_w, scale_h = walk_w / idle_w, walk_h / idle_h
    idle_scale = (scale_w + scale_h) / 2
    print(f"scala del gatto fermo: {idle_scale:.3f}  (da larghezza {scale_w:.3f}, da altezza {scale_h:.3f})")

    # Riferimento per mettere gli altri fogli: il baricentro (in x) della parte bassa del corpo, rispetto agli occhi.
    walk_ground = float(np.median([f["ground"] for f in walk]))
    offsets = []
    for f in walk:
        band = lower_band(f, f["ground"])
        offsets.append(np.where(band)[1].mean() - f["ax"])
    body_offset = float(np.mean(offsets))

    items = []
    def add(frame, scale, ax, ground, label):
        img = Image.fromarray(frame["rgba"], "RGBA")
        if abs(scale - 1.0) > 1e-6:
            img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
        items.append(dict(img=img, ax=ax * scale, ground=ground * scale, label=label))

    add(idle, idle_scale, idle["ax"], idle["ground"], "fermo")
    for n, f in enumerate(walk, 1):
        add(f, 1.0, f["ax"], f["ground"], f"passo {n}")

    for sheet in EXTRA:
        frames = load_extra(sheet)
        if frames is None:
            continue
        name = sheet[0]
        scale = SCALE[name]
        print(f"{name}: scala {scale:.3f}")

        # Ridimensiono, poi sovrappongo i fotogrammi sul corpo (la parte bassa) del primo.
        scaled = []
        for f in frames:
            img = Image.fromarray(f["rgba"], "RGBA")
            img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)
            arr = np.asarray(img)
            ys = np.where((arr[..., 3] > 128).any(axis=1))[0]
            scaled.append(dict(rgba=arr, ground=float(ys.max())))
        ground = float(np.median([f["ground"] for f in scaled]))
        bands = [lower_band(f, f["ground"]) for f in scaled]
        ref = bands[0]
        ref_cx = float(np.where(ref)[1].mean())
        for f, band in zip(scaled, bands):
            dx = shift_for(ref, band)
            # Il punto di questo fotogramma che coincide con il baricentro del primo va dove sta il corpo
            # nella camminata (body_offset è la distanza fra il baricentro e gli occhi).
            ax = (ref_cx - dx) - body_offset
            items.append(dict(img=Image.fromarray(f["rgba"], "RGBA"), ax=ax, ground=ground, label=name))

    left = int(np.ceil(max(i["ax"] for i in items)))
    right = int(np.ceil(max(i["img"].width - i["ax"] for i in items)))
    up = int(np.ceil(max(i["ground"] for i in items)))
    down = int(np.ceil(max(i["img"].height - i["ground"] for i in items)))
    cw, ch = left + right + 2 * PAD, up + down + 2 * PAD
    print(f"formato comune: {cw}x{ch}  (zampe a riga {up + PAD}, {(down + PAD) / ch:.4f} dal fondo, "
          f"occhi a x={left + PAD} = {(left + PAD) / cw:.3f} della larghezza)")

    canvases = []
    for n, i in enumerate(items, 1):
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        canvas.paste(i["img"], (int(round(left + PAD - i["ax"])), int(round(up + PAD - i["ground"]))), i["img"])
        canvas.save(OUT.format(n))
        canvases.append(canvas)
    print(f"Scritti {len(items)} fotogrammi: assets/gattino/frame1.png ... frame{len(items)}.png")

    if "--preview" in sys.argv:
        cols = 6
        rows = (len(canvases) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * cw, rows * ch), (84, 110, 150, 255))
        for n, c in enumerate(canvases):
            sheet.alpha_composite(c, ((n % cols) * cw, (n // cols) * ch))
        sheet.convert("RGB").save(PREVIEW)
        print(f"Foglio di controllo: {PREVIEW}")


if __name__ == "__main__":
    main()
