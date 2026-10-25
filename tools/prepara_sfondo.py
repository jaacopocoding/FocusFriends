#!/usr/bin/env python3
"""Prepara lo sfondo del giardino: assets/giardino/sfondo_original.png (il paesaggio di Gemini, 1024x506) -> assets/giardino/sfondo.png (2048x1012)

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


def place(canvas, sprite_name, base, size, along):
    sprite = Image.open(f"{DIR}/paesaggio_{sprite_name}.png").convert("RGBA")
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


def main():
    original = Image.open(f"{DIR}/sfondo_original.png").convert("RGB")
    canvas = original.resize((original.width * K, original.height * K), Image.LANCZOS)
    canvas = cover_islet(canvas)
    house = None
    for name, base, size, along in SCENERY:
        left, top, scale = place(canvas, name, base, size, along)
        if name == "casale":
            house = (left, top, scale)
    canvas.save(f"{DIR}/sfondo.png", optimize=True)
    w, h = canvas.size
    left, top, scale = house
    print(f"sfondo.png: {w}x{h}")
    print("camino   u=%.4f v=%.4f" % ((left + CHIMNEY[0] * scale) / w, (top + CHIMNEY[1] * scale) / h))
    for window in WINDOWS:
        print("finestra u=%.4f v=%.4f" % ((left + window[0] * scale) / w, (top + window[1] * scale) / h))
    print("casale largo (in punti della scena, circa): %.0f" % (349 * scale / K * 2.371 / 2))


if __name__ == "__main__":
    main()
