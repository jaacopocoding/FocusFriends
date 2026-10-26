#!/usr/bin/env python3
"""Ritaglia le case delle isole: assets/giardino/casa_<isola>_original.png -> assets/giardino/casa_<isola>.png

Ogni isola ha la sua casa (3×3 tessere), un disegno solo su fondo magenta #FF00FF, in prospettiva isometrica, appoggiata a uno zoccolo a rombo che
riempie la base. Il fondo si toglie come per gli oggetti del giardino (tools/cutout_giardino.py: stessa funzione) e si toglie il rosa che resta fra le
cose. Dello zoccolo si stampano le misure (centro del rombo, mezza larghezza, mezza altezza, in pixel del disegno ritagliato): sono quelle di
`GardenLandmarks.art` in Sources/FocusFriends/GardenGrid.swift, che servono a incastrare lo zoccolo sulle 3×3 tessere.

Uso, dalla cartella principale:  python3 tools/cutout_case.py
"""
import importlib.util
import os
import numpy as np
from PIL import Image

DIR = "assets/giardino"
ISLANDS = ["pianty", "porcellino", "ciccio", "gattino"]


def load_tool(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def remove_pink(rgba):
    r, g, b = (rgba[..., i].astype(np.float32) for i in range(3))
    magenta = np.minimum(r, b) - g
    out = rgba.copy()
    out[..., 3] = np.where(magenta > 40, 0, out[..., 3])
    soft = (magenta > 14) & (magenta <= 40)
    spill = np.maximum(0, np.minimum(r, b) - g)
    out[..., 0] = np.where(soft, np.clip(r - spill * 0.8, 0, 255), out[..., 0])
    out[..., 2] = np.where(soft, np.clip(b - spill * 0.8, 0, 255), out[..., 2])
    return out


def main():
    garden = load_tool("tools/cutout_giardino.py", "cutout_giardino")
    for island in ISLANDS:
        source = f"{DIR}/casa_{island}_original.png"
        if not os.path.exists(source):
            continue
        rgb = np.asarray(Image.open(source).convert("RGB")).astype(np.float32)
        rgba = garden.magenta_object(rgb)
        piece = garden.crop(remove_pink(rgba.astype(np.uint8)))
        Image.fromarray(piece, "RGBA").save(f"{DIR}/casa_{island}.png", optimize=True)
        alpha = piece[..., 3] > 40
        ys, xs = np.where(alpha)
        left = (xs.min(), ys[xs == xs.min()].mean())
        right = (xs.max(), ys[xs == xs.max()].mean())
        bottom = (xs[ys == ys.max()].mean(), ys.max())
        print(f"casa_{island}: {piece.shape[1]}x{piece.shape[0]}  sinistra {left[0]:.0f},{left[1]:.0f}  destra {right[0]:.0f},{right[1]:.0f}  fondo {bottom[0]:.0f},{bottom[1]:.0f}")


if __name__ == "__main__":
    main()
