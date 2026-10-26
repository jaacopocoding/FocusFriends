#!/usr/bin/env python3
"""Ritaglia i pezzi del ponte: assets/giardino/ponte_original.png -> assets/giardino/ponte_<asse>_<n>.png

Il foglio ha 8 pezzi su fondo magenta #FF00FF, 4 colonne per 2 righe, ognuno nella sua cella. Ogni pezzo è un ponticello intero (due paletti per lato,
la corda in mezzo) lungo due tessere e largo una. Servono i due pezzi di mezzo (colonne 2 e 3 della riga in alto, che hanno la stessa prospettiva): messi
in fila con uno scarto di STEP pixel, i paletti di un pezzo coincidono con quelli del successivo e il ponte è continuo. I pezzi d'imbocco e di sbocco
(colonne 1 e 4) sono disegnati con un'altra inclinazione e non combaciano, la riga in basso ripete quella in alto (tranne il primo): non si usano.

  ponte_colonna_1, ponte_colonna_2   il ponte lungo le colonne (scende a destra), i due tratti da alternare
  ponte_riga_1,    ponte_riga_2      gli stessi specchiati: il ponte lungo le righe (scende a sinistra)

Il fondo si toglie come per gli oggetti del giardino (tools/cutout_giardino.py: stessa funzione); in più si toglie il rosa che resta fra i paletti e le assi.

Uso, dalla cartella principale:  python3 tools/cutout_ponte.py
"""
import importlib.util
import numpy as np
from PIL import Image

DIR = "assets/giardino"
COLUMNS, ROWS = 4, 2
# i pezzi di mezzo, nella riga in alto: (colonna del foglio, nome)
MIDDLE = [(1, "colonna_1"), (2, "colonna_2")]
# lo scarto fra un pezzo e il successivo lungo le colonne, in pixel del pezzo ritagliato (verso destra e in basso)
STEP = (122, 75)


def load_tool(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def remove_pink(rgba, garden):
    """Il rosa del fondo rimasto in buchi piccoli: via dove è ancora molto magenta, e smorzato dove lo è poco."""
    r, g, b = (rgba[..., i].astype(np.float32) for i in range(3))
    magenta = np.minimum(r, b) - g
    out = rgba.copy()
    out[..., 3] = np.where(magenta > 40, 0, out[..., 3])
    soft = (magenta > 14) & (magenta <= 40)
    spill = np.maximum(0, np.minimum(r, b) - g)
    out[..., 0] = np.where(soft, np.clip(r - spill * 0.8, 0, 255), out[..., 0])
    out[..., 2] = np.where(soft, np.clip(b - spill * 0.8, 0, 255), out[..., 2])
    return out


def main():
    garden = load_tool("tools/cutout_giardino.py", "cutout_giardino")
    scenery = load_tool("tools/cutout_paesaggio.py", "cutout_paesaggio")
    sheet = np.asarray(Image.open(f"{DIR}/ponte_original.png").convert("RGB")).astype(np.float32)
    height, width = sheet.shape[:2]
    rgba = garden.magenta_object(sheet)
    groups = scenery.components(rgba[..., 3] > 25, 4)
    print(f"{len(groups)} gruppi trovati")
    assert len(groups) == COLUMNS * ROWS, "servono otto pezzi staccati"
    for col, name in MIDDLE:
        cx, cy = (col + 0.5) * width / COLUMNS, 0.25 * height
        best = min(range(len(groups)), key=lambda i: (groups[i][1][0] - cx) ** 2 + (groups[i][1][1] - cy) ** 2)
        piece = garden.crop(remove_pink(np.where(groups[best][0][..., None], rgba, 0).astype(np.uint8), garden))
        image = Image.fromarray(piece, "RGBA")
        image.save(f"{DIR}/ponte_{name}.png", optimize=True)
        image.transpose(Image.FLIP_LEFT_RIGHT).save(f"{DIR}/ponte_{name.replace('colonna', 'riga')}.png", optimize=True)
        print(f"ponte_{name}: {piece.shape[1]}x{piece.shape[0]} (e lo specchiato ponte_{name.replace('colonna', 'riga')})")
    print(f"scarto fra un pezzo e il successivo: {STEP[0]},{STEP[1]} px (due tessere)")


if __name__ == "__main__":
    main()
