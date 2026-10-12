#!/usr/bin/env python3
"""Compone le immagini di crescita del porcellino durante un focus: la carota che cresce, e lui accanto.

    python3 tools/compose_porcellino_growth.py [cartella_giardino]

Legge assets/porcellino/frame1.png (il porcellino a riposo) e le cinque carote del giardino
(<cartella>/garden_porcellino_1..5.png, sulla tela delle piantine 208x341) e scrive
<cartella>/growth_porcellino_1..5.png.

Il soggetto è la carota: la matura occupa quasi tutta l'altezza della finestra, mentre il porcellino è più
piccolo e sta a guardarla. Il GRUPPO porcellino + carota sta al centro della tela, e quindi sopra l'orologio
(che sta centrato sotto la finestra). Quando guarda a sinistra l'immagine viene specchiata e la carota è
comunque davanti a lui.
"""
import sys
from PIL import Image

PORCELLINO = "assets/porcellino/frame1.png"
FOLDER = sys.argv[1] if len(sys.argv) > 1 else "assets/garden"
GROUND_FRACTION = 0.129          # dove stanno i piedi del porcellino (dal fondo, in frazione dell'altezza)
FEET_IN_GARDEN_CANVAS = 0.0176   # e dove stanno quelli delle carote nella tela delle piantine
RIPE_HEIGHT = 196                # px della tela del porcellino (241 di altezza): la carota matura, foglie incluse
PIG_SCALE = 0.62                 # quanto si rimpicciolisce il porcellino rispetto al suo disegno normale
GAP = 8                          # spazio fra il muso e la carota

pig = Image.open(PORCELLINO).convert("RGBA")
H = pig.height
W_PIG = pig.width
pig_small = pig.resize((round(pig.width * PIG_SCALE), round(pig.height * PIG_SCALE)), Image.LANCZOS)
pb = pig_small.getbbox()

carrots = [Image.open(f"{FOLDER}/garden_porcellino_{i}.png").convert("RGBA") for i in range(1, 6)]
ripe = carrots[-1].getbbox()
scale = RIPE_HEIGHT / (ripe[3] - ripe[1])        # stessa scala per tutti gli stadi
scaled = [c.resize((round(c.width * scale), round(c.height * scale)), Image.LANCZOS) for c in carrots]
carrot_w = max(s.getbbox()[2] - s.getbbox()[0] for s in scaled)

# Il gruppo porcellino + carota sta al CENTRO della tela: così, sotto il timer, il gruppo è centrato
# (e la finestra si allarga attorno a quel centro).
MARGIN = 10
union_w = (pb[2] - pb[0]) + GAP + carrot_w
W = union_w + 2 * MARGIN
feet_y = round(H * (1 - GROUND_FRACTION))
print(f"porcellino x{PIG_SCALE}, carota matura {RIPE_HEIGHT}px (scala {scale:.2f}), tela {W}x{H}")

pig_x = MARGIN - pb[0]                        # il porcellino a sinistra del gruppo
pig_y = feet_y - round(pig_small.height * (1 - GROUND_FRACTION))
carrot_center = MARGIN + (pb[2] - pb[0]) + GAP + carrot_w / 2.0   # sempre lo stesso: la carota cresce sul posto

for i, s in enumerate(scaled, 1):
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.paste(pig_small, (pig_x, pig_y), pig_small)
    bb = s.getbbox()
    s_feet = round(s.height * (1 - FEET_IN_GARDEN_CANVAS))
    x = carrot_center - (bb[0] + bb[2]) / 2.0     # il centro della carota sul suo punto fisso
    y = feet_y - s_feet
    canvas.paste(s, (int(round(x)), int(round(y))), s)
    canvas.save(f"{FOLDER}/growth_porcellino_{i}.png")
print("scritti", len(scaled), "file in", FOLDER)
