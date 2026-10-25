#!/usr/bin/env python3
"""Taglia i fogli di texture del terreno dell'isola e li trasforma in tessere a rombo.

Gemini disegna quadrati visti dall'alto (assets/giardino/<nome>_original.png, una griglia di celle con un contorno scuro intorno a ognuna);
qui si ritaglia il centro di ogni cella (fuori dal contorno), si fa quadrato e si schiaccia in un rombo 2:1, come lo vede l'isola:
l'angolo in alto a sinistra del quadrato va al vertice in alto del rombo, quello in alto a destra al vertice destro, quello in basso a
sinistra al vertice sinistro (le colonne della tessera vanno verso destra e in basso, le righe verso sinistra e in basso).

Scrive assets/giardino/tessera_<nome>_<n>.png (320x160, RGBA, bordi del rombo sfumati); build.sh le copia come giardino_tessera_<nome>_<n>.png.

Uso, dalla cartella principale:  python3 tools/cutout_tessere.py
"""
import numpy as np
from PIL import Image, ImageDraw

DIR = "assets/giardino"
TILE_W, TILE_H = 320, 160
# nome del foglio, bordi delle colonne e delle righe (in pixel, dentro il contorno della griglia di Gemini), quante piastrelle
SHEETS = [
    ("erba", [50, 281, 513, 744, 975], [14, 193, 376, 558], 12),
    ("sentiero", [50, 282, 512, 742, 973], [14, 285, 557], 8),
]
INSET = 10   # via il contorno scuro e un po' di margine


def square_from_cell(image, box):
    left, top, right, bottom = box
    left, top, right, bottom = left + INSET, top + INSET, right - INSET, bottom - INSET
    side = min(right - left, bottom - top)
    cx, cy = (left + right) // 2, (top + bottom) // 2
    return image.crop((cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side))


def diamond(square, width=TILE_W, height=TILE_H):
    """Il quadrato (vista dall'alto) messo a rombo, con i bordi sfumati."""
    scale = 2
    w, h = width * scale, height * scale
    s = square.width
    # dal rombo (x, y) al quadrato (u, v): u = x/w + y/h - 1/2, v = y/h - x/w + 1/2
    coeffs = (s / w, s / h, -0.5 * s, -s / w, s / h, 0.5 * s)
    warped = square.convert("RGBA").transform((w, h), Image.AFFINE, coeffs, resample=Image.BICUBIC)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon([(w / 2, 0), (w, h / 2), (w / 2, h), (0, h / 2)], fill=255)
    warped.putalpha(mask)
    premultiplied = warped.convert("RGBa").resize((width, height), Image.LANCZOS)
    return premultiplied.convert("RGBA")


def main():
    for name, xs, ys, count in SHEETS:
        sheet = Image.open(f"{DIR}/{name}_original.png").convert("RGB")
        n = 0
        for row in range(len(ys) - 1):
            for col in range(len(xs) - 1):
                n += 1
                if n > count:
                    break
                square = square_from_cell(sheet, (xs[col], ys[row], xs[col + 1], ys[row + 1]))
                diamond(square).save(f"{DIR}/tessera_{name}_{n}.png", optimize=True)
        print(f"{name}: {n} tessere ({square.width}x{square.height} px ciascuna prima di mettere a rombo)")


if __name__ == "__main__":
    main()
