#!/usr/bin/env python3
"""Crea l'icona dell'app: assets/bonsy/stage5.png -> assets/AppIcon.icns (e assets/AppIcon.png)."""
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


icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

# Corpo: rettangolo arrotondato con gradiente verde-azzurro scuro.
body = gradient(BODY, (62, 128, 120), (18, 52, 58)).convert("RGBA")
body.alpha_composite(glow(BODY, (255, 255, 235), (BODY * 0.5, BODY * 0.12), BODY * 0.8, 0.34))
mask = Image.new("L", (BODY, BODY), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, BODY - 1, BODY - 1), RADIUS, fill=255)

# Ombra sotto la forma.
shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 120), (MARGIN, MARGIN + 14), mask)
icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
icon.paste(body, (MARGIN, MARGIN), mask)

# Bonsai adulto: ingrandito e poi riaffilato per non vedere i pixel.
spidy = Image.open("assets/bonsy/stage5.png").convert("RGBA")
target_h = 660
scale = target_h / spidy.height
spidy = spidy.resize((round(spidy.width * scale), target_h), Image.LANCZOS)
spidy = spidy.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))

x = (SIZE - spidy.width) // 2
y = MARGIN + BODY - target_h - 30

# Ombra a terra e ombra del personaggio.
ground = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ImageDraw.Draw(ground).ellipse((x + spidy.width * 0.14, y + target_h - 62, x + spidy.width * 0.86, y + target_h - 8), fill=(0, 0, 0, 110))
icon.alpha_composite(ground.filter(ImageFilter.GaussianBlur(14)))

drop = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
silhouette = Image.new("RGBA", spidy.size, (0, 0, 0, 150))
silhouette.putalpha(spidy.getchannel("A").point(lambda v: v * 150 // 255))
drop.alpha_composite(silhouette, (x + 6, y + 14))
icon.alpha_composite(drop.filter(ImageFilter.GaussianBlur(10)))
icon.alpha_composite(spidy, (x, y))

# Il personaggio non deve uscire dalla forma dell'icona.
clip = Image.new("L", (SIZE, SIZE), 0)
clip.paste(mask, (MARGIN, MARGIN))
icon.putalpha(Image.fromarray(np.minimum(np.asarray(icon.getchannel("A")), np.asarray(clip.filter(ImageFilter.GaussianBlur(0.6))))))

icon.save("assets/AppIcon.png")

# .iconset -> .icns con iconutil
tmp = tempfile.mkdtemp(suffix=".iconset")
for base in (16, 32, 128, 256, 512):
    icon.resize((base, base), Image.LANCZOS).save(os.path.join(tmp, f"icon_{base}x{base}.png"))
    icon.resize((base * 2, base * 2), Image.LANCZOS).save(os.path.join(tmp, f"icon_{base}x{base}@2x.png"))
subprocess.run(["iconutil", "-c", "icns", tmp, "-o", "assets/AppIcon.icns"], check=True)
shutil.rmtree(tmp)
print("Scritti assets/AppIcon.png e assets/AppIcon.icns")
