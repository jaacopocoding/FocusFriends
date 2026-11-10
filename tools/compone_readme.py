#!/usr/bin/env python3
"""Compone le immagini del README fatte con i disegni dei compagni e con i fumetti veri dell'app: docs/images/scrivania.png, compagni.png, frasi.png e crescita.png

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


def fumetto(n):
    return Image.open(f"build/readme/bubble{n}.png").convert("RGBA")


def gradient(size, top, bottom):
    from PIL import ImageFilter
    width, height = size
    image = Image.new("RGB", size)
    px = image.load()
    for y in range(height):
        t = y / (height - 1)
        row = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(width):
            px[x, y] = row
    return image


import math


def wallpaper(W, H):
    """Uno sfondo morbido, di colline: i colori dell'app, senza niente che distragga."""
    from PIL import ImageFilter
    image = gradient((W, H), (255, 240, 220), (253, 216, 190))
    draw = ImageDraw.Draw(image)
    layers = [(0.58, (206, 218, 200), 0.0085, 0.9, 20), (0.68, (166, 204, 176), 0.0068, 2.1, 26), (0.80, (126, 182, 148), 0.0052, 3.3, 30)]
    for base, color, frequency, phase, amplitude in layers:
        points = [(0, H)]
        for x in range(0, W + 8, 8):
            points.append((x, H * base + amplitude * math.sin(x * frequency + phase) + amplitude * 0.4 * math.sin(x * frequency * 2.1 + phase * 1.7)))
        points.append((W, H))
        draw.polygon(points, fill=color)
    return image.filter(ImageFilter.GaussianBlur(1.2))


def window(image, box, title, shadow=True):
    from PIL import ImageFilter
    x0, y0, x1, y1 = box
    if shadow:
        layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle((x0, y0 + 12, x1, y1 + 12), 20, fill=(70, 50, 60, 90))
        layer = layer.filter(ImageFilter.GaussianBlur(20))
        image.paste(layer, (0, 0), layer)
    draw = ImageDraw.Draw(image, "RGBA")
    draw.rounded_rectangle(box, 20, fill=(253, 253, 252), outline=(222, 218, 214), width=2)
    draw.rounded_rectangle((x0, y0, x1, y0 + 50), 20, fill=(240, 237, 234))
    draw.rectangle((x0, y0 + 30, x1, y0 + 50), fill=(240, 237, 234))
    for k, color in enumerate([(255, 96, 92), (255, 189, 68), (0, 202, 78)]):
        draw.ellipse((x0 + 22 + k * 28, y0 + 16, x0 + 38 + k * 28, y0 + 32), fill=color)
    centered(draw, title, (x0 + x1) // 2, y0 + 12, font(TEXT, 20), (120, 112, 108))
    return draw


def desk_scene(W, H, icon_active=False):
    """La scrivania, senza il compagno: gli appunti davanti, una dispensa dietro, la barra dei menu e il Dock."""
    from PIL import ImageFilter
    image = wallpaper(W, H)
    # la dispensa, dietro
    back = window(image, (560, 54, 1050, 330), "Dispensa di fisiologia", shadow=True)
    for k in range(6):
        back.rounded_rectangle((600, 124 + k * 28, 600 + 380 - (k % 3) * 70, 135 + k * 28), 6, fill=(226, 222, 218))
    back.rounded_rectangle((600, 290, 760, 314), 8, fill=(232, 226, 214))
    # gli appunti, davanti
    front = window(image, (50, 78, 640, 400), "Anatomia · appunti")
    front.text((88, 124), "Il sistema nervoso", font=ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 38), fill=(45, 40, 40))
    lines = ["Il sistema nervoso centrale comprende l'encefalo", "e il midollo spinale. Riceve le informazioni dai", "nervi e prepara le risposte.",
             "Le cellule principali sono i neuroni: ognuno ha un", "corpo, i dendriti che ricevono i segnali e un assone."]
    for k, line in enumerate(lines):
        front.text((88, 186 + k * 31), line, font=font(TEXT, 21), fill=(100, 92, 90))
    front.rounded_rectangle((88, 350, 238, 376), 10, fill=(255, 235, 200))
    front.text((100, 353), "da ripassare", font=font(TEXT, 18), fill=(176, 108, 40))
    # la barra dei menu, con l'icona dell'app
    draw = ImageDraw.Draw(image, "RGBA")
    draw.rectangle((0, 0, W, 30), fill=(255, 255, 255, 170))
    if icon_active:
        draw.rounded_rectangle((W - 174, 3, W - 142, 27), 6, fill=(60, 60, 70, 70))
    logo = Image.open("docs/images/logo.png").convert("RGBA").resize((20, 20), Image.LANCZOS)
    image.paste(logo, (W - 168, 5), logo)
    draw.text((W - 132, 6), "lun 16:40", font=font(TEXT, 16), fill=(50, 44, 44, 235))
    draw.text((22, 6), "Appunti", font=font(TEXT, 16), fill=(50, 44, 44, 235))
    # il Dock
    dock_w = 520
    draw.rounded_rectangle(((W - dock_w) // 2, H - 66, (W + dock_w) // 2, H - 14), 22, fill=(255, 255, 255, 150), outline=(255, 255, 255, 200), width=2)
    colors = [(255, 140, 90), (96, 170, 240), (110, 200, 130), (245, 200, 80), (200, 130, 220), (240, 110, 130), (120, 120, 140)]
    for k, color in enumerate(colors):
        cx = (W - dock_w) // 2 + 46 + k * 71
        draw.rounded_rectangle((cx - 22, H - 58, cx + 22, H - 22), 11, fill=color + (255,))
    return image


def scrivania():
    """Il compagno sulla scrivania, che cammina: una GIF con il Gattino, il fumetto e l'orologio veri dell'app. Mentre parla sta fermo (come nell'app)."""
    from PIL import ImageFilter
    W, H = 1100, 720
    ppt = 1.25                                           # pixel per punto: un compagno è largo circa 144 punti (la scrivania è più grande di così: lui non deve dare nell'occhio)
    scene = desk_scene(W, H)
    walk = [Image.open(f"assets/gattino/frame{n}.png").convert("RGBA") for n in range(2, 8)]
    still = Image.open("assets/gattino/frame1.png").convert("RGBA")
    k = (144 / 360) * ppt
    def scaled(im):
        return im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    walk = [scaled(f) for f in walk]
    still = scaled(still)
    ground = round(0.0949 * 274 * (144 / 360) * ppt)    # quanto sta sotto i piedi, nell'immagine
    bubble = fumetto(1)
    bubble = bubble.resize((round(bubble.width * ppt / 3), round(bubble.height * ppt / 3)), Image.LANCZOS)
    clocks = [Image.open(f"build/readme/timer_24{10 - n:02d}.png").convert("RGBA") for n in range(0, 9)]   # 24:10 … 24:02
    clocks = [c.resize((round(c.width * ppt / 3), round(c.height * ppt / 3)), Image.LANCZOS) for c in clocks]
    feet = 548
    speed = 42 * ppt                                     # punti al secondo, com'è nell'app
    fps, total = 10, 9.0
    frames, x = [], 400.0
    for n in range(int(total * fps)):
        t = n / fps
        speaking = 3.0 <= t < 7.0
        if not speaking and n > 0:
            x += speed / fps
        sprite = still if speaking else walk[int(t / 0.15) % len(walk)]
        frame = scene.copy().convert("RGBA")
        left = round(x - sprite.width / 2)
        top = feet + ground - sprite.height
        shadow = Image.new("RGBA", (sprite.width + 160, 120), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((80, 34, 80 + sprite.width - 30, 62), fill=(60, 40, 40, 70))
        shadow = shadow.filter(ImageFilter.GaussianBlur(5))
        frame.alpha_composite(shadow, (left - 80 + 12, feet - 46))
        frame.alpha_composite(sprite, (left, top))
        clock = clocks[min(int(t), len(clocks) - 1)]
        frame.alpha_composite(clock, (round(x - clock.width / 2), feet + ground - 10))
        if speaking:
            alpha = min((t - 3.0) / 0.3, (7.0 - t) / 0.3, 1.0)
            if alpha > 0:
                b = bubble.copy()
                b.putalpha(b.getchannel("A").point(lambda v: int(v * alpha)))
                head_x = left + round(sprite.width * 0.74)
                frame.alpha_composite(b, (head_x - round(b.width * 0.825), top + 40 - b.height))
        frames.append(frame.convert("RGB"))
    # una sola tavolozza per tutti i fotogrammi (altrimenti i colori ballano)
    montage = Image.new("RGB", (W, H * 3))
    for i, index in enumerate((5, 45, 80)):
        montage.paste(frames[index], (0, i * H))
    palette = montage.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    quantized = [f.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG) for f in frames]
    quantized[0].save("docs/images/scrivania.gif", save_all=True, append_images=quantized[1:], duration=round(1000 / fps), loop=0, optimize=False, disposal=1)
    frames[45].save("docs/images/scrivania.png", optimize=True)
    print("scrivania.gif", W, H, len(frames), "fotogrammi")


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


FRASI = [
    ("Pianty", "assets/pianty/stage5_1.png", 84 / 208, 2),
    ("Porcellino", "assets/porcellino/frame1.png", 118 / 236, 3),
    ("Gattino", "assets/gattino/frame1.png", 144 / 360, 4),
    ("Riccio", "assets/riccio/frame1.png", 154 / 405, 5),
]


def frasi():
    zoom = 2.0
    cell, height = 380, 640
    base = height - 110
    sheet = Image.new("RGB", (cell * len(FRASI), height), CREAM)
    draw = ImageDraw.Draw(sheet)
    for index, (name, path, scale, bubble_number) in enumerate(FRASI):
        art = trimmed(path)
        k = scale * zoom
        art = art.resize((round(art.width * k), round(art.height * k)), Image.LANCZOS)
        cx = index * cell + cell // 2
        shadow = Image.new("RGBA", (min(art.width + 24, cell - 40), 24), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((0, 0, shadow.width, shadow.height), fill=(90, 60, 30, 46))
        sheet.paste(shadow, (cx - shadow.width // 2, base - 11), shadow)
        sheet.paste(art, (cx - art.width // 2, base - art.height), art)
        bubble = fumetto(bubble_number)
        bk = 0.52
        bubble = bubble.resize((round(bubble.width * bk), round(bubble.height * bk)), Image.LANCZOS)
        head_x = cx + art.width // 4
        top = base - art.height - bubble.height + 10
        left = head_x - round(bubble.width * 0.825)
        left = min(max(left, index * cell + 12), (index + 1) * cell - 12 - bubble.width)       # il fumetto resta nella sua colonna
        sheet.paste(bubble, (left, max(top, 10)), bubble)
        centered(draw, name, cx, base + 32, font(MARKER, 30), INK)
    sheet.save("docs/images/frasi.png", optimize=True)
    print("frasi.png", sheet.size)


if __name__ == "__main__":
    scrivania()
    menu_schermata()
    compagni()
    frasi()
    crescita()
