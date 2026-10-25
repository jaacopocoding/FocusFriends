#!/usr/bin/env python3
"""Ritaglia le immagini dell'album: assets/album/<nome>_original.png (su fondo magenta #FF00FF) -> assets/album/<nome>.png

- copertina: la copertina del libro (vista frontale, con la targa vuota dove l'app scrive il titolo); si ritaglia sul contenuto.
- doppia_pagina: il libro aperto con le pagine vuote (fasce per i titoli, sei aree per pagina, un posto per il numero). NON si ritaglia: l'app
  conosce le posizioni delle aree come frazioni dell'immagine intera, quindi la tela deve restare quella di Gemini.
Il fondo magenta si toglie come per gli oggetti del giardino (tools/cutout_giardino.py: stessa funzione, che ripulisce anche il rosa sui contorni).

Uso, dalla cartella principale:  python3 tools/cutout_album.py
"""
import importlib.util
import numpy as np
from PIL import Image

DIR = "assets/album"
# (nome, ritagliare sul contenuto?)
SHEETS = [("copertina", True), ("doppia_pagina", False)]


def load_garden_tools():
    spec = importlib.util.spec_from_file_location("cutout_giardino", "tools/cutout_giardino.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    garden = load_garden_tools()
    for name, crop in SHEETS:
        rgb = np.asarray(Image.open(f"{DIR}/{name}_original.png").convert("RGB")).astype(np.float32)
        rgba = garden.magenta_object(rgb)
        if crop:
            ys, xs = np.where(rgba[..., 3] > 25)
            rgba = rgba[max(ys.min() - 2, 0):ys.max() + 3, max(xs.min() - 2, 0):xs.max() + 3]
        image = Image.fromarray(rgba, "RGBA")
        image.save(f"{DIR}/{name}.png", optimize=True)
        print(f"{name}: {image.width}x{image.height}")


if __name__ == "__main__":
    main()
