#!/usr/bin/env python3
"""Ritaglia le scene «animale + oggetto» del giardino: assets/interazioni/<compagno>_original.png -> assets/interazioni/<compagno>-<oggetto>.png

Ogni tavola (generata con Gemini) ha quattro scene in una griglia 2×2 su fondo magenta, nell'ordine di `SHEETS`: in ognuna c'è un oggetto del giardino
disegnato come il suo (assets/giardino/<oggetto>.png) e il compagno che lo usa. Nel giardino, quando il compagno usa l'oggetto, il suo disegno prende
il posto di quello dell'oggetto: per questo bisogna sapere dove sta l'oggetto dentro la scena, e quanto è grande. Lo trovo confrontando i colori
(il disegno dell'oggetto, a varie grandezze, scorre sulla scena finché i colori combaciano di più; l'animale che lo copre in parte non sposta il punto
migliore) e stampo, per ogni scena, la scala e lo spostamento: sono quelli di `GardenInteractions` (Sources/FocusFriends/GardenInteractions.swift e
windows/src/core/gardenInteractions.ts).

Il fondo si toglie come per gli oggetti (tools/cutout_giardino.py), ma tenendo i pezzi piccoli (gli schizzi d'acqua del bagnetto); ogni pezzo va alla
scena del quadrante in cui cade il suo centro (una coperta da picnic può sporgere un po' nel quadrante accanto).

Uso, dalla cartella principale:  python3 tools/cutout_interazioni.py [--preview]
"""
import importlib.util
import os
import sys

import numpy as np
from PIL import Image

DIR = "assets/interazioni"
SHEETS = {
    "gattino": ["cesto-cuscino", "tiragraffi", "panchina", "amaca"],
    "porcellino": ["cesto-carote", "tunnel", "picnic", "altalena"],
    "ciccio": ["bagnetto", "altalena-uccelli", "casetta-uccelli", "girasole"],
    "riccio": ["mucchio-foglie", "cassetta-mele", "tronco-cavo", "carriola-ghiande"],
    "tartaruga": ["sasso-sole", "lattuga", "laghetto", "rifugio-paglia"],
    "pianty": ["annaffiatoio", "aiuola", "sdraio", "barattolo-lucciole"],
}
# le cose «sul lato» (il giardino le disegna storte lungo il lato della tessera): la scena si ritaglia proprio sul riquadro dell'oggetto, così passa
# per lo stesso disegno storto e combacia (quel poco di animale che sporge si perde)
AXIAL = {"amaca", "altalena"}
# dove l'animale grande accanto confonde le sagome (e Gemini ha cambiato un po' le proporzioni dell'oggetto), la scala e l'angolo si danno a mano,
# guardandoli sovrapposti
MANUAL = {"riccio-cassetta-mele": (1.2, 0, 0)}
# dove Gemini ha disegnato l'oggetto girato dall'altra parte: la scena si specchia (il compagno passa dall'altra parte), così l'oggetto resta com'è
MIRROR = {"pianty-annaffiatoio"}
# dove l'oggetto sta da una parte e il compagno dall'altra, staccati: le sagome si confrontano solo da quella parte di questa colonna (in pixel della
# scena, già specchiata)
SIDE = {"tartaruga-lattuga": ("left", 160), "pianty-annaffiatoio": ("right", 183), "pianty-barattolo-lucciole": ("left", 250)}
MIN_PIECE = 20          # le macchioline più piccole si tolgono (gli schizzi d'acqua sono più grandi)
WORK = 0.5              # il confronto dei colori si fa a metà grandezza (veloce), poi si affina
PREVIEW = "--preview" in sys.argv

spec = importlib.util.spec_from_file_location("cutout", os.path.join(os.path.dirname(__file__), "cutout_giardino.py"))
garden = importlib.util.module_from_spec(spec)
spec.loader.exec_module(garden)


def alpha_of(rgb):
    """Quanto un pixel non è fondo magenta (come `magenta_object`, senza togliere i pezzi piccoli)."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    magenta = np.minimum(r, b) - g
    return np.clip(1 - (magenta - 60) / (170 - 60), 0, 1)


def pieces(mask):
    """I pezzi staccati (anche in diagonale): per ognuno la maschera e il centro."""
    seen = np.zeros_like(mask)
    out = []
    for y, x in zip(*np.where(mask)):
        if seen[y, x]:
            continue
        piece = garden.flood(mask & ~seen, [(y, x)], diagonal=True)
        seen |= piece
        if piece.sum() >= MIN_PIECE:
            ys, xs = np.where(piece)
            out.append((piece, xs.mean(), ys.mean()))
    return out


def cut(rgb, keep):
    """La scena ritagliata (RGBA, bordi ripuliti dal rosa) dei pixel in `keep`."""
    alpha = np.where(garden.dilate(keep, 3), alpha_of(rgb), 0)
    out = rgb.copy()
    edge = garden.dilate(alpha < 0.5, 5) & (alpha > 0.02)
    spill = np.maximum(0, np.minimum(out[..., 0], out[..., 2]) - out[..., 1])
    k = np.where(edge, 0.9, 0.0)
    out[..., 0] -= k * spill
    out[..., 2] -= k * spill
    rgba = np.dstack([np.clip(out, 0, 255), alpha * 255]).astype(np.uint8)
    return garden.crop(rgba)


def correlate(a, b):
    """La correlazione (valida, senza bordi) di `b` (piccola) su `a` (grande), con le FFT."""
    H, W = a.shape
    h, w = b.shape
    size = (H + h, W + w)
    fa = np.fft.rfft2(a, size)
    fb = np.fft.rfft2(b[::-1, ::-1], size)
    full = np.fft.irfft2(fa * fb, size)
    return full[h - 1:H, w - 1:W]


def resized(rgba, k):
    img = Image.fromarray(rgba, "RGBA")
    return np.asarray(img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)).astype(np.float64)


def locate(scene, thing, scales):
    """Dove sta `thing` (l'oggetto) dentro `scene`, per le scale date: la scala e l'angolo in alto a sinistra dove le due sagome si sovrappongono
    di più (intersezione su unione). Le sagome, non i colori: Gemini ridipinge l'oggetto con colori un po' diversi, ma la forma resta; l'animale che
    sporge fa solo da rumore. In pixel della scena."""
    s = (scene[..., 3] > 128).astype(np.float64)
    total = s.sum()
    best = None
    for k in scales:
        t = resized(thing, k)
        if t.shape[0] > s.shape[0] or t.shape[1] > s.shape[1]:
            continue
        m = (t[..., 3] > 128).astype(np.float64)
        inter = correlate(s, m)
        iou = inter / (m.sum() + total - inter)
        y, x = np.unravel_index(np.argmax(iou), iou.shape)
        if best is None or iou[y, x] > best[0]:
            best = (iou[y, x], k, x, y)
    return best


def main():
    os.makedirs("build", exist_ok=True)
    rows = []
    for pet, items in SHEETS.items():
        sheet = np.asarray(Image.open(f"{DIR}/{pet}_original.png").convert("RGB")).astype(np.float32)
        h, w, _ = sheet.shape
        mask = alpha_of(sheet) > 0.5
        groups = [np.zeros_like(mask) for _ in range(4)]
        for piece, cx, cy in pieces(mask):
            groups[(1 if cx >= w / 2 else 0) + (2 if cy >= h / 2 else 0)] |= piece
        for item, keep in zip(items, groups):
            scene = cut(sheet, keep)
            if f"{pet}-{item}" in MIRROR:
                scene = np.ascontiguousarray(scene[:, ::-1])
            Image.fromarray(scene, "RGBA").save(f"{DIR}/{pet}-{item}.png", optimize=True)
            thing = np.asarray(Image.open(f"assets/giardino/{item}.png").convert("RGBA"))
            # prima a metà grandezza e a passi larghi, poi a grandezza piena attorno al punto trovato
            # l'oggetto occupa almeno metà della larghezza della scena (o della sua altezza) e ci sta dentro: le scale possibili sono quelle
            # (senza un limite, un disegno piccolissimo trova sempre una macchia dello stesso colore)
            low = 0.5 * min(scene.shape[1] / thing.shape[1], scene.shape[0] / thing.shape[0])
            high = min(scene.shape[1] / thing.shape[1], scene.shape[0] / thing.shape[0])
            target = scene
            if f"{pet}-{item}" in SIDE:
                side, column = SIDE[f"{pet}-{item}"]
                target = scene.copy()
                if side == "left":
                    target[:, column:, 3] = 0
                else:
                    target[:, :column, 3] = 0
                width = column if side == "left" else scene.shape[1] - column
                low = 0.5 * min(width / thing.shape[1], scene.shape[0] / thing.shape[0])
            small = resized(target, WORK).astype(np.uint8)
            if f"{pet}-{item}" in MANUAL:
                k, x, y = MANUAL[f"{pet}-{item}"]
            else:
                coarse = locate(small, thing, [WORK * k for k in np.arange(low, high + 0.001, 0.02)])
                k0 = coarse[1] / WORK
                _, k, x, y = locate(target, thing, np.arange(k0 - 0.03, k0 + 0.031, 0.005))
            if item in AXIAL:
                box = (int(x), int(y), int(round(x + thing.shape[1] * k)), int(round(y + thing.shape[0] * k)))
                scene = np.asarray(Image.fromarray(scene, "RGBA").crop(box))
                Image.fromarray(scene, "RGBA").save(f"{DIR}/{pet}-{item}.png", optimize=True)
                k, x, y = scene.shape[1] / thing.shape[1], 0, 0
            rows.append((pet, item, scene.shape[1], scene.shape[0], k, x, y, thing.shape[1], thing.shape[0]))
            if PREVIEW:
                # la scena con il contorno dell'oggetto dove l'ha trovato
                t = resized(thing, k)
                preview = Image.new("RGBA", (scene.shape[1], scene.shape[0]), (214, 232, 204, 255))
                preview.alpha_composite(Image.fromarray(scene, "RGBA"))
                ghost = Image.fromarray(t.astype(np.uint8), "RGBA")
                tint = Image.new("RGBA", ghost.size, (255, 0, 0, 0))
                tint.putalpha(Image.fromarray((t[..., 3] * 0.45).astype(np.uint8)))
                preview.alpha_composite(tint, (int(x), int(y)))
                preview.save(f"build/interazione-{pet}-{item}.png")
    print("scena                          tela       scala   x     y    (oggetto)")
    for pet, item, sw, sh, k, x, y, tw, th in rows:
        print(f"{pet + '-' + item:30} {sw:4}x{sh:<4}  {k:.3f}  {x:4}  {y:4}   ({tw}x{th})")


if __name__ == "__main__":
    main()
