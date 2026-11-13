#!/usr/bin/env python3
"""Compone le immagini del README fatte con i disegni dei compagni e con i fumetti veri dell'app: docs/images/scrivania.gif (in scrivania_readme.py), menu-schermata.png, giro.png, compagni.png e crescita.png

    tools/compone-readme.sh        (disegna prima i fumetti e l'orologio dell'app in build/readme/, poi chiama questo script)
    python3 tools/compone_readme.py   (solo la composizione, se i fumetti in build/readme/ ci sono già)

Servono i caratteri di macOS (Marker Felt). I disegni sono quelli dell'app (assets/<compagno>/frame1.png, gli stadi di Pianty, le immagini di crescita
in assets/garden/), alla grandezza che hanno sul desktop (la finestra di ogni compagno ha la sua scala), con i piedi sulla stessa linea.
"""
from PIL import Image, ImageDraw, ImageFont

CREAM = (255, 246, 222)
INK = (41, 26, 15)
SOFT = (110, 82, 55)
MARKER = "/System/Library/Fonts/MarkerFelt.ttc"
TEXT = "/System/Library/Fonts/SFNSRounded.ttf"


def font(path, size):
    return ImageFont.truetype(path, size)


def trimmed(path):
    image = Image.open(path).convert("RGBA")
    return image.crop(image.getbbox())


def centered(draw, text, center_x, y, face, fill):
    width = draw.textlength(text, font=face)
    draw.text((center_x - width / 2, y), text, font=face, fill=fill)


# nome, immagine da ferma, punti della finestra per pixel del disegno (la scala vera sul desktop), didascalia
PETS = [
    ("Pianty", "assets/pianty/stage5_1.png", 84 / 208, "una succulenta che cresce"),
    ("Porcellino", "assets/porcellino/frame1.png", 118 / 236, "una cavia e la sua carota"),
    ("Ciccio", "assets/ciccio/frame1.png", 112 / 321, "una cocorita che svolazza"),
    ("Gattino", "assets/gattino/frame1.png", 144 / 360, "un gatto e il suo pesce"),
    ("Riccio", "assets/riccio/frame1.png", 154 / 405, "un riccio e le sue mele"),
    ("Tartaruga", "assets/tartaruga/frame1.png", 144 / 328, "una tartaruga e la sua fragola"),
]


def compagni():
    zoom = 2.6
    cell, height = 330, 520
    base = height - 130          # la linea di terra
    sheet = Image.new("RGB", (cell * len(PETS), height), CREAM)
    draw = ImageDraw.Draw(sheet)
    for index, (name, path, scale, caption) in enumerate(PETS):
        art = trimmed(path)
        k = scale * zoom
        art = art.resize((round(art.width * k), round(art.height * k)), Image.LANCZOS)
        cx = index * cell + cell // 2
        # un'ombra morbida
        shadow = Image.new("RGBA", (min(art.width + 24, cell - 30), 26), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((0, 0, shadow.width, shadow.height), fill=(90, 60, 30, 46))
        sheet.paste(shadow, (cx - shadow.width // 2, base - 12), shadow)
        sheet.paste(art, (cx - art.width // 2, base - art.height), art)
        centered(draw, name, cx, base + 34, font(MARKER, 34), INK)
        centered(draw, caption, cx, base + 82, font(TEXT, 18), SOFT)
    sheet.save("docs/images/compagni.png", optimize=True)
    print("compagni.png", sheet.size)


GROWTH = [
    ("Pianty", "da seme a pianta", [f"assets/pianty/stage{i}_1.png" for i in range(1, 6)], 84 / 208),
    ("Ciccio", "da uovo a cocorita", [f"assets/garden/garden_ciccio_{i}.png" for i in range(1, 6)], 84 / 208),
    ("Porcellino", "una carota che cresce", [f"assets/garden/growth_porcellino_{i}.png" for i in range(1, 6)], 118 / 236),
    ("Riccio", "la schiena che si riempie", [f"assets/garden/growth_riccio_{i}.png" for i in range(1, 6)], 154 / 405),
]


def crescita():
    zoom = 1.5
    label, cell = 250, 210
    heights = [240, 190, 190, 190]        # la pianta, da grande, è alta: le serve più spazio
    sheet = Image.new("RGB", (label + cell * 5 + 20, sum(heights) + 70), CREAM)
    draw = ImageDraw.Draw(sheet)
    # in cima: dall'inizio alla fine del focus
    arrow_y = 34
    draw.text((label + 8, 6), "inizio del focus", font=font(TEXT, 17), fill=SOFT)
    end_text = "fine"
    draw.text((sheet.width - 20 - draw.textlength(end_text, font=font(TEXT, 17)), 6), end_text, font=font(TEXT, 17), fill=SOFT)
    draw.line((label + 8, arrow_y, sheet.width - 24, arrow_y), fill=(214, 184, 140), width=3)
    draw.polygon([(sheet.width - 24, arrow_y - 7), (sheet.width - 12, arrow_y), (sheet.width - 24, arrow_y + 7)], fill=(214, 184, 140))
    y0 = 70
    for row, (name, caption, paths, scale) in enumerate(GROWTH):
        row_height = heights[row]
        base = y0 + row_height - 28
        draw.text((24, y0 + row_height // 2 - 38), name, font=font(MARKER, 32), fill=INK)
        draw.text((24, y0 + row_height // 2 + 4), caption, font=font(TEXT, 17), fill=SOFT)
        arts = [Image.open(p).convert("RGBA") for p in paths]
        k = scale * zoom        # la stessa scala per tutti gli stadi, e i piedi sulla stessa linea: così si vede che cresce
        for i, art in enumerate(arts):
            piece = art.crop(art.getbbox())
            piece = piece.resize((max(1, round(piece.width * k)), max(1, round(piece.height * k))), Image.LANCZOS)
            cx = label + i * cell + cell // 2
            sheet.paste(piece, (cx - piece.width // 2, base - piece.height), piece)
        y0 += row_height
    sheet.save("docs/images/crescita.png", optimize=True)
    print("crescita.png", sheet.size)


# ---------------------------------------------------------------------------------------------------------------------------------------------------
# Il compagno sullo schermo: una scrivania con gli appunti, e lui che cammina, con il fumetto e l'orologio veri dell'app (disegnati da tools/banchi/render-fumetti).


def desk_scene(W, H):
    """La scrivania senza il compagno (la stessa della GIF: tools/scrivania_readme.py), alla grandezza di questa immagine."""
    import scrivania_readme
    return scrivania_readme.desk((W, H)).resize((W, H), Image.LANCZOS)


def scrivania():
    """Il compagno sulla scrivania, che cammina, parla, e l'orologio a tendina che si chiude e si riapre al passaggio del cursore: tools/scrivania_readme.py."""
    import scrivania_readme
    scrivania_readme.scrivania()


def menu_schermata():
    """La scheda del menu vera dell'app, aperta dal compagno (clic destro su di lui): sta alla sua sinistra, con il bordo di sotto alla stessa altezza (come in MenuCard.reposition)."""
    from PIL import ImageFilter, ImageOps
    W, H = 1200, 960
    ppt = 1.1                                            # pixel per punto, per la scheda e per il compagno
    scene = desk_scene(W, H).convert("RGBA")
    # il compagno, in basso a destra, che guarda verso la scheda
    cat = Image.open("assets/gattino/frame1.png").convert("RGBA")
    k = (144 / 360) * ppt
    cat = ImageOps.mirror(cat.resize((round(cat.width * k), round(cat.height * k)), Image.LANCZOS))
    pet_left, window_bottom = W - 70 - cat.width, 876
    ground = round(0.0949 * 274 * k)
    glow = Image.new("RGBA", (cat.width + 160, 120), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((80, 34, 80 + cat.width - 30, 62), fill=(60, 40, 40, 70))
    scene.alpha_composite(glow.filter(ImageFilter.GaussianBlur(5)), (pet_left - 80 + 12, window_bottom - ground - 46))
    scene.alpha_composite(cat, (pet_left, window_bottom - cat.height))
    # la scheda, a sinistra di lui (10 punti di distanza), con il bordo di sotto come il suo
    card = Image.open("build/readme/scheda.png").convert("RGBA")
    card = card.resize((round(card.width * ppt / 2), round(card.height * ppt / 2)), Image.LANCZOS)
    x, y = pet_left - round(10 * ppt) - card.width, window_bottom - card.height
    shadow = Image.new("RGBA", scene.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 14, x + card.width, y + card.height + 14), 28, fill=(60, 40, 40, 110))
    scene.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(20)))
    scene.alpha_composite(card, (x, y))
    scene.convert("RGB").save("docs/images/menu-schermata.png", optimize=True)
    print("menu-schermata.png", scene.size)


def giro():
    """Il giro guidato al passo del giardino, come sullo schermo: la scheda con il velo tranne il giardino (tools/banchi/render-scheda.sh, modo «giro»),
    il fumetto del giro a sinistra con la punta sul giardino e sopra l'immagine di com'è fatto (assets/benvenuto/giardino.png), come in GuidedTour.show."""
    from PIL import ImageFilter, ImageOps
    W, H = 1200, 960
    ppt = 1.1
    scene = desk_scene(W, H).convert("RGBA")
    cat = Image.open("assets/gattino/frame1.png").convert("RGBA")
    k = (144 / 360) * ppt
    cat = ImageOps.mirror(cat.resize((round(cat.width * k), round(cat.height * k)), Image.LANCZOS))
    pet_left, window_bottom = W - 70 - cat.width, 876
    ground = round(0.0949 * 274 * k)
    glow = Image.new("RGBA", (cat.width + 160, 120), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((80, 34, 80 + cat.width - 30, 62), fill=(60, 40, 40, 70))
    scene.alpha_composite(glow.filter(ImageFilter.GaussianBlur(5)), (pet_left - 80 + 12, window_bottom - ground - 46))
    scene.alpha_composite(cat, (pet_left, window_bottom - cat.height))
    card = Image.open("build/readme/scheda-giro.png").convert("RGBA")
    card = card.resize((round(card.width * ppt / 2), round(card.height * ppt / 2)), Image.LANCZOS)
    x, y = pet_left - round(10 * ppt) - card.width, window_bottom - card.height
    shadow = Image.new("RGBA", scene.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 14, x + card.width, y + card.height + 14), 28, fill=(60, 40, 40, 110))
    scene.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(20)))
    scene.alpha_composite(card, (x, y))
    # il fumetto: a sinistra della scheda (4 punti), con la punta a metà del giardino (30 punti sotto il suo bordo alto)
    spot_y, spot_h = [float(v) for v in open("build/readme/giro.txt").read().split()][1::2]
    tip = Image.open("build/readme/giro-fumetto.png").convert("RGBA")
    tip = tip.resize((round(tip.width * ppt / 2), round(tip.height * ppt / 2)), Image.LANCZOS)
    tip_x = x - round(4 * ppt) - tip.width
    tip_y = round(y + (spot_y + spot_h / 2 - 30) * ppt)
    tip_shadow = Image.new("RGBA", scene.size, (0, 0, 0, 0))
    ImageDraw.Draw(tip_shadow).rounded_rectangle((tip_x + 4, tip_y + 8, tip_x + tip.width - 14, tip_y + tip.height + 6), 18, fill=(40, 30, 20, 70))
    scene.alpha_composite(tip_shadow.filter(ImageFilter.GaussianBlur(10)))
    scene.alpha_composite(tip, (tip_x, tip_y))
    # l'immagine di com'è fatto: sopra il fumetto, larga al massimo 420 punti, angoli tondi e ombra
    peek = Image.open("assets/benvenuto/giardino.png").convert("RGBA")
    width = round(min(420 * ppt, tip_x + tip.width - 10 * ppt - 8 * ppt))
    peek = peek.resize((width, round(width * peek.height / peek.width)), Image.LANCZOS)
    mask = Image.new("L", peek.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, peek.width - 1, peek.height - 1), round(14 * ppt), fill=255)
    peek.putalpha(mask)
    px = max(tip_x + tip.width - round(10 * ppt) - peek.width, round(8 * ppt))
    py = tip_y - round(12 * ppt) - peek.height
    if py < 40:
        py = tip_y + tip.height + round(12 * ppt)
    peek_shadow = Image.new("RGBA", scene.size, (0, 0, 0, 0))
    ImageDraw.Draw(peek_shadow).rounded_rectangle((px, py + 10, px + peek.width, py + peek.height + 10), 18, fill=(40, 30, 20, 90))
    scene.alpha_composite(peek_shadow.filter(ImageFilter.GaussianBlur(16)))
    scene.alpha_composite(peek, (px, py))
    scene.convert("RGB").save("docs/images/giro.png", optimize=True)
    print("giro.png", scene.size)


def finestra_statistiche(name):
    """La finestra delle statistiche disegnata da tools/banchi/render-statistiche.sh (build/readme/<name>.png), con gli angoli tondi e l'ombra, su un fondo chiaro."""
    from PIL import ImageFilter
    view = Image.open(f"build/readme/{name}.png").convert("RGBA")
    margin, radius = 88, 40
    mask = Image.new("L", view.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, view.width - 1, view.height - 1), radius, fill=255)
    view.putalpha(mask)
    sheet = Image.new("RGBA", (view.width + 2 * margin, view.height + 2 * margin), (235, 227, 214, 255))
    shadow = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((margin, margin + 14, margin + view.width, margin + view.height + 14), radius, fill=(70, 50, 30, 80))
    sheet.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(22)))
    sheet.alpha_composite(view, (margin, margin))
    sheet.convert("RGB").save(f"docs/images/{name}.png", optimize=True)
    print(f"{name}.png", sheet.size)


def statistiche():
    for name in ("statistiche-oggi", "statistiche-settimana", "statistiche-mese", "statistiche-anno"):
        finestra_statistiche(name)


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["statistiche"]:
        statistiche()
        sys.exit()
    if sys.argv[1:] == ["scrivania"]:
        scrivania()
        sys.exit()
    scrivania()
    menu_schermata()
    giro()
    compagni()
    crescita()
