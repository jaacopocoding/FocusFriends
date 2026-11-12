// Dove compare la figurina di fine focus (GiftPlacement in BubblePlacement.swift): di fianco al compagno, dal lato con più spazio, con il fondo
// all'altezza dei suoi piedi. Se lì c'è la scheda «Com'è andata?» (che compare insieme), dall'altro lato; se anche lì non c'è posto, sopra il compagno.
// Solo calcoli: si collauda da sola (test/schermi.test.ts) e dà gli stessi risultati del Mac.

export const GIFT_WIDTH = 112, GIFT_HEIGHT = 138;
const WIDTH = GIFT_WIDTH, HEIGHT = GIFT_HEIGHT;

export type Box = { left: number; top: number; width: number; height: number };

/** La posizione (in punti della pagina, dall'alto) della figurina. */
export function giftPosition(pet: Box, feetY: number, scene: { width: number; height: number }, avoid: Box | null): { left: number; top: number } {
  const top = Math.min(Math.max(feetY - 6 - HEIGHT, 6), scene.height - HEIGHT - 6);
  const beside = (right: boolean): { left: number; top: number } => {
    const left = right ? pet.left + pet.width + 4 : pet.left - WIDTH - 4;
    return { left: Math.min(Math.max(left, 6), scene.width - WIDTH - 6), top };
  };
  const overlaps = (a: Box, b: Box): boolean => a.left < b.left + b.width && b.left < a.left + a.width && a.top < b.top + b.height && b.top < a.top + a.height;
  const inner = { left: pet.left + 8, top: pet.top + 8, width: pet.width - 16, height: pet.height - 16 };
  const free = (p: { left: number; top: number }): boolean => {
    const box = { ...p, width: WIDTH, height: HEIGHT };
    return !overlaps(box, inner) && !(avoid !== null && overlaps(box, avoid));
  };
  const preferRight = pet.left + pet.width / 2 < scene.width / 2;
  for (const right of [preferRight, !preferRight]) if (free(beside(right))) return beside(right);
  if (avoid === null) return beside(preferRight);
  const left = Math.min(Math.max(pet.left + pet.width / 2 - WIDTH / 2, 6), scene.width - WIDTH - 6);
  return { left, top: Math.max(pet.top - HEIGHT - 4, 6) };
}
