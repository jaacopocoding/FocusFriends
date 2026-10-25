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
# i fogli della neve: le celle non hanno i bordi in comune (c'è uno spazio bianco fra una e l'altra) e, nel sentiero, non sono tutte uguali; per ogni
# tessera (nell'ordine in cui vanno) si dà la cella (sinistra, alto, destra, basso). Quelle troppo basse per farne un quadrato senza sgranare
# (la lastra con il ghiaccio, la neve sporca) si lasciano.
CELLS = [
    ("neve", [(x0, y0, x1, y1) for y0, y1 in ((0, 187), (193, 380), (386, 571)) for x0, x1 in ((5, 253), (260, 508), (515, 763), (771, 1019))]),
    ("sentiero_neve", [
        (5, 1, 253, 187),       # una lastra larga con la neve sopra
        (260, 0, 508, 283),     # lastre grigie
        (515, 0, 763, 187),     # ciottoli con la neve fra l'uno e l'altro
        (771, 1, 1019, 283),    # pietre irregolari, la neve nelle fessure
        (5, 387, 253, 571),     # lastre con i ciuffi secchi
        (260, 387, 508, 571),   # lastre con il ghiaccio
        (771, 387, 1019, 571),  # neve calpestata
        (515, 387, 763, 571),   # pietre scure con la neve fine (rara)
    ]),
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
    for name, cells in CELLS:
        sheet = Image.open(f"{DIR}/{name}_original.png").convert("RGB")
        for n, cell in enumerate(cells, start=1):
            square = square_from_cell(sheet, cell)
            diamond(square).save(f"{DIR}/tessera_{name}_{n}.png", optimize=True)
        print(f"{name}: {len(cells)} tessere (da {min(c[2] - c[0] for c in cells)} px di larghezza)")


if __name__ == "__main__":
    main()
