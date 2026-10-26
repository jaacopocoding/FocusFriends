#!/usr/bin/env python3
"""Ritaglia gli animali ospiti del giardino: assets/giardino/visitatori_original.png -> assets/giardino/visitatore_<nome>.png

Il foglio ha 12 animaletti (4 colonne per 3 righe, in ordine di lettura, ognuno nella sua cella) su fondo magenta #FF00FF, visti di tre quarti e rivolti
a destra: riccio, pettirosso, coniglio, volpe, scoiattolo, rana, civetta, tartaruga, topolino, cinciallegra, anatroccolo, lucertola.
Il fondo si toglie come per gli oggetti del giardino (tools/cutout_giardino.py: stessa funzione). Gli animali non stanno per forza dentro la loro cella (la coda della
volpe scende in quella sotto): si cercano i pezzi staccati (come per il paesaggio, tools/cutout_paesaggio.py) e ognuno va all'animale della cella più vicina al suo centro.

Uso, dalla cartella principale:  python3 tools/cutout_visitatori.py
"""
import importlib.util
import numpy as np
from PIL import Image

DIR = "assets/giardino"
COLUMNS, ROWS = 4, 3
NAMES = ["riccio", "pettirosso", "coniglio", "volpe", "scoiattolo", "rana", "civetta", "tartaruga", "topolino", "cinciallegra", "anatroccolo", "lucertola"]


def load_garden_tools():
    spec = importlib.util.spec_from_file_location("cutout_giardino", "tools/cutout_giardino.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_tool(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    garden = load_tool("tools/cutout_giardino.py", "cutout_giardino")
    scenery = load_tool("tools/cutout_paesaggio.py", "cutout_paesaggio")
    sheet = np.asarray(Image.open(f"{DIR}/visitatori_original.png").convert("RGB")).astype(np.float32)
    height, width = sheet.shape[:2]
    rgba = garden.magenta_object(sheet)
    groups = scenery.components(rgba[..., 3] > 25, 4)
    print(f"{len(groups)} gruppi trovati")
    used = set()
    for n, name in enumerate(NAMES):
        cx, cy = (n % COLUMNS + 0.5) * width / COLUMNS, (n // COLUMNS + 0.5) * height / ROWS
        best = min((i for i in range(len(groups)) if i not in used), key=lambda i: (groups[i][1][0] - cx) ** 2 + (groups[i][1][1] - cy) ** 2)
        used.add(best)
        piece = garden.crop(np.where(groups[best][0][..., None], rgba, 0).astype(np.uint8))
        Image.fromarray(piece, "RGBA").save(f"{DIR}/visitatore_{name}.png", optimize=True)
        print(f"visitatore_{name}: {piece.shape[1]}x{piece.shape[0]}")


if __name__ == "__main__":
    main()
