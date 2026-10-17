// Più schermi: dove sta il compagno e come passa dall'uno all'altro (la finestra trasparente sta su uno schermo alla volta e si sposta
// con lui). Solo geometria, senza Electron, così si prova con schermi inventati.

export interface Rect { x: number; y: number; width: number; height: number }

export interface DisplayInfo {
  id: number;
  /** L'area di lavoro (senza la barra delle applicazioni), in punti. */
  workArea: Rect;
  /** Lo schermo intero, in punti. */
  bounds: Rect;
  primary: boolean;
}

const contains = (rect: Rect, x: number, y: number): boolean => x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height;

/** Quanto un punto dista da un rettangolo (0 se è dentro). */
function distance(rect: Rect, x: number, y: number): number {
  const dx = Math.max(rect.x - x, 0, x - (rect.x + rect.width - 1));
  const dy = Math.max(rect.y - y, 0, y - (rect.y + rect.height - 1));
  return Math.hypot(dx, dy);
}

/** Lo schermo che contiene il punto (o, se sta nella barra delle applicazioni o fuori da tutti, quello più vicino). */
export function displayAt(displays: readonly DisplayInfo[], x: number, y: number): DisplayInfo | null {
  const inside = displays.find((d) => contains(d.bounds, x, y));
  if (inside) return inside;
  let best: DisplayInfo | null = null, bestDistance = Infinity;
  for (const display of displays) {
    const d = distance(display.bounds, x, y);
    if (d < bestDistance) { best = display; bestDistance = d; }
  }
  return best;
}

/** Il compagno si sta trascinando: il cursore è su un altro schermo? Ritorna quello, altrimenti null. */
export function displayToFollow(displays: readonly DisplayInfo[], currentId: number, cursor: { x: number; y: number }): DisplayInfo | null {
  const target = displayAt(displays, cursor.x, cursor.y);
  return target !== null && target.id !== currentId ? target : null;
}

/** Lo schermo su cui sta il compagno, o il principale se non c'è più (scollegato). */
export function currentOrPrimary(displays: readonly DisplayInfo[], currentId: number | null): DisplayInfo | null {
  return displays.find((d) => d.id === currentId) ?? displays.find((d) => d.primary) ?? displays[0] ?? null;
}

/** Un rettangolo dello schermo (l'icona nell'area di notifica) nelle coordinate della finestra, che comincia all'angolo dell'area di lavoro. */
export function relativeTo(rect: Rect, workArea: Rect): Rect {
  return { x: rect.x - workArea.x, y: rect.y - workArea.y, width: rect.width, height: rect.height };
}

/** Dove aprire la scheda rispetto a un'icona: sopra/sotto/di fianco al suo lato della barra, centrata sull'icona (e dentro l'area di lavoro). */
export function cardPlacement(anchor: Rect, scene: { width: number; height: number }, card: { width: number; height: number }, margin = 6): { left: number; top: number } {
  const cx = anchor.x + anchor.width / 2, cy = anchor.y + anchor.height / 2;
  const clampX = (x: number): number => Math.min(Math.max(x, 8), Math.max(scene.width - card.width - 8, 8));
  const clampY = (y: number): number => Math.min(Math.max(y, 8), Math.max(scene.height - card.height - 8, 8));
  if (cy >= scene.height) return { left: clampX(cx - card.width / 2), top: clampY(scene.height - margin - card.height) };      // barra in basso
  if (cy < 0) return { left: clampX(cx - card.width / 2), top: clampY(margin) };                                                  // barra in alto
  if (cx >= scene.width) return { left: clampX(scene.width - margin - card.width), top: clampY(cy - card.height / 2) };          // barra a destra
  if (cx < 0) return { left: clampX(margin), top: clampY(cy - card.height / 2) };                                                 // barra a sinistra
  return { left: clampX(cx - card.width / 2), top: clampY(anchor.y - margin - card.height) };                                     // l'icona sta dentro l'area di lavoro
}
