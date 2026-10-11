#!/usr/bin/env python3
"""Compone le immagini di crescita del porcellino durante un focus: lui fermo, con la carota accanto.

    python3 tools/compose_porcellino_growth.py [cartella_giardino]

Legge assets/porcellino/frame1.png (il porcellino a riposo) e le cinque carote del giardino
(<cartella>/garden_porcellino_1..5.png, sulla tela delle piantine 208x341) e scrive
<cartella>/growth_porcellino_1..5.png: la tela del porcellino (stessa altezza e stessa linea di terra),
allargata a destra e a sinistra di quanto serve alla carota. Il porcellino sta al centro: se la finestra si
allarga attorno ai suoi piedi, lui non si sposta; quando guarda a sinistra l'immagine viene specchiata
e la carota è comunque davanti a lui.

La carota è alla stessa scala per tutti gli stadi (la matura alta quanto il porcellino) e sta sulla sua linea
di terra, appena a destra del muso.
"""
import sys
import numpy as np
from PIL import Image

PORCELLINO = "assets/porcellino/frame1.png"
FOLDER = sys.argv[1] if len(sys.argv) > 1 else "assets/garden"
GROUND_FRACTION = 0.129          # dove stanno i piedi del porcellino (dal fondo, in frazione dell'altezza)
GAP = 6                          # spazio fra il muso e la carota
RIPE_HEIGHT_RATIO = 1.0          # la carota matura alta quanto il porcellino

pig = Image.open(PORCELLINO).convert("RGBA")
pb = pig.getbbox()
pig_h = pb[3] - pb[1]
carrots = []
for i in range(1, 6):
    img = Image.open(f"{FOLDER}/garden_porcellino_{i}.png").convert("RGBA")
    carrots.append(img)

# Scala unica: la carota dell'ultimo stadio alta come il porcellino.
ripe = carrots[-1].getbbox()
scale = RIPE_HEIGHT_RATIO * pig_h / (ripe[3] - ripe[1])
widths = []
scaled = []
for img in carrots:
    s = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    scaled.append(s)
    bb = s.getbbox()
    widths.append(bb[2] - bb[0])
pad = max(widths) + GAP + 6
W, H = pig.width + 2 * pad, pig.height
feet_y = round(H * (1 - GROUND_FRACTION))
print(f"porcellino {pig.size}, carota in scala {scale:.2f}, margine {pad}px -> tela {W}x{H}")

for i, s in enumerate(scaled, 1):
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.paste(pig, (pad, 0), pig)
    bb = s.getbbox()
    # la carota: bordo basso della sua immagine sulla linea di terra del porcellino
    # (nella tela delle piantine i piedi stanno a 1,76% dal fondo)
    s_feet = round(s.height * (1 - 0.0176))
    cx_src = (bb[0] + bb[2]) / 2.0
    x = pad + pb[2] + GAP + (bb[2] - bb[0]) / 2.0 - cx_src
    y = feet_y - s_feet
    canvas.paste(s, (int(round(x)), int(round(y))), s)
    canvas.save(f"{FOLDER}/growth_porcellino_{i}.png")
print("scritti", [f"{FOLDER}/growth_porcellino_{i}.png" for i in range(1, 6)])
