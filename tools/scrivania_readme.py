"""La scrivania animata del README (docs/images/scrivania.gif e scrivania.png): il Gattino che cammina sopra il Dock, si ferma a dire una frase,
e l'orologio del focus che si chiude a tendina; poi arriva il cursore, si posa sul compagno e l'orologio si riapre, come nell'app (Pomodoro.swift:
evaluateVisibility, reveal, conceal; TimerView.reveal).

    python3 tools/compone_readme.py scrivania     (servono i fumetti e gli orologi veri dell'app in build/readme/: li disegna tools/compone-readme.sh)

Tutto è disegnato al doppio della grandezza e poi rimpicciolito: i testi vengono nitidi. Servono i caratteri di macOS (SF, New York, Marker Felt).
"""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

S = 2                                   # si disegna al doppio, e si rimpicciolisce alla fine
W, H = 1100, 720                        # la grandezza della GIF
SF = "/System/Library/Fonts/SFNS.ttf"
NY = "/System/Library/Fonts/NewYork.ttf"


def s(v):
    return round(v * S)


def face(path, size, weight=None):
    """Un carattere variabile di macOS al peso giusto e con la grandezza ottica della sua misura (senza, le lettere vengono troppo larghe)."""
    f = ImageFont.truetype(path, s(size))
    try:
        axes = []
        for a in f.get_variation_axes():
            if a["name"] == b"Weight":
                axes.append(weight or a["default"])
            elif a["name"] == b"Optical Size":
                axes.append(min(max(size, a["minimum"]), a["maximum"]))
            else:
                axes.append(a["default"])
        f.set_variation_by_axes(axes)
    except OSError:
        pass
    return f


def text(d, xy, t, f, fill):
    d.text((s(xy[0]), s(xy[1])), t, font=f, fill=fill)


# ---------------------------------------------------------------------------------------------------------------------------------------------------
# La scena ferma: lo sfondo a colline, la dispensa, gli appunti, la barra dei menu e il Dock.

def wallpaper():
    """Le colline: i colori dell'app, senza niente che distragga."""
    img = Image.new("RGB", (s(W), s(H)))
    top, bottom = (255, 240, 220), (253, 216, 190)
    sky = Image.new("RGB", (1, s(H)))
    for y in range(s(H)):
        t = y / (s(H) - 1)
        sky.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    img.paste(sky.resize((s(W), s(H))))
    d = ImageDraw.Draw(img)
    for base, color, fr, ph, amp in [(0.58, (206, 218, 200), 0.0085, 0.9, 20), (0.68, (166, 204, 176), 0.0068, 2.1, 26), (0.80, (126, 182, 148), 0.0052, 3.3, 30)]:
        pts = [(0, s(H))]
        for x in range(0, W + 4, 2):
            pts.append((s(x), s(H * base + amp * math.sin(x * fr + ph) + amp * 0.4 * math.sin(x * fr * 2.1 + ph * 1.7))))
        pts.append((s(W), s(H)))
        d.polygon(pts, fill=color)
    return img.filter(ImageFilter.GaussianBlur(s(1.2))).convert("RGBA")


def shadow(img, box, radius=14, blur=22, dy=14, alpha=70):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(layer).rounded_rectangle((s(x0), s(y0 + dy), s(x1), s(y1 + dy)), s(radius), fill=(80, 55, 50, alpha))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(s(blur))))


def window(img, box, title, radius=14, bar=40):
    """Una finestra come quelle di macOS: angoli tondi, la barra del titolo con i tre semafori, un filo di bordo e l'ombra."""
    x0, y0, x1, y1 = box
    shadow(img, box, radius)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((s(x0), s(y0), s(x1), s(y1)), s(radius), fill=(255, 254, 252))
    d.rounded_rectangle((s(x0), s(y0), s(x1), s(y0 + bar)), s(radius), fill=(245, 242, 238))
    d.rectangle((s(x0), s(y0 + bar - radius), s(x1), s(y0 + bar)), fill=(245, 242, 238))
    d.line((s(x0), s(y0 + bar), s(x1), s(y0 + bar)), fill=(228, 223, 218), width=s(1))
    d.rounded_rectangle((s(x0), s(y0), s(x1), s(y1)), s(radius), outline=(0, 0, 0, 30), width=s(1))
    for k, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        cx, cy = x0 + 20 + k * 20, y0 + bar / 2
        d.ellipse((s(cx - 6), s(cy - 6), s(cx + 6), s(cy + 6)), fill=c, outline=tuple(max(0, v - 30) for v in c), width=1)
    f = face(SF, 13, 590)
    d.text((s((x0 + x1) / 2), s(y0 + bar / 2)), title, font=f, fill=(95, 88, 84), anchor="mm")
    img.alpha_composite(layer)
    return ImageDraw.Draw(img, "RGBA")


def body_lines(d, x, y, lines, size=15.5, lead=1.62, color=(84, 78, 76)):
    f = face(SF, size, 400)
    for k, line in enumerate(lines):
        text(d, (x, y + k * size * lead), line, f, color)


def neuron(d, cx, cy, z, color=(196, 120, 110)):
    """Il disegno della dispensa: un neurone, con i dendriti e l'assone con la mielina."""
    d.ellipse((s(cx - z), s(cy - z * 0.8), s(cx + z), s(cy + z * 0.8)), fill=color + (60,), outline=color, width=s(1.6))
    d.ellipse((s(cx - z * 0.32), s(cy - z * 0.28), s(cx + z * 0.32), s(cy + z * 0.28)), fill=color)
    for a in (130, 160, 200, 230, 95, 265):
        r = math.radians(a)
        x1, y1 = cx + math.cos(r) * z, cy + math.sin(r) * z * 0.8
        x2, y2 = cx + math.cos(r) * z * 1.9, cy + math.sin(r) * z * 1.6
        d.line((s(x1), s(y1), s(x2), s(y2)), fill=color, width=s(1.6))
        d.line((s(x2), s(y2), s(x2 + math.cos(r + 0.5) * z * 0.5), s(y2 + math.sin(r + 0.5) * z * 0.5)), fill=color, width=s(1.2))
    x = cx + z
    d.line((s(x), s(cy), s(x + z * 5.2), s(cy)), fill=color, width=s(1.8))
    for k in range(4):
        xx = x + z * 0.35 + k * z * 1.2
        d.rounded_rectangle((s(xx), s(cy - z * 0.2), s(xx + z * 0.95), s(cy + z * 0.2)), s(3), fill=(250, 214, 170), outline=color, width=s(1))
    end = x + z * 5.2
    for a in (-35, 0, 35):
        r = math.radians(a)
        d.line((s(end), s(cy), s(end + math.cos(r) * z * 0.8), s(cy + math.sin(r) * z * 0.8)), fill=color, width=s(1.4))


def menubar(img):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle((0, 0, s(W), s(26)), fill=(255, 250, 244, 190))
    x = 18
    for k, t in enumerate(["Appunti", "File", "Modifica", "Formato", "Vista", "Finestra"]):
        f = face(SF, 13, 700 if k == 0 else 450)
        d.text((s(x), s(5)), t, font=f, fill=(40, 34, 32))
        x += d.textlength(t, font=f) / S + 20
    f = face(SF, 13, 450)
    clock = "lun 13 nov  16:40"
    tw = d.textlength(clock, font=f) / S
    d.text((s(W - 18 - tw), s(5)), clock, font=f, fill=(40, 34, 32))
    logo = Image.open("docs/images/logo.png").convert("RGBA").resize((s(17), s(17)), Image.LANCZOS)
    layer.alpha_composite(logo, (s(W - 18 - tw - 30), s(4)))
    img.alpha_composite(layer)


def tile(img, x, y, size, top, bottom):
    """Il fondo di un'icona del Dock: un quadrato arrotondato con una sfumatura e la sua ombra."""
    grad = Image.new("RGBA", (1, s(size)))
    for yy in range(s(size)):
        grad.putpixel((0, yy), tuple(round(top[i] + (bottom[i] - top[i]) * yy / s(size)) for i in range(3)) + (255,))
    t = grad.resize((s(size), s(size)))
    mask = Image.new("L", t.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, s(size) - 1, s(size) - 1), s(size * 0.23), fill=255)
    t.putalpha(mask)
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((s(x), s(y + 2), s(x + size), s(y + size + 2)), s(size * 0.23), fill=(60, 40, 30, 60))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(s(2))))
    img.alpha_composite(t, (s(x), s(y)))
    return ImageDraw.Draw(img, "RGBA")


# Le icone del Dock: disegni semplici, nessun marchio vero.
def ic_notes(img, x, y, z):
    d = tile(img, x, y, z, (255, 222, 120), (247, 190, 70))
    d.rounded_rectangle((s(x), s(y + z * 0.30), s(x + z), s(y + z)), s(z * 0.23), fill=(255, 253, 245))
    d.rectangle((s(x), s(y + z * 0.30), s(x + z), s(y + z * 0.6)), fill=(255, 253, 245))
    for k in range(3):
        d.line((s(x + z * 0.18), s(y + z * (0.50 + k * 0.15)), s(x + z * 0.82), s(y + z * (0.50 + k * 0.15))), fill=(226, 218, 200), width=s(1.5))


def ic_book(img, x, y, z):
    d = tile(img, x, y, z, (255, 160, 100), (236, 110, 70))
    d.rounded_rectangle((s(x + z * 0.24), s(y + z * 0.2), s(x + z * 0.76), s(y + z * 0.8)), s(3), fill=(255, 247, 235))
    d.rectangle((s(x + z * 0.24), s(y + z * 0.2), s(x + z * 0.34), s(y + z * 0.8)), fill=(250, 210, 180))


def ic_calendar(img, x, y, z):
    d = tile(img, x, y, z, (255, 255, 255), (240, 236, 232))
    d.text((s(x + z / 2), s(y + z * 0.23)), "NOV", font=face(SF, 8.5, 700), fill=(235, 80, 70), anchor="mm")
    d.text((s(x + z / 2), s(y + z * 0.60)), "13", font=face(SF, 22, 400), fill=(40, 34, 32), anchor="mm")


def ic_globe(img, x, y, z):
    d = tile(img, x, y, z, (130, 210, 170), (70, 175, 130))
    cx, cy, r = x + z / 2, y + z / 2, z * 0.28
    d.ellipse((s(cx - r), s(cy - r), s(cx + r), s(cy + r)), outline=(255, 255, 255), width=s(2))
    d.ellipse((s(cx - r * 0.45), s(cy - r), s(cx + r * 0.45), s(cy + r)), outline=(255, 255, 255), width=s(1.5))
    d.line((s(cx - r), s(cy), s(cx + r), s(cy)), fill=(255, 255, 255), width=s(1.5))


def ic_music(img, x, y, z):
    d = tile(img, x, y, z, (255, 120, 140), (230, 70, 110))
    w = (255, 255, 255)
    d.ellipse((s(x + z * 0.26), s(y + z * 0.58), s(x + z * 0.44), s(y + z * 0.72)), fill=w)
    d.ellipse((s(x + z * 0.56), s(y + z * 0.52), s(x + z * 0.74), s(y + z * 0.66)), fill=w)
    d.line((s(x + z * 0.43), s(y + z * 0.65), s(x + z * 0.43), s(y + z * 0.30)), fill=w, width=s(2.2))
    d.line((s(x + z * 0.73), s(y + z * 0.59), s(x + z * 0.73), s(y + z * 0.24)), fill=w, width=s(2.2))
    d.polygon([(s(x + z * 0.42), s(y + z * 0.28)), (s(x + z * 0.745), s(y + z * 0.22)), (s(x + z * 0.745), s(y + z * 0.32)), (s(x + z * 0.42), s(y + z * 0.38))], fill=w)


def ic_folder(img, x, y, z):
    d = tile(img, x, y, z, (120, 190, 250), (70, 150, 235))
    d.rounded_rectangle((s(x + z * 0.18), s(y + z * 0.32), s(x + z * 0.5), s(y + z * 0.45)), s(2), fill=(215, 238, 255))
    d.rounded_rectangle((s(x + z * 0.18), s(y + z * 0.38), s(x + z * 0.82), s(y + z * 0.74)), s(3), fill=(235, 246, 255))


def ic_focus(img, x, y, z):
    tile(img, x, y, z, (255, 246, 222), (250, 228, 190))
    logo = Image.open("docs/images/logo.png").convert("RGBA").resize((s(z * 0.78), s(z * 0.78)), Image.LANCZOS)
    img.alpha_composite(logo, (s(x + z * 0.11), s(y + z * 0.11)))
    ImageDraw.Draw(img, "RGBA").ellipse((s(x + z / 2 - 2), s(y + z + 5), s(x + z / 2 + 2), s(y + z + 9)), fill=(60, 50, 50, 200))   # l'app è aperta


def dock(img):
    icons = [ic_notes, ic_book, ic_calendar, ic_globe, ic_music, ic_folder, ic_focus]
    size, gap = 46, 12
    w = len(icons) * size + (len(icons) - 1) * gap + 28
    x0, y0 = (W - w) / 2, H - 16 - size - 16
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle((s(x0), s(y0), s(x0 + w), s(H - 10)), s(20), fill=(255, 255, 255, 120), outline=(255, 255, 255, 170), width=s(1))
    img.alpha_composite(layer)
    for k, icon in enumerate(icons):
        icon(img, x0 + 14 + k * (size + gap), y0 + 8, size)


def desk(size=(1100, 720)):
    """La scrivania senza il compagno, al doppio della grandezza: la dispensa a destra, gli appunti a sinistra, la barra dei menu e il Dock.
    È la stessa per tutte le immagini del README (la GIF qui sotto, e la scheda e il giro in compone_readme.py, che sono più grandi:
    le finestre restano al centro, le colline e il Dock si allargano)."""
    global W, H
    saved, (W, H) = (W, H), size
    try:
        dx = (W - 1100) / 2
        img = wallpaper()
        d = window(img, (600 + dx, 62, 1056 + dx, 336), "Dispensa di fisiologia")
        text(d, (628 + dx, 120), "Il potenziale d'azione", face(NY, 21, 600), (50, 40, 40))
        body_lines(d, 628 + dx, 156, ["Quando lo stimolo supera la soglia, i canali", "del sodio si aprono e la membrana si",
                                      "depolarizza: il segnale corre lungo l'assone."], size=13.5)
        neuron(d, 690 + dx, 284, 14)
        text(d, (880 + dx, 300), "fig. 3.2", face(SF, 11.5, 400), (150, 140, 136))
        d = window(img, (44 + dx, 84, 600 + dx, 404), "Anatomia · appunti")
        text(d, (78 + dx, 144), "Il sistema nervoso", face(NY, 30, 650), (38, 32, 32))
        body_lines(d, 78 + dx, 196, ["Il sistema nervoso centrale comprende l'encefalo", "e il midollo spinale. Riceve le informazioni dai",
                                     "nervi e prepara le risposte. Le cellule principali", "sono i neuroni: ognuno ha un corpo, i dendriti",
                                     "che ricevono i segnali e un assone."])
        d.rounded_rectangle((s(78 + dx), s(360), s(176 + dx), s(382)), s(11), fill=(255, 233, 196))
        text(d, (90 + dx, 363), "da ripassare", face(SF, 12.5, 600), (176, 104, 36))
        d.rounded_rectangle((s(184 + dx), s(360), s(258 + dx), s(382)), s(11), fill=(220, 236, 226))
        text(d, (196 + dx, 363), "esame", face(SF, 12.5, 600), (60, 130, 90))
        menubar(img)
        dock(img)
        return img
    finally:
        W, H = saved


# ---------------------------------------------------------------------------------------------------------------------------------------------------
# L'animazione.

def cursor_image():
    """La freccia del mouse (nera, con il bordo bianco e un'ombra leggera), con la punta in (0, 0)."""
    pts = [(0, 0), (0, 17), (4.2, 13.1), (7, 19.6), (9.6, 18.5), (6.9, 12.2), (12.4, 12.2)]
    pad = 6
    img = Image.new("RGBA", (s(26), s(32)), (0, 0, 0, 0))
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(s(x + pad + 0.6), s(y + pad + 1.4)) for x, y in pts], fill=(0, 0, 0, 90))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(s(1.2))))
    d = ImageDraw.Draw(img)
    d.polygon([(s(x + pad), s(y + pad)) for x, y in pts], fill=(10, 10, 10), outline=(255, 255, 255), width=s(1.4))
    return img, (s(pad), s(pad))


def ease_out(p):
    return 1 - (1 - p) ** 3


def ease_in_out(p):
    return 3 * p * p - 2 * p * p * p


def scrivania(out_gif="docs/images/scrivania.gif", out_png="docs/images/scrivania.png"):
    ppt = 1.0                       # pixel per punto: il compagno è largo 144 punti
    fps, total = 20, 12.0
    speed = 42 * ppt                # punti al secondo, com'è nell'app
    curtain = 0.35                  # la tendina dell'orologio (Pomodoro.curtainDuration)
    linger = 1.0                    # resta aperta un secondo dopo che il mouse è uscito (Pomodoro.hoverLinger)
    intro_until = 2.0               # all'inizio l'orologio è aperto (i primi minuti del focus), poi si chiude
    speak = (4.0, 7.0)              # mentre parla sta fermo, come nell'app
    feet, x0 = 552, 640

    scene = desk()
    k = (144 / 360) * ppt * S
    def scaled(im):
        return im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    walk = [scaled(Image.open(f"assets/gattino/frame{n}.png").convert("RGBA")) for n in range(2, 8)]
    still = scaled(Image.open("assets/gattino/frame1.png").convert("RGBA"))
    ground = round(0.0949 * 274 * k)                    # quanto sta sotto i piedi, nell'immagine
    bubble = Image.open("build/readme/bubble1.png").convert("RGBA")
    bubble = bubble.resize((round(bubble.width * ppt / 3 * S), round(bubble.height * ppt / 3 * S)), Image.LANCZOS)
    def clock_for(t):
        seconds = 24 * 60 + 10 - int(t)
        c = Image.open(f"build/readme/timer_{seconds // 60:02d}{seconds % 60:02d}.png").convert("RGBA")
        return c.resize((round(c.width * ppt / 3 * S), round(c.height * ppt / 3 * S)), Image.LANCZOS)
    arrow, tip = cursor_image()

    # il cursore: entra da destra, si posa sul compagno mentre parla, poi se ne va (in punti dello schermo, con il tempo)
    def x_at(t):
        moving = min(t, speak[0]) + max(0.0, t - speak[1])
        return x0 + speed * moving
    rest = (x_at(speak[0]) + 4, feet - 52)
    cursor_path = [(4.7, (W + 30, 640)), (5.6, rest), (8.0, rest), (8.6, (rest[0] - 150, H + 30))]   # se ne va verso il basso, a sinistra: il compagno resta fuori dal suo percorso
    def cursor_at(t):
        if t < cursor_path[0][0] or t > cursor_path[-1][0]:
            return None
        for (ta, pa), (tb, pb) in zip(cursor_path, cursor_path[1:]):
            if ta <= t <= tb:
                p = ease_in_out((t - ta) / (tb - ta)) if tb > ta else 1
                return (pa[0] + (pb[0] - pa[0]) * p, pa[1] + (pb[1] - pa[1]) * p)
        return None

    frames = []
    reveal, target, start_value, started = 0.0, 1.0, 0.0, 0.0       # la tendina si apre all'inizio, come quando parte un focus
    hover_until = -1.0
    for n in range(int(total * fps)):
        t = n / fps
        speaking = speak[0] <= t < speak[1]
        x = x_at(t)
        sprite = still if speaking else walk[int(t / 0.15) % len(walk)]
        left = s(x) - sprite.width // 2
        top = s(feet) + ground - sprite.height
        art = (left / S, top / S, (left + sprite.width) / S, (top + sprite.height) / S)
        cur = cursor_at(t)
        if cur and art[0] <= cur[0] <= art[2] and art[1] <= cur[1] <= art[3]:
            hover_until = t + linger
        wanted = 1.0 if (t < intro_until or t < hover_until) else 0.0
        if wanted != target:                                         # la tendina riparte da dove si trova
            target, start_value, started = wanted, reveal, t
        p = min((t - started) / curtain, 1.0)
        eased = ease_out(p) if target == 1 else p ** 3                # si apre decelerando, si chiude accelerando
        reveal = start_value + (target - start_value) * eased

        frame = scene.copy()
        sh = Image.new("RGBA", frame.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((left + s(14), s(feet) - s(8), left + sprite.width - s(14), s(feet) + s(5)), fill=(50, 40, 40, 70))
        frame.alpha_composite(sh.filter(ImageFilter.GaussianBlur(s(4))))
        frame.alpha_composite(sprite, (left, top))
        if reveal > 0.005:                                           # la tendina: si vede la parte alta dell'orologio, che cresce verso il basso
            clock = clock_for(t)
            shown = max(1, round(clock.height * reveal))
            frame.alpha_composite(clock.crop((0, 0, clock.width, shown)), (s(x) - clock.width // 2, s(feet) + ground - s(8)))
        if speaking:
            alpha = min((t - speak[0]) / 0.3, (speak[1] - t) / 0.3, 1.0)
            if alpha > 0:
                b = bubble.copy()
                b.putalpha(b.getchannel("A").point(lambda v: int(v * alpha)))
                head = left + round(sprite.width * 0.74)
                frame.alpha_composite(b, (head - round(b.width * 0.825), top + s(32) - b.height))
        if cur:
            frame.alpha_composite(arrow, (s(cur[0]) - tip[0], s(cur[1]) - tip[1]))
        frames.append(frame.convert("RGB").resize((W, H), Image.LANCZOS))

    # Una sola tavolozza per tutti i fotogrammi; lo sfondo è fermo, quindi è quantizzato una volta sola e in ogni fotogramma cambia
    # solo il riquadro che si muove (così il cielo non sfarfalla e la GIF resta leggera).
    background = scene.convert("RGB").resize((W, H), Image.LANCZOS)
    montage = Image.new("RGB", (W, H * 4))
    for i, index in enumerate((10, 60, 110, 125)):
        montage.paste(frames[index], (0, i * H))
    palette = montage.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    q_background = background.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG)
    from PIL import ImageChops
    quantized = []
    for frame in frames:
        q = q_background.copy()
        box = ImageChops.difference(frame, background).getbbox()
        if box:
            box = (max(0, box[0] - 2), max(0, box[1] - 2), min(W, box[2] + 2), min(H, box[3] + 2))
            q.paste(frame.crop(box).quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG), box[:2])
        quantized.append(q)
    quantized[0].save(out_gif, save_all=True, append_images=quantized[1:], duration=round(1000 / fps), loop=0, optimize=False, disposal=1)
    frames[round(6.2 * fps)].save(out_png, optimize=True)                # il fermo immagine: parla, con il cursore sopra e l'orologio aperto
    print("scrivania.gif", W, H, len(frames), "fotogrammi")
