// Un compagno che usa una cosa del giardino: il gattino dorme nel cesto con cuscino, il porcellino fa capolino dal tunnel, Ciccio fa il bagno nel
// bagnetto. Ogni interazione è un disegno solo, la cosa con il compagno dentro (`assets/interazioni/<compagno>-<cosa>.png`): quando il compagno la usa,
// lui sparisce e il disegno della cosa diventa quello. Come GardenInteractions.swift (la prova di contratto lo confronta). Niente `node:*`.

import { applyTurn, itemWithId } from "./gardenCatalog.ts";
import { route, standingTiles } from "./gardenCompanions.ts";
import { footprintTiles, isWalkable, tileKey } from "./gardenGrid.ts";
import type { GardenPlacement, GardenTile } from "./gardenGrid.ts";

/** Cosa si vede in più mentre la usa: niente, le «z» di chi dorme, gli schizzi d'acqua. */
export type InteractionEffect = "none" | "sleep" | "splash";

export interface GardenInteraction {
  pet: string;
  item: string;
  effect: InteractionEffect;
  /** Dove sta la cosa nel disegno della scena: quanto è più grande del suo disegno di sempre, e il suo angolo in alto a sinistra, in pixel della scena. */
  scale: number;
  x: number;
  y: number;
}

const scene = (pet: string, item: string, effect: InteractionEffect, scale: number, x: number, y: number): GardenInteraction => ({ pet, item, effect, scale, x, y });

/** Le interazioni, per compagno (le misure da tools/cutout_interazioni.py; l'amaca e l'altalena sono ritagliate sul loro riquadro). */
export const GARDEN_INTERACTIONS: readonly GardenInteraction[] = [
  scene("gattino", "cesto-cuscino", "sleep", 1.687, 0, 0),
  scene("gattino", "tiragraffi", "none", 1.489, 0, 0),
  scene("gattino", "panchina", "sleep", 1.658, 0, 0),
  scene("gattino", "amaca", "sleep", 1.609, 0, 0),
  scene("porcellino", "cesto-carote", "none", 1.560, 142, 0),
  scene("porcellino", "tunnel", "none", 1.660, 5, 0),
  scene("porcellino", "picnic", "none", 1.930, 11, 0),
  scene("porcellino", "altalena", "none", 1.306, 0, 0),
  scene("ciccio", "bagnetto", "splash", 1.215, 18, 79),
  scene("ciccio", "altalena-uccelli", "none", 1.291, 13, 0),
  scene("ciccio", "casetta-uccelli", "none", 1.093, 4, 58),
  scene("ciccio", "girasole", "none", 1.083, 28, 29),
  scene("riccio", "mucchio-foglie", "none", 1.229, 69, 0),
  scene("riccio", "cassetta-mele", "none", 1.200, 0, 0),
  scene("riccio", "tronco-cavo", "sleep", 1.512, 0, 3),
  scene("riccio", "carriola-ghiande", "none", 1.347, 1, 5),
  scene("tartaruga", "sasso-sole", "sleep", 1.598, 0, 32),
  scene("tartaruga", "lattuga", "none", 0.901, 0, 82),
  scene("tartaruga", "laghetto", "none", 1.518, 1, 20),
  scene("tartaruga", "rifugio-paglia", "sleep", 1.293, 0, 0),
  // la scena dell'annaffiatoio è specchiata (Gemini l'aveva girato dall'altra parte): Pianty sta a sinistra
  scene("pianty", "annaffiatoio", "splash", 1.242, 171, 36),
  scene("pianty", "aiuola", "none", 1.461, 0, 43),
  scene("pianty", "sdraio", "sleep", 1.499, 1, 0),
  scene("pianty", "barattolo-lucciole", "none", 0.658, 43, 71),
];

export const interactionOf = (pet: string, item: string): GardenInteraction | undefined => GARDEN_INTERACTIONS.find((i) => i.pet === pet && i.item === item);

/** La chiave dell'immagine della scena (in `assets/`): `interazioni/<compagno>-<cosa>`. */
export const interactionImage = (i: GardenInteraction): string => `interazioni/${i.pet}-${i.item}`;

/** Quanti secondi ci sta: chi dorme di più. */
export const interactionDuration = (i: GardenInteraction): [number, number] => (i.effect === "sleep" ? [20, 35] : [12, 20]);

export interface InteractionCandidate { placement: GardenPlacement; interaction: GardenInteraction; route: GardenTile[] }

/** Le cose dell'isola che questo compagno sa usare, raggiungibili (fino a `limit` passi, fino a una tessera accanto), nell'ordine delle copie; non
 *  quella dell'ultima volta (come `GardenInteractions.candidates`). */
export function interactionCandidates(pet: string, placements: readonly GardenPlacement[], from: GardenTile, size: number, occupied: ReadonlySet<string>,
  last: string | null, taken: ReadonlySet<string> = new Set(), limit = 12): InteractionCandidate[] {
  const result: InteractionCandidate[] = [];
  for (const placement of placements) {
    if (placement.id === last) continue;
    const interaction = interactionOf(pet, placement.item), item = itemWithId(placement.item);
    if (!interaction || !item) continue;
    let best: GardenTile[] | null = null;
    for (const t of standingTiles(footprintTiles(applyTurn(item.footprint, placement.turned), placement), size)) {
      if (!isWalkable(t, size, occupied) || taken.has(tileKey(t))) continue;
      const way = route(from, t, size, occupied, limit);
      if (way && (best === null || way.length < best.length)) best = way;
    }
    if (best) result.push({ placement, interaction, route: best });
  }
  return result;
}

/** Sceglie fra le candidate, tutte uguali; `value` da 0 a 1. */
export function pickInteraction(candidates: readonly InteractionCandidate[], value: number): InteractionCandidate | null {
  if (candidates.length === 0) return null;
  return candidates[Math.min(Math.floor(Math.min(Math.max(value, 0), 0.999999) * candidates.length), candidates.length - 1)] ?? null;
}
