#!/usr/bin/env python3
"""Crea l'icona dell'app FocusFriends: assets/AppIcon.png e assets/AppIcon.icns.

Un anello che si riempie (il timer del focus) con i tre amici davanti: Pianty al centro, Ciccio a sinistra,
il Porcellino a destra. Usa i fotogrammi "fermo" già ritagliati in assets/.
"""
import math
import os
import shutil
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
MARGIN = 100            # macOS lascia un bordo attorno alla forma
BODY = SIZE - 2 * MARGIN
RADIUS = 185            # raggio degli angoli (forma "squircle" approssimata)

PIANTY = "assets/pianty/stage5_1.png"
CICCIO = "assets/ciccio/frame1.png"
PORCELLINO = "assets/porcellino/frame1.png"


def gradient(size, top, bottom):
    """Gradiente verticale."""
    t = np.linspace(0, 1, size)[:, None, None]
    top, bottom = np.array(top, dtype=np.float32), np.array(bottom, dtype=np.float32)
    arr = (top * (1 - t) + bottom * t).repeat(size, axis=1)
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def glow(size, color, center, radius, strength):
    """Alone radiale morbido, come luce dall'alto."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.sqrt((x - center[0]) ** 2 + (y - center[1]) ** 2) / radius
    a = np.clip(1 - d, 0, 1) ** 2 * strength
    layer = Image.new("RGBA", (size, size), color + (0,))
    layer.putalpha(Image.fromarray((a * 255).astype(np.uint8)))
    return layer


def load(path, height):
    """Il personaggio ritagliato sul suo contorno, alto `height`, un po' riaffilato."""
    im = Image.open(path).convert("RGBA")
    im = im.crop(im.getbbox())
    k = height / im.height
    im = im.resize((round(im.width * k), height), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=2, percent=50, threshold=2))
    # Sul fondo scuro l'ultimo pixel del bordo (sfumatura col bianco del disegno) si vedrebbe come un alone chiaro.
    alpha = im.getchannel("A").filter(ImageFilter.MinFilter(3))
    im.putalpha(alpha)
    return im


def paste_shadowed(canvas, im, xy, alpha=110, blur=10, dx=5, dy=12):
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sil = Image.new("RGBA", im.size, (0, 0, 0, alpha))
    sil.putalpha(im.getchannel("A").point(lambda v: v * alpha // 255))
    shadow.alpha_composite(sil, (xy[0] + dx, xy[1] + dy))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    canvas.alpha_composite(im, xy)


def ground_shadow(canvas, cx, y, width, alpha=70):
    g = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse((cx - width / 2, y - width * 0.07, cx + width / 2, y + width * 0.07), fill=(0, 0, 0, alpha))
    canvas.alpha_composite(g.filter(ImageFilter.GaussianBlur(10)))


def ring(layer, cx, cy, r, w, start, end, color, track):
    """Arco con le estremità arrotondate (a 3x per i bordi lisci), sopra una pista più chiara."""
    k = 3
    big = Image.new("RGBA", (layer.width * k, layer.height * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.arc(((cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k), 0, 360, fill=track, width=int(w * k))
    d.arc(((cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k), start, end, fill=color, width=int(w * k))
    for ang in (start, end):
        px, py = cx + r * math.cos(math.radians(ang)), cy + r * math.sin(math.radians(ang))
        d.ellipse(((px - w / 2) * k, (py - w / 2) * k, (px + w / 2) * k, (py + w / 2) * k), fill=color)
    layer.alpha_composite(big.resize(layer.size, Image.LANCZOS))


def make():
    # Corpo: rettangolo arrotondato con gradiente crema-pesca e una luce dall'alto.
    body = gradient(BODY, (255, 244, 224), (247, 214, 178)).convert("RGBA")
    body.alpha_composite(glow(BODY, (255, 255, 255), (BODY * 0.5, BODY * 0.1), BODY * 0.9, 0.5))
    mask = Image.new("L", (BODY, BODY), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, BODY - 1, BODY - 1), RADIUS, fill=255)

    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 120), (MARGIN, MARGIN + 14), mask)
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    icon.paste(body, (MARGIN, MARGIN), mask)

    # L'anello del focus: tre quarti pieni, il resto è la pista ancora da percorrere.
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ring(layer, SIZE / 2, SIZE / 2 + 8, 300, 44, -90, 215, (226, 128, 84, 255), (255, 255, 255, 170))
    icon.alpha_composite(layer)

    pianty = load(PIANTY, 540)
    ciccio = load(CICCIO, 215)
    porcellino = load(PORCELLINO, 195)
    floor = MARGIN + BODY

    px, py = SIZE // 2 - pianty.width // 2, floor - pianty.height - 95
    ground_shadow(icon, SIZE // 2, py + pianty.height - 6, pianty.width * 0.55)
    paste_shadowed(icon, pianty, (px, py))

    cx, cy = MARGIN + 34, floor - ciccio.height - 70
    ground_shadow(icon, cx + ciccio.width * 0.55, cy + ciccio.height * 0.75, ciccio.width * 0.6)
    paste_shadowed(icon, ciccio, (cx, cy))

    rx, ry = SIZE // 2 + pianty.width // 2 - 85, floor - porcellino.height - 62
    ground_shadow(icon, rx + porcellino.width * 0.5, ry + porcellino.height * 0.9, porcellino.width * 0.8)
    paste_shadowed(icon, porcellino, (rx, ry))

    # Niente deve uscire dalla forma dell'icona.
    clip = Image.new("L", (SIZE, SIZE), 0)
    clip.paste(mask, (MARGIN, MARGIN))
    icon.putalpha(Image.fromarray(np.minimum(np.asarray(icon.getchannel("A")), np.asarray(clip.filter(ImageFilter.GaussianBlur(0.6))))))
    return icon


icon = make()
icon.save("assets/AppIcon.png")

# .iconset -> .icns con iconutil
tmp = tempfile.mkdtemp(suffix=".iconset")
for base in (16, 32, 128, 256, 512):
    icon.resize((base, base), Image.LANCZOS).save(os.path.join(tmp, f"icon_{base}x{base}.png"))
    icon.resize((base * 2, base * 2), Image.LANCZOS).save(os.path.join(tmp, f"icon_{base}x{base}@2x.png"))
subprocess.run(["iconutil", "-c", "icns", tmp, "-o", "assets/AppIcon.icns"], check=True)
shutil.rmtree(tmp)
print("Scritti assets/AppIcon.png e assets/AppIcon.icns")
