#!/usr/bin/env python3
"""Compone le immagini del focus della tartaruga: più passa il tempo, più si avvicina alla bandierina, lungo un sentiero di sassi: tre posizioni (la partenza, a metà strada, alla fragola).

    python3 tools/compose_tartaruga_growth.py [--preview]

Legge le pose già ritagliate (assets/tartaruga/frame*.png, da tools/cutout_tartaruga.py) e la tavola
assets/tartaruga/path_original.png (a sinistra la tartaruga, solo per la scala; cinque sassi; la bandierina; una fragola),
e scrive assets/garden/growth_tartaruga_1..3.png (come le carote del porcellino).

- I sassi e la bandierina stanno fermi in tutte le immagini: fanno da punto di riferimento, si vede quanta strada ha fatto.
- La tartaruga avanza a passi uguali, con un fotogramma diverso della camminata a ogni stadio. All'ultimo è il primo
  fotogramma di «mangia», con la fragola davanti al muso: a fine focus la mangia senza salti.
- La fragola, ferma davanti alla bandierina, è quella di quel fotogramma (non quella della tavola): così combacia.
- Nell'ultimo stadio la tartaruga sta al centro della tela, dove sta nelle pose di sempre: l'app disegna le immagini del
  focus centrate sulla finestra, e a fine focus, quando la finestra torna stretta, lei resta dov'era. Per questo la tela è
  larga il doppio della strada più una tartaruga, e a destra della bandierina resta dell'aria.
- Stessa altezza e stessa linea di terra delle pose: `focusGrowthFeetFraction` è quella di `groundFraction`.
"""
import importlib.util
import os
import sys

import numpy as np
from PIL import Image

DIR = "assets/tartaruga"
OUT = "assets/garden/growth_tartaruga_{}.png"
STAGES = 3
TRAVEL = 250            # px della tela delle pose: quanta strada fa dal primo all'ultimo stadio
STONE_SCALE = 0.62      # i sassi della tavola sono grandi per la tartaruga: un po' più piccoli
STONE_GAP = 7           # aria fra un sasso e l'altro
STONE_SINK = 9          # di quanto i sassi scendono sotto la linea dei piedi (la tartaruga ci cammina sopra)
FLAG_GAP = 6            # fra la fragola e il bastone della bandierina
GROUND_PAD = 26         # come in cutout_tartaruga.py
PREVIEW = "--preview" in sys.argv

spec = importlib.util.spec_from_file_location("cutout", os.path.join(os.path.dirname(__file__), "cutout_tartaruga.py"))
cutout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cutout)


def pieces(path):
    """I disegni staccati della tavola, da sinistra a destra, in RGBA (sfondo bianco tolto come nelle pose)."""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    minc = rgb.min(axis=2)
    h, w = minc.shape
    # le macchie di colore, un po' allargate perché un disegno (la bandierina e il suo ciuffo d'erba) resti tutto insieme
    blob = cutout.dilate(minc < 235, 4)
    seen = np.zeros_like(blob)
    found = []
    for y, x in zip(*np.where(blob)):
        if seen[y, x]:
            continue
        comp = cutout.flood(blob & ~seen, [(y, x)], diagonal=True)
        seen |= comp
        if comp.sum() < 400:
            continue
        ys, xs = np.where(comp)
        found.append((int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()), comp))
    out = []
    for x0, y0, x1, y1, comp in sorted(found, key=lambda f: f[:4]):
        block = rgb[y0:y1 + 1, x0:x1 + 1]
        bmin = minc[y0:y1 + 1, x0:x1 + 1]
        bh, bw = bmin.shape
        border = [(0, i) for i in range(bw)] + [(bh - 1, i) for i in range(bw)] + [(i, 0) for i in range(bh)] + [(i, bw - 1) for i in range(bh)]
        # solo questo disegno: nel suo rettangolo può entrare un pezzo del sasso accanto
        fg = ~cutout.flood(bmin >= cutout.BG_MIN, border) & comp[y0:y1 + 1, x0:x1 + 1]
        edge = fg & cutout.dilate(~fg, 2)
        soft = np.clip((255 - bmin) / 90.0, 0.0, 1.0)
        alpha = np.where(edge, soft, fg.astype(np.float32))
        a = np.maximum(alpha, 1e-3)[..., None]
        color = np.clip(np.where(edge[..., None], (block - 255.0 * (1 - a)) / a, block), 0, 255)
        img = Image.fromarray(np.dstack([color, alpha * 255]).astype(np.uint8), "RGBA")
        out.append(img.crop(img.getbbox()))
    return out


def is_red(img):
    a = np.asarray(img).astype(int)
    solid = a[..., 3] > 128
    red = solid & (a[..., 0] > 170) & (a[..., 1] < 110) & (a[..., 2] < 110)
    return red.sum() > 0.05 * solid.sum()


def strawberry_box(frame):
    """Dove sta la fragola nel primo fotogramma di «mangia»: il rosso a destra del guscio."""
    a = np.asarray(frame).astype(int)
    solid = a[..., 3] > 128
    red = solid & (a[..., 0] > 170) & (a[..., 1] < 110) & (a[..., 2] < 110)
    left, right = cutout.shell_span(a.astype(np.uint8))
    red[:, : int(right)] = False
    ys, xs = np.where(red)
    # con le foglie: allargo un po' il rettangolo del rosso
    return int(xs.min()) - 6, int(ys.min()) - 14, int(xs.max()) + 12, int(ys.max()) + 2


def main():
    poses = [Image.open(os.path.join(DIR, f"frame{i}.png")).convert("RGBA") for i in range(1, 24)]
    W, H = poses[0].size
    ground = H - GROUND_PAD - 1

    parts = pieces(os.path.join(DIR, "path_original.png"))
    turtle, rest = parts[0], parts[1:]
    flag = next(p for p in rest if is_red(p) and p.height > p.width * 1.5)
    stones = [p for p in rest if not is_red(p)]
    print(f"tavola: {len(stones)} sassi, bandierina {flag.size}")
    assert len(stones) == 5, "attesi cinque sassi"

    # la scala della tavola: il guscio della tartaruga largo come nella camminata
    ref_left, ref_right = cutout.shell_span(np.asarray(poses[1]))
    t_left, t_right = cutout.shell_span(np.asarray(turtle))
    k = (ref_right - ref_left) / (t_right - t_left)
    print(f"scala della tavola: {k:.3f}")

    def scaled(img, f):
        return img.resize((max(1, round(img.width * f)), max(1, round(img.height * f))), Image.LANCZOS)

    flag = scaled(flag, k)
    stones = [scaled(s, k * STONE_SCALE) for s in stones]

    # la tela: l'ultimo stadio al centro, la strada a sinistra, e altrettanto a destra
    half = TRAVEL + W / 2
    CW = int(round(2 * half))
    final_x = int(round(half - W / 2))          # dove va la tela delle pose all'ultimo stadio

    eat = poses[7]
    sx0, sy0, sx1, sy1 = strawberry_box(eat)
    straw = eat.crop((sx0, sy0, sx1, sy1))
    straw_x = final_x + sx0
    flag_x = final_x + sx1 + FLAG_GAP              # il bastone subito dopo la fragola
    assert flag_x + flag.width <= CW, "la bandierina non ci sta: allunga TRAVEL"

    # i sassi: dal muso della tartaruga al primo stadio fino alla fragola, distribuiti in fila
    start_nose = final_x - TRAVEL + W * 0.80
    span = straw_x - start_nose
    total = sum(s.width for s in stones) + STONE_GAP * (len(stones) - 1)
    order = [0, 3, 1, 4, 2]                        # alterna quelli grandi e quelli piccoli
    gap = STONE_GAP + max(0.0, (span - total) / (len(stones) - 1))
    x = start_nose - (total - span) / 2 if total > span else start_nose
    placed = []
    for i in order:
        s = stones[i]
        placed.append((s, int(round(x)), ground + STONE_SINK - s.height))
        x += s.width + gap

    def background():
        canvas = Image.new("RGBA", (CW, H), (255, 255, 255, 0))
        for s, sx, sy in placed:
            canvas.alpha_composite(s, (sx, sy))
        canvas.alpha_composite(flag, (flag_x, ground + 4 - flag.height))
        return canvas

    walk = poses[1:7]
    out = []
    for stage in range(STAGES):
        canvas = background()
        last = stage == STAGES - 1
        if not last:
            canvas.alpha_composite(straw, (straw_x, sy0))
        pose = eat if last else walk[stage % len(walk)]
        dx = final_x - round(TRAVEL * (STAGES - 1 - stage) / (STAGES - 1))
        canvas.alpha_composite(pose, (dx, 0)) if dx >= 0 else canvas.paste(pose, (dx, 0), pose)
        canvas.save(OUT.format(stage + 1))
        out.append(canvas)
    print(f"scritte {STAGES} immagini {CW}x{H} (le pose: {W}x{H}), piedi a {GROUND_PAD / H:.4f} dal fondo")

    if PREVIEW:
        os.makedirs("build", exist_ok=True)
        sheet = Image.new("RGB", (CW, H * STAGES), (214, 232, 204))
        for i, im in enumerate(out):
            sheet.paste(im, (0, i * H), im)
        sheet.save("build/tartaruga-crescita.png")
        print("anteprima in build/tartaruga-crescita.png")


if __name__ == "__main__":
    main()
