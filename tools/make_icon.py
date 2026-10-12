#!/usr/bin/env python3
"""Crea l'icona dell'app FocusFriends: assets/AppIcon.png, assets/AppIcon.icns e docs/images/logo.png.

Parte dal disegno del logo (assets/logo_original.png: un pomodoro-timer con picciolo e foglie, l'anello arancio
che mostra il tempo e lo spicchio crema che resta), lo mette nella forma delle icone di macOS (quadrato con
angoli molto arrotondati, con un bordo attorno e una leggera ombra) e scrive tutte le misure dell'.icns.
"""
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
MARGIN = 100            # macOS lascia un bordo attorno alla forma
BODY = SIZE - 2 * MARGIN
RADIUS = 185            # raggio degli angoli (forma "squircle" approssimata)
SOURCE = "assets/logo_original.png"


def make():
    art = Image.open(SOURCE).convert("RGBA").resize((BODY, BODY), Image.LANCZOS)

    mask = Image.new("L", (BODY, BODY), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, BODY - 1, BODY - 1), RADIUS, fill=255)

    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 120), (MARGIN, MARGIN + 14), mask)
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    icon.paste(art, (MARGIN, MARGIN), mask)

    return icon


icon = make()
icon.save("assets/AppIcon.png")
icon.save("docs/images/logo.png")      # la copia che mostra il README

# .iconset -> .icns con iconutil
tmp = tempfile.mkdtemp(suffix=".iconset")
for base in (16, 32, 128, 256, 512):
    icon.resize((base, base), Image.LANCZOS).save(os.path.join(tmp, f"icon_{base}x{base}.png"))
    icon.resize((base * 2, base * 2), Image.LANCZOS).save(os.path.join(tmp, f"icon_{base}x{base}@2x.png"))
subprocess.run(["iconutil", "-c", "icns", tmp, "-o", "assets/AppIcon.icns"], check=True)
shutil.rmtree(tmp)
print("Scritti assets/AppIcon.png e assets/AppIcon.icns")
