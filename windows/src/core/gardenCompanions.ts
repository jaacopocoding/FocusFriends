// Cosa fanno i compagni sull'isola: le pose negli angoli che gli piacciono, i fotogrammi di ogni posa, dove stare vicino a una cosa e la strada
// per arrivarci. Come GardenCompanions.swift. Niente `node:*`.

import { islandContains, isWalkable, tileKey } from "./gardenGrid.ts";
import type { GardenTile } from "./gardenGrid.ts";

export type GardenPose = "sleep" | "eat" | "popcorn" | "wings" | "groom";
export const GARDEN_POSES: readonly GardenPose[] = ["sleep", "eat", "popcorn", "wings", "groom"];

/** Quanti fotogrammi al secondo. */
export const POSE_FPS: Readonly<Record<GardenPose, number>> = { sleep: 3, eat: 5, popcorn: 8, wings: 8, groom: 4 };
/** Quanti secondi dura, da un minimo a un massimo. */
export const POSE_DURATION: Readonly<Record<GardenPose, [number, number]>> = {
  sleep: [14, 24], eat: [8, 13], popcorn: [6, 10], wings: [7, 11], groom: [8, 12],
};

export interface GardenAffinity { pet: string; corner: string; item: string; pose: GardenPose }

const affinity = (pet: string, corner: string, item: string, pose: GardenPose): GardenAffinity => ({ pet, corner, item, pose });

export const AFFINITIES: readonly GardenAffinity[] = [
  affinity("gattino", "gatto", "casetta-gatto", "sleep"),
  affinity("gattino", "lettura", "panchina", "groom"),
  affinity("gattino", "salotto", "cesto-cuscino", "sleep"),
  affinity("porcellino", "orto", "aiuola", "eat"),
  affinity("porcellino", "porcellino", "casetta-porcellino", "popcorn"),
  affinity("porcellino", "festa", "picnic", "popcorn"),
  affinity("porcellino", "picnic", "picnic", "eat"),
  affinity("ciccio", "uccelli", "bagnetto", "wings"),
  affinity("ciccio", "festa", "bandierine", "wings"),
  affinity("ciccio", "vento", "altalena-uccelli", "wings"),
  affinity("riccio", "tana", "tana-foglie", "sleep"),
  affinity("riccio", "dispensa", "cassetta-mele", "eat"),
  affinity("riccio", "bosco", "felci", "popcorn"),
  affinity("tartaruga", "rifugio", "rifugio-paglia", "sleep"),
  affinity("tartaruga", "fragole", "aiuola-fragole", "eat"),
  affinity("tartaruga", "acqua", "ponticello", "popcorn"),
];

const POSE_FRAMES: Readonly<Record<string, [number, number]>> = {
  "gattino/eat": [8, 12], "gattino/sleep": [13, 18], "gattino/groom": [19, 23],
  "porcellino/eat": [6, 10], "porcellino/sleep": [11, 14], "porcellino/popcorn": [15, 19],
  "ciccio/wings": [8, 13],
  "riccio/eat": [8, 12], "riccio/sleep": [13, 18], "riccio/popcorn": [19, 23],
  "tartaruga/eat": [8, 12], "tartaruga/sleep": [13, 18], "tartaruga/popcorn": [19, 23],
};

/** I numeri di fotogramma (da 1, come `frame<n>.png`) di una posa per un compagno; vuoto se non la fa. */
export function poseFrames(pet: string, pose: GardenPose): number[] {
  const range = POSE_FRAMES[`${pet}/${pose}`];
  if (!range) return [];
  return Array.from({ length: range[1] - range[0] + 1 }, (_, i) => range[0] + i);
}

/** Il fotogramma della posa al tempo `time` (`<compagno>/frame<n>`), o null se quel compagno non la fa. */
export function poseImage(pet: string, pose: GardenPose, time: number): string | null {
  const numbers = poseFrames(pet, pose);
  if (numbers.length === 0) return null;
  const step = Math.floor(time * POSE_FPS[pose]);
  return `${pet}/frame${numbers[((step % numbers.length) + numbers.length) % numbers.length]}`;
}

/** Le tessere attorno a un ingombro (anche in diagonale) dentro l'isola, per righe. */
export function standingTiles(footprint: readonly GardenTile[], size: number): GardenTile[] {
  const own = new Set(footprint.map(tileKey));
  const around = new Map<string, GardenTile>();
  for (const t of footprint) for (let dc = -1; dc <= 1; dc++) for (let dr = -1; dr <= 1; dr++) {
    const near = { col: t.col + dc, row: t.row + dr };
    if (!own.has(tileKey(near)) && islandContains(near, size)) around.set(tileKey(near), near);
  }
  return [...around.values()].sort((a, b) => (a.row - b.row) || (a.col - b.col));
}

/** La strada più corta (in su, in giù, a destra o a sinistra) da `from` a `to` senza passare sugli oggetti: senza la partenza e con l'arrivo;
 *  vuota se già ci si è; null se non c'è (o è più lunga di `limit`). */
export function route(from: GardenTile, to: GardenTile, size: number, occupied: ReadonlySet<string>, limit = 16): GardenTile[] | null {
  if (!isWalkable(to, size, occupied) || !isWalkable(from, size, occupied)) return null;
  if (from.col === to.col && from.row === to.row) return [];
  const previous = new Map<string, GardenTile>();
  const seen = new Set([tileKey(from)]);
  let frontier: GardenTile[] = [from];
  for (let depth = 0; frontier.length > 0 && depth < limit;) {
    depth += 1;
    const next: GardenTile[] = [];
    for (const t of frontier) {
      for (const [dc, dr] of [[1, 0], [-1, 0], [0, 1], [0, -1]] as const) {
        const step = { col: t.col + dc, row: t.row + dr };
        if (seen.has(tileKey(step)) || !isWalkable(step, size, occupied)) continue;
        seen.add(tileKey(step));
        previous.set(tileKey(step), t);
        if (step.col === to.col && step.row === to.row) {
          const path = [step];
          for (let before = previous.get(tileKey(path[0]!)); before && !(before.col === from.col && before.row === from.row); before = previous.get(tileKey(path[0]!))) {
            path.unshift(before);
          }
          return path;
        }
        next.push(step);
      }
    }
    frontier = next;
  }
  return null;
}
