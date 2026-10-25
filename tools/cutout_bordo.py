#!/usr/bin/env python3
"""Ritaglia le strisce del bordo di terra dell'isola: assets/giardino/bordo_original.png -> assets/giardino/bordo_<n>.png

Gemini disegna tre strisce orizzontali (una zolla vista di fronte: un bordo d'erba, terra con radici, sassi e muschio, un limite ondulato in basso)
su fondo bianco. Qui si toglie il fondo (il bianco collegato ai bordi dell'immagine), si ritaglia ogni striscia e la si porta alla stessa misura:
`LIP` pixel sopra la linea dove comincia la terra (ci stanno i fili d'erba che sporgono) e `BODY` pixel di terra sotto. L'app le mette sui due lati
dell'isola, ripetute e sovrapposte di `FADE` pixel: le estremità svaniscono piano, così il punto dove una finisce e l'altra comincia non si vede.

Lo stesso per il foglio d'inverno (bordo_neve_original.png -> bordo_neve_<n>.png): lì la «terra» comincia dove comincia lo strato di neve, che ha un contorno scuro.

Uso, dalla cartella principale:  python3 tools/cutout_bordo.py
"""
import importlib.util
import numpy as np
from PIL import Image

DIR = "assets/giardino"
# il foglio (assets/giardino/<nome>_original.png) e le righe (da, a) di ogni striscia
# (il terzo numero: di quanti pixel si ingrossa il contorno scuro prima di togliere il fondo; d'inverno la neve è bianca come il fondo e,
# se il contorno ha un buchino, il fondo entra nella neve)
SHEETS = [
    ("bordo", [(23, 182), (207, 364), (385, 557)], 0),
    ("bordo_neve", [(11, 183), (203, 371), (389, 567)], 3),     # d'inverno: la neve al posto dell'erba, i ghiaccioli, la terra fredda
]
OUTLINE_MAX = 200   # sotto questo canale massimo un pixel fa parte del contorno scuro (per chiudere i buchini del contorno, d'inverno)
BG_MIN = 238     # sopra questo canale minimo un pixel è sfondo (se collegato al bordo)
LIP, BODY = 24, 110
FADE = 30       # pixel (già alla misura finale) in cui le estremità svaniscono
PAD = 8


def load_garden_tools():
    spec = importlib.util.spec_from_file_location("cutout_giardino", "tools/cutout_giardino.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    garden = load_garden_tools()
    for name, strips, close in SHEETS:
        cut_sheet(garden, name, strips, close)


def cut_sheet(garden, name, strips, close):
    sheet = np.asarray(Image.open(f"{DIR}/{name}_original.png").convert("RGB")).astype(np.float32)
    for n, (top, bottom) in enumerate(strips, start=1):
        rgb = sheet[max(top - PAD, 0):bottom + PAD]
        height, width = rgb.shape[:2]
        light = rgb.min(axis=2) >= BG_MIN
        passable = light & ~garden.dilate(rgb.max(axis=2) < OUTLINE_MAX, close) if close else light
        seeds = [(y, x) for y in range(height) for x in (0, width - 1)] + [(y, x) for y in (0, height - 1) for x in range(width)]
        background = garden.flood(passable, seeds)
        if close:
            # il bianco che sta appena dentro il contorno ingrossato (e collegato al fondo) è ancora fondo
            background |= garden.dilate(background, close) & light
        # un bordo morbido: i pixel appena fuori dal fondo diventano semitrasparenti
        alpha = np.where(background, 0.0, 1.0)
        soft = garden.dilate(background, 1) & ~background
        alpha = np.where(soft, 0.55, alpha)
        rgba = np.dstack([rgb, alpha * 255]).astype(np.uint8)
        ys, xs = np.where(rgba[..., 3] > 25)
        rgba = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        # la linea dove comincia la terra: la prima riga quasi tutta piena
        coverage = (rgba[..., 3] > 128).mean(axis=1)
        body_top = int(np.argmax(coverage >= 0.9))
        body = rgba.shape[0] - body_top
        image = Image.fromarray(rgba, "RGBA")
        scale = BODY / body
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
        line = round(body_top * scale)
        # LIP righe sopra la linea (ritagliando o aggiungendo trasparenza), poi tutta la terra
        canvas = Image.new("RGBA", (image.width, LIP + image.height - line), (0, 0, 0, 0))
        canvas.paste(image.crop((0, max(line - LIP, 0), image.width, image.height)), (0, max(LIP - line, 0)))
        # le due estremità svaniscono piano: una striscia si sovrappone alla vicina e si fondono, senza taglio
        pixels = np.asarray(canvas).astype(np.float32).copy()
        ramp = np.clip(np.arange(canvas.width) / FADE, 0, 1) * np.clip((canvas.width - 1 - np.arange(canvas.width)) / FADE, 0, 1)
        pixels[..., 3] *= ramp[None, :]
        canvas = Image.fromarray(pixels.astype(np.uint8), "RGBA")
        canvas.save(f"{DIR}/{name}_{n}.png", optimize=True)
        print(f"{name}_{n}: {canvas.width}x{canvas.height} (linea a {LIP})")


if __name__ == "__main__":
    main()
