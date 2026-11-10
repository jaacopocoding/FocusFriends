#!/usr/bin/env python3
"""Ritaglia gli animali ospiti del giardino: assets/giardino/visitatori_original.png -> assets/giardino/visitatore_<nome>.png

Il foglio ha 12 animaletti (4 colonne per 3 righe, in ordine di lettura, ognuno nella sua cella) su fondo magenta #FF00FF, visti di tre quarti e rivolti
a destra: riccio (non più usato), pettirosso, coniglio, volpe, scoiattolo, rana, civetta, tartaruga (non più usata), topolino, cinciallegra, anatroccolo, lucertola.
Il fondo si toglie come per gli oggetti del giardino (tools/ritagli/cutout_giardino.py: stessa funzione). Gli animali non stanno per forza dentro la loro cella (la coda della
volpe scende in quella sotto): si cercano i pezzi staccati (come per il paesaggio, tools/ritagli/cutout_paesaggio.py) e ognuno va all'animale della cella più vicina al suo centro.

Uso, dalla cartella principale:  python3 tools/ritagli/cutout_visitatori.py
"""
import importlib.util
import numpy as np
from PIL import Image

DIR = "assets/giardino"
COLUMNS, ROWS = 4, 3
# Il riccio e la tartaruga del foglio non ci sono più fra gli ospiti (sono diventati compagni): le loro celle si saltano. La lumaca e la lepre hanno preso
# il loro posto, disegnate a parte.
RETIRED = {"riccio", "tartaruga"}
EXTRAS = ["lumaca", "lepre"]
NAMES = ["riccio", "pettirosso", "coniglio", "volpe", "scoiattolo", "rana", "civetta", "tartaruga", "topolino", "cinciallegra", "anatroccolo", "lucertola"]


def load_garden_tools():
    spec = importlib.util.spec_from_file_location("cutout_giardino", "tools/ritagli/cutout_giardino.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_tool(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    garden = load_tool("tools/ritagli/cutout_giardino.py", "cutout_giardino")
    scenery = load_tool("tools/ritagli/cutout_paesaggio.py", "cutout_paesaggio")
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
        if name in RETIRED:
            continue
        Image.fromarray(piece, "RGBA").save(f"{DIR}/visitatore_{name}.png", optimize=True)
        print(f"visitatore_{name}: {piece.shape[1]}x{piece.shape[0]}")
    # Gli ospiti disegnati a parte, uno per foglio (<nome>_original.png, su fondo magenta).
    for name in EXTRAS:
        single = np.asarray(Image.open(f"{DIR}/{name}_original.png").convert("RGB")).astype(np.float32)
        rgba = garden.magenta_object(single)
        piece = garden.crop(rgba.astype(np.uint8))
        image = Image.fromarray(piece, "RGBA")
        longest = max(image.size)
        if longest > 260:      # com'è il foglio degli altri ospiti (circa 200 pixel): niente disegni cinque volte più grandi
            image = image.resize((round(image.width * 260 / longest), round(image.height * 260 / longest)), Image.LANCZOS)
        image.save(f"{DIR}/visitatore_{name}.png", optimize=True)
        print(f"visitatore_{name}: {image.width}x{image.height}")


if __name__ == "__main__":
    main()
