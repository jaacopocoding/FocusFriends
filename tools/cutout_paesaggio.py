#!/usr/bin/env python3
"""Ritaglia gli elementi del paesaggio: assets/giardino/paesaggio_original.png (su fondo magenta #FF00FF) -> assets/giardino/paesaggio_<nome>.png

Dodici elementi sparsi sul foglio (non in una griglia): si trovano guardando i pezzi staccati (l'elemento fatto di più parti, come lo steccato o il
tronco con il ceppo, si riunisce) e si riconoscono dalla posizione sul foglio. Il fondo si toglie come per gli oggetti del giardino
(tools/cutout_giardino.py: stessa funzione).

Uso, dalla cartella principale:  python3 tools/cutout_paesaggio.py
"""
import importlib.util
import numpy as np
from PIL import Image

DIR = "assets/giardino"
# nome, dove sta il suo centro sul foglio (1024x572) più o meno
ITEMS = [
    ("casale", (210, 125)), ("albero-tondo", (670, 120)), ("albero-alto", (895, 120)), ("albero-piccolo", (125, 325)),
    ("abete-grande", (480, 285)), ("abete-piccolo", (685, 320)), ("cespuglio-grande", (900, 320)),
    ("cespuglio-piccolo", (115, 490)), ("siepe-arancio", (320, 485)), ("siepe-rosa", (510, 485)), ("steccato", (705, 495)), ("tronchi", (905, 495)),
]


def load_garden_tools():
    spec = importlib.util.spec_from_file_location("cutout_giardino", "tools/cutout_giardino.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def components(mask):
    """Gruppi di pixel pieni vicini (anche a una ventina di pixel di distanza): [(maschera, centro)]."""
    garden = load_garden_tools()
    joined = garden.dilate(mask, 12)
    seen = np.zeros(mask.shape, dtype=bool)
    groups = []
    for y, x in zip(*np.where(joined)):
        if seen[y, x]:
            continue
        region = garden.flood(joined, [(y, x)], diagonal=True)
        seen |= region
        if region.sum() > 400:
            ys, xs = np.where(region & mask)
            groups.append((region, (xs.mean(), ys.mean())))
    return groups


def main():
    garden = load_garden_tools()
    rgb = np.asarray(Image.open(f"{DIR}/paesaggio_original.png").convert("RGB")).astype(np.float32)
    rgba = garden.magenta_object(rgb)
    groups = components(rgba[..., 3] > 25)
    print(f"{len(groups)} gruppi trovati")
    used = set()
    for name, (cx, cy) in ITEMS:
        best = min((i for i in range(len(groups)) if i not in used), key=lambda i: (groups[i][1][0] - cx) ** 2 + (groups[i][1][1] - cy) ** 2)
        used.add(best)
        region = groups[best][0]
        piece = np.where(region[..., None], rgba, 0).astype(np.uint8)
        piece = garden.crop(piece)
        Image.fromarray(piece, "RGBA").save(f"{DIR}/paesaggio_{name}.png", optimize=True)
        print(f"{name}: {piece.shape[1]}x{piece.shape[0]} (centro {groups[best][1][0]:.0f},{groups[best][1][1]:.0f})")


if __name__ == "__main__":
    main()
