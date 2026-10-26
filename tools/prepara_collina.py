#!/usr/bin/env python3
"""Prepara la collina sotto l'isola: assets/giardino/collina_original.png (il disegno di Gemini, una collina su magenta) -> collina_<stagione>.png

Gemini ha dipinto la collina in prospettiva isometrica, con un rombo MAGENTA in cima (largo il doppio dell'altezza, come le nostre tessere) dove sta l'isola.
Si fa questo:
1. si toglie il magenta (tools/cutout_giardino.py) e si tiene il pezzo più grande; il buco in cima è la parte trasparente non collegata al bordo;
2. i pendii sono più alti di quanto serve: la parte sotto il fondo del buco si accorcia (`SQUASH`); sopra non si tocca, quindi il buco resta un rombo 2:1;
3. il contorno scuro attorno al buco si toglie (l'erba vicina lo ricopre), così fra le tessere e il pendio non c'è nessun distacco;
4. il contorno esterno resta netto sui fianchi (una linea marrone sottile: via la sfumatura viola lasciata dal magenta) e sfuma morbido solo in basso, dove la
   collina si perde nel prato;
5. si ritaglia sul contenuto e si scrive collina_autunno.png; le altre stagioni (collina_primavera.png, collina_estate.png, collina_inverno.png) per ora
   si ricavano da questa cambiando i colori (finché Gemini non ne dipinge di vere: stesso nome, stesse misure, stesso buco).
Si stampano la misura dell'immagine e i quattro angoli del buco: stanno in `GardenHill` (GardenGrid.swift) e servono a mettere l'isola nel buco.

Uso, dalla cartella principale:  python3 tools/prepara_collina.py
"""
import importlib.util
import numpy as np
from PIL import Image, ImageFilter

DIR = "assets/giardino"
SQUASH = 0.5          # quanto si accorcia la parte dei pendii sotto il buco
PAD = 6
UPSCALE = 1.5         # il disegno di Gemini è piccolo (una collina larga ~1000 px): si ingrandisce con Lanczos e si rende più nitido, perché a schermo si vede a 1,5-3 volte


def load_tools():
    spec = importlib.util.spec_from_file_location("cutout_giardino", "tools/cutout_giardino.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def blur(plane, radius):
    return np.asarray(Image.fromarray(np.clip(plane, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))).astype(np.float32)


def dilate(mask, n):
    return np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * n + 1))) > 127


def cut_hill(garden):
    """Il disegno senza magenta (RGBA)."""
    sheet = np.asarray(Image.open(f"{DIR}/collina_original.png").convert("RGB")).astype(np.float32)
    rgba = garden.magenta_object(sheet)
    alpha = rgba[..., 3] > 25
    labels = np.zeros(alpha.shape, np.int32)
    sizes = {}
    for y, x in zip(*np.where(alpha)):
        if labels[y, x]:
            continue
        region = garden.flood(alpha, [(y, x)], diagonal=True)
        labels[region] = len(sizes) + 1
        sizes[len(sizes) + 1] = int(region.sum())
    keep = labels == max(sizes, key=sizes.get)      # eventuali scritte restano fuori
    rgba[..., 3] = np.where(keep, rgba[..., 3], 0)
    return rgba


def hole_of(alpha, garden):
    outside = garden.flood(alpha < 8, [(0, 0)])
    return outside, (alpha < 8) & ~outside


def corners(hole):
    ys, xs = np.where(hole)
    left = (int(xs.min()), int(ys[xs == xs.min()].mean()))
    right = (int(xs.max()), int(ys[xs == xs.max()].mean()))
    top = (int(xs[ys == ys.min()].mean()), int(ys.min()))
    bottom = (int(xs[ys == ys.max()].mean()), int(ys.max()))
    return left, top, right, bottom


def prepare(garden):
    rgba = cut_hill(garden)
    # (1) senza la sfumatura viola del magenta: il blu non supera il verde, il rosso non esagera
    rgba[..., 2] = np.minimum(rgba[..., 2], rgba[..., 1] * 0.92 + 4)
    rgba[..., 0] = np.minimum(rgba[..., 0], rgba[..., 1] * 1.28 + 14)
    outside, hole = hole_of(rgba[..., 3], garden)
    left, top, right, bottom = corners(hole)
    # (2) i pendii sotto il fondo del buco si accorciano
    image = Image.fromarray(rgba.astype(np.uint8), "RGBA")
    upper = image.crop((0, 0, image.width, bottom[1]))
    lower = image.crop((0, bottom[1], image.width, image.height))
    lower = lower.resize((lower.width, max(1, int(lower.height * SQUASH))), Image.LANCZOS)
    joined = Image.new("RGBA", (image.width, upper.height + lower.height), (0, 0, 0, 0))
    joined.alpha_composite(upper, (0, 0))
    joined.alpha_composite(lower, (0, bottom[1]))
    A = np.asarray(joined).astype(np.float32)
    alpha = A[..., 3]
    outside, hole = hole_of(alpha, garden)
    band_outer = dilate(outside, 5)                  # il contorno esterno
    band_hole = dilate(hole, 4)                      # il contorno del buco
    core = (alpha >= 8) & ~band_outer & ~band_hole
    cf = core.astype(np.float32)
    weight = blur(cf * 255, 6.5) / 255 + 1e-3
    fill = np.stack([blur(A[..., c] * cf, 6.5) / weight for c in range(3)], axis=-1)
    # (4) il fianco netto: la linea scura diventa marrone
    sharp = A.copy()
    luma = 0.3 * A[..., 0] + 0.59 * A[..., 1] + 0.11 * A[..., 2]
    dark = (alpha >= 8) & band_outer & (luma < 135)
    brown = np.minimum(np.stack([luma + 12, luma * 0.74 + 6, luma * 0.55 + 2], axis=-1), 120)
    sharp[..., :3] = np.where(dark[..., None], brown, sharp[..., :3])
    # (3) niente linea attorno al buco
    sharp[..., :3] = np.where((band_hole & ~hole & (alpha >= 8))[..., None], fill, sharp[..., :3])
    # la versione sfumata, per il bordo di sotto
    soft = A.copy()
    recolor = ~core & ~hole & (weight > 0.02)
    soft[..., :3] = np.where(recolor[..., None], fill, soft[..., :3])
    body = Image.fromarray((((alpha >= 8) | hole) * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(4.7))
    soft[..., 3] = np.where(hole, 0, np.asarray(body).astype(np.float32))
    # quanto è «in basso»: dove, poco sotto il bordo, c'è il fuori (sui fianchi sotto c'è ancora collina)
    below_outside = np.zeros_like(outside)
    below_outside[:-9] = outside[9:]
    weight_soft = np.clip(blur((below_outside & dilate(outside, 7)).astype(np.float32) * 255, 8.5) / 255 * 1.8, 0, 1)[..., None]
    mixed = sharp * (1 - weight_soft) + soft * weight_soft
    mixed[..., 3] = np.where(hole, 0, mixed[..., 3])
    # la base: l'alpha scende piano negli ultimi pixel
    rows = np.arange(mixed.shape[0])[:, None]
    mixed[..., 3] *= np.clip((mixed.shape[0] - rows) / (0.10 * mixed.shape[0]), 0, 1) ** 0.8
    out = Image.fromarray(mixed.clip(0, 255).astype(np.uint8), "RGBA")
    box = out.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
    x0, y0 = max(box[0] - PAD, 0), max(box[1] - PAD, 0)
    out = out.crop((x0, y0, min(box[2] + PAD, out.width), min(box[3] + PAD, out.height)))
    shifted = [(p[0] - x0, p[1] - y0) for p in (left, top, right, bottom)]
    if UPSCALE != 1:
        # più grande e più nitido: l'alpha si ingrandisce com'è (è già morbida), i colori si rinforzano con una maschera di nitidezza
        size = (int(round(out.width * UPSCALE)), int(round(out.height * UPSCALE)))
        alpha_big = out.getchannel("A").resize(size, Image.LANCZOS)
        rgb_big = out.convert("RGB").resize(size, Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=2.0, percent=110, threshold=2))
        out = rgb_big.convert("RGBA")
        out.putalpha(alpha_big)
        shifted = [(int(round(p[0] * UPSCALE)), int(round(p[1] * UPSCALE))) for p in shifted]
    return out, shifted


def seasonal(autumn, name):
    """Le altre stagioni, dai colori dell'autunno (provvisorie: Gemini le può dipingere di nuovo)."""
    rgb = autumn.convert("RGB").convert("HSV")
    h, s, v = [np.asarray(c).astype(np.float32) for c in rgb.split()]
    if name == "primavera":
        h = (h + 25) % 256; s = np.clip(s * 0.56, 0, 255); v = np.clip(v * 1.06 + 10, 0, 255)
    elif name == "estate":
        h = (h + 30) % 256; s = np.clip(s * 0.64, 0, 255); v = np.clip(v * 0.94 + 4, 0, 255)
    elif name == "inverno":
        # neve: chiara e azzurrina, con le pennellate che restano visibili
        rgb = np.asarray(autumn.convert("RGB")).astype(np.float32)
        lum = (0.3 * rgb[..., 0] + 0.59 * rgb[..., 1] + 0.11 * rgb[..., 2]) / 255
        lum = np.clip((lum - 0.25) / 0.7, 0, 1)
        snow = np.array([238, 244, 250], np.float32)
        shade = np.array([158, 176, 204], np.float32)
        base = shade + (snow - shade) * lum[..., None] ** 0.8
        out = Image.fromarray(base.clip(0, 255).astype(np.uint8), "RGB")
        out.putalpha(autumn.getchannel("A"))
        return out
    out = Image.merge("HSV", [Image.fromarray(c.astype(np.uint8)) for c in (h, s, v)]).convert("RGB")
    out.putalpha(autumn.getchannel("A"))
    return out


def main():
    garden = load_tools()
    autumn, (left, top, right, bottom) = prepare(garden)
    autumn.save(f"{DIR}/collina_autunno.png", optimize=True)
    for name in ("primavera", "estate", "inverno"):
        seasonal(autumn, name).save(f"{DIR}/collina_{name}.png", optimize=True)
    print(f"collina: {autumn.width}x{autumn.height}")
    print(f"buco: sinistro {left}, alto {top}, destro {right}, basso {bottom}  (larghezza {right[0] - left[0]}, altezza {bottom[1] - top[1]}, rapporto {(right[0] - left[0]) / (bottom[1] - top[1]):.3f})")
    print("per GardenHill (GardenGrid.swift):")
    print(f"    static let imageWidth = {autumn.width}.0, imageHeight = {autumn.height}.0")
    print(f"    static let holeLeft = (x: {left[0]}.0, y: {left[1]}.0), holeRight = (x: {right[0]}.0, y: {right[1]}.0)")
    print(f"    static let holeTop = (x: {top[0]}.0, y: {top[1]}.0), holeBottom = (x: {bottom[0]}.0, y: {bottom[1]}.0)")


if __name__ == "__main__":
    main()
