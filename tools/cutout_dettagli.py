#!/usr/bin/env python3
"""Ritaglia i dettagli da spargere sul terreno dell'isola: assets/giardino/dettagli_original.png -> assets/giardino/dettaglio_<n>.png

Il foglio ha 24 piccoli elementi (6 colonne per 4 righe, in ordine di lettura, ognuno nella sua cella) su fondo magenta #FF00FF:
  1-4 ciuffi d'erba   5-6 trifogli   7-10 fiorellini (bianco, rosa, giallo, azzurro)   11-13 sassi   14-17 foglie cadute (arancio, rossa, gialla, marrone)
  18-20 petali caduti   21-24 ciuffi di neve e ghiaccio
Il fondo si toglie come per gli oggetti del giardino (tools/cutout_giardino.py: stessa funzione); ogni immagine si ritaglia sul contenuto.
L'app sa quali numeri sono ciuffi, fiori, sassi… (GardenDecalGroup in GardenGrid.swift).

Uso, dalla cartella principale:  python3 tools/cutout_dettagli.py
"""
import importlib.util
import numpy as np
from PIL import Image

DIR = "assets/giardino"
COLUMNS, ROWS = 6, 4


def load_garden_tools():
    spec = importlib.util.spec_from_file_location("cutout_giardino", "tools/cutout_giardino.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    garden = load_garden_tools()
    sheet = np.asarray(Image.open(f"{DIR}/dettagli_original.png").convert("RGB")).astype(np.float32)
    height, width = sheet.shape[:2]
    n = 0
    for row in range(ROWS):
        for col in range(COLUMNS):
            n += 1
            cell = sheet[row * height // ROWS:(row + 1) * height // ROWS, col * width // COLUMNS:(col + 1) * width // COLUMNS]
            rgba = garden.crop(garden.magenta_object(cell))
            Image.fromarray(rgba, "RGBA").save(f"{DIR}/dettaglio_{n}.png", optimize=True)
            print(f"dettaglio_{n}: {rgba.shape[1]}x{rgba.shape[0]}")


if __name__ == "__main__":
    main()
