#!/usr/bin/env python3
"""Prepara lo sfondo del giardino: assets/giardino/sfondo_original.png (il paesaggio di Gemini, 1024x506) -> assets/giardino/sfondo.png (2048x1012)
(e, d'inverno, sfondo_inverno_original.png -> sfondo_inverno.png: il lago ghiacciato, senza isola da ricoprire, con il casale e gli alberi innevati)

1. Si ingrandisce 2x con una buona interpolazione (come il vecchio prato).
2. Sul lago Gemini ha disegnato una piccola isola: la nostra isola ci sta sopra, ma rimpicciolendo si vedrebbero due isole. Si ricopre con l'acqua
   (presa dall'acqua sotto) e con le colline (prese da sopra), sfumando i bordi.
3. Sulle rive lontane si mettono il casale, gli alberi e gli abeti ritagliati da tools/cutout_paesaggio.py, un po' sfocati e schiariti come le cose
   lontane. La posizione del camino e delle finestre del casale si stampa: serve all'app (MeadowBackdrop) per il fumo e la luce di sera.

Uso, dalla cartella principale:  python3 tools/cutout_paesaggio.py && python3 tools/prepara_sfondo.py
"""
import numpy as np
from PIL import Image, ImageFilter

DIR = "assets/giardino"
K = 2   # ingrandimento

# (nome, base al centro (x, y) sull'immagine da 1024x506, altezza o larghezza, "h" o "w")
SCENERY = [
    ("abete-grande", (884, 216), 82, "h"), ("abete-piccolo", (924, 221), 56, "h"), ("albero-alto", (846, 225), 66, "h"),
    ("cespuglio-grande", (905, 233), 46, "w"), ("cespuglio-piccolo", (806, 239), 42, "w"),
    ("albero-tondo", (190, 219), 54, "h"), ("albero-piccolo", (66, 236), 42, "h"),
    ("casale", (122, 218), 100, "w"),
]
HAZE = (206, 216, 226)     # le cose lontane si schiariscono verso il cielo
HAZE_AMOUNT = 0.14
# nel casale (349x223): bocca del camino e finestre accese di sera
CHIMNEY = (226, 12)
WINDOWS = [(78, 94), (147, 152), (200, 154), (269, 92)]

# lo sfondo d'inverno: il casale e gli alberi innevati (ritagliati da paesaggio_inverno_original.png) sulle due rive; le cose più grandi, perché la
# neve le schiarisce. Il camino e le finestre accese (gialle, già nel disegno) si trovano guardando il casale ritagliato.
WINTER_SCENERY = [
    ("albero-alto", (752, 232), 70, "h"), ("abete-grande", (798, 229), 86, "h"), ("abete-piccolo", (838, 235), 60, "h"),
    ("cespuglio-grande", (868, 246), 46, "w"), ("cespuglio-rado", (722, 234), 42, "w"),
    ("albero-tondo", (206, 233), 56, "h"), ("albero-piccolo", (62, 246), 42, "h"), ("cespuglio-piccolo", (172, 240), 30, "w"),
    ("casale", (118, 228), 100, "w"),
]


# la sagoma della piccola isola del lago, sull'immagine da 1024x506 (la parte di sopra, poi la parte di sotto tornando indietro)
ISLET = [(200, 314), (255, 288), (330, 262), (420, 238), (520, 244), (610, 246), (700, 260), (780, 284), (840, 314),
         (780, 338), (640, 350), (520, 351), (400, 349), (290, 338)]


def polygon_mask(shape, points, grow):
    from PIL import ImageDraw
    image = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(image).polygon([(x * K, y * K) for x, y in points], fill=255)
    if grow:
        image = image.filter(ImageFilter.MaxFilter(grow * 2 + 1))
    return np.asarray(image) > 127


def harmonic_fill(arr, mask):
    """Riempie la zona `mask` con una media liscia dei colori che la circondano (si risolve prima in piccolo e poi si raffina)."""
    ys, xs = np.where(mask)
    y0, y1, x0, x1 = ys.min() - 3, ys.max() + 4, xs.min() - 3, xs.max() + 4
    region = arr[y0:y1, x0:x1].copy()
    box_mask = mask[y0:y1, x0:x1]
    # i pixel noti attorno alla zona: la guess iniziale sono loro, sfocati e stesi
    def solve(levels):
        guess = None
        for level in range(levels, -1, -1):
            f = 2 ** level
            h, w = (region.shape[0] + f - 1) // f, (region.shape[1] + f - 1) // f
            small = np.asarray(Image.fromarray(region.clip(0, 255).astype(np.uint8)).resize((w, h), Image.BOX)).astype(np.float32)
            small_mask = np.asarray(Image.fromarray((box_mask * 255).astype(np.uint8)).resize((w, h), Image.BOX)) > 40
            if guess is None:
                value = small.copy()
                value[small_mask] = small[~small_mask].mean(axis=0)
            else:
                value = np.asarray(Image.fromarray(guess.clip(0, 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)).astype(np.float32)
                value[~small_mask] = small[~small_mask]
            for _ in range(400 if level else 250):
                padded = np.pad(value, ((1, 1), (1, 1), (0, 0)), mode="edge")
                average = (padded[:-2, 1:-1] + padded[2:, 1:-1] + padded[1:-1, :-2] + padded[1:-1, 2:]) / 4
                value[small_mask] = average[small_mask]
            guess = value
        return guess
    filled = solve(4)
    out = arr.copy()
    out[y0:y1, x0:x1][box_mask] = filled[box_mask]
    return out


def cover_islet(canvas):
    """Ricopre la piccola isola del lago con una sfumatura liscia presa dai colori attorno (acqua ai lati e sotto, colline sopra): l'acqua è un acquerello
    quasi piatto, e dietro la nostra isola non si nota."""
    arr = np.asarray(canvas).astype(np.float32)
    mask = polygon_mask(arr.shape[:2], ISLET, 7 * K)
    out = harmonic_fill(arr, mask)
    soft = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5 * K))).astype(np.float32) / 255
    blended = arr * (1 - soft[..., None]) + out * soft[..., None]
    return Image.fromarray(blended.clip(0, 255).astype(np.uint8), "RGB")


def place(canvas, sprite_name, base, size, along, sheet="paesaggio"):
    sprite = Image.open(f"{DIR}/{sheet}_{sprite_name}.png").convert("RGBA")
    scale = size * K / (sprite.height if along == "h" else sprite.width)
    sprite = sprite.resize((max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))), Image.LANCZOS)
    # sfocato e schiarito, come le cose lontane
    alpha = sprite.split()[3]
    rgb = sprite.convert("RGB").filter(ImageFilter.GaussianBlur(0.7))
    haze = Image.new("RGB", rgb.size, HAZE)
    rgb = Image.blend(rgb, haze, HAZE_AMOUNT)
    sprite = Image.merge("RGBA", (*rgb.split(), alpha))
    left, top = round(base[0] * K - sprite.width / 2), round(base[1] * K - sprite.height)
    canvas.alpha_composite(sprite, (left, top)) if canvas.mode == "RGBA" else canvas.paste(sprite, (left, top), sprite)
    return left, top, scale


def house_marks(sprite_name="casale", sheet="paesaggio_inverno"):
    """La bocca del camino e il centro di ogni finestra accesa nel casale ritagliato (in pixel del ritaglio): il camino è il punto più alto del
    casale, le finestre sono le macchie gialle."""
    sprite = np.asarray(Image.open(f"{DIR}/{sheet}_{sprite_name}.png").convert("RGBA")).astype(np.float32)
    alpha = sprite[..., 3] > 128
    ys, xs = np.where(alpha)
    top = ys.min()
    chimney = (float(xs[ys <= top + 2].mean()), float(top + 5))
    r, g, b = sprite[..., 0], sprite[..., 1], sprite[..., 2]
    yellow = alpha & (r > 215) & (g > 165) & (b < 140) & (r - b > 90)
    # i vetri sono divisi dai montanti: si uniscono le macchie vicine (un vetro è una sola finestra)
    joined = np.asarray(Image.fromarray((yellow * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))) > 127
    windows = []
    seen = np.zeros(yellow.shape, dtype=bool)
    for y, x in zip(*np.where(joined)):
        if seen[y, x]:
            continue
        stack, blob = [(y, x)], []
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            blob.append((cy, cx))
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < joined.shape[0] and 0 <= nx < joined.shape[1] and joined[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        pixels = [(py, px) for py, px in blob if yellow[py, px]]
        if len(pixels) >= 30:
            windows.append((float(np.mean([q[1] for q in pixels])), float(np.mean([q[0] for q in pixels]))))
    return chimney, sorted(windows)


def compose(name, original, scenery, sheet, cover):
    original = Image.open(f"{DIR}/{original}").convert("RGB")
    canvas = original.resize((original.width * K, original.height * K), Image.LANCZOS)
    if cover:
        canvas = cover_islet(canvas)
    house = None
    for sprite, base, size, along in scenery:
        left, top, scale = place(canvas, sprite, base, size, along, sheet)
        if sprite == "casale":
            house = (left, top, scale)
    canvas.save(f"{DIR}/{name}", optimize=True)
    print(f"{name}: {canvas.size[0]}x{canvas.size[1]}")
    return canvas.size, house


def main():
    (w, h), (left, top, scale) = compose("sfondo.png", "sfondo_original.png", SCENERY, "paesaggio", True)
    print("camino   u=%.4f v=%.4f" % ((left + CHIMNEY[0] * scale) / w, (top + CHIMNEY[1] * scale) / h))
    for window in WINDOWS:
        print("finestra u=%.4f v=%.4f" % ((left + window[0] * scale) / w, (top + window[1] * scale) / h))
    print("casale largo (in punti della scena, circa): %.0f" % (349 * scale / K * 2.371 / 2))
    print()
    (w, h), (left, top, scale) = compose("sfondo_inverno.png", "sfondo_inverno_original.png", WINTER_SCENERY, "paesaggio_inverno", False)
    chimney, windows = house_marks()
    print("inverno, camino   u=%.4f v=%.4f" % ((left + chimney[0] * scale) / w, (top + chimney[1] * scale) / h))
    for window in windows:
        print("inverno, finestra u=%.4f v=%.4f" % ((left + window[0] * scale) / w, (top + window[1] * scale) / h))
    sprite_width = Image.open(f"{DIR}/paesaggio_inverno_casale.png").width
    print("inverno, casale largo (in punti della scena, circa): %.0f" % (sprite_width * scale / K * 2.371 / 2))


if __name__ == "__main__":
    main()
