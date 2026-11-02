// Gli «angoli» del giardino: certe cose messe vicine fanno qualcosa insieme (il tavolino e la sdraio fanno l'angolo del tè). Come GardenCorners.swift.
// Niente `node:*`.

import { applyTurn, itemWithId } from "./gardenCatalog.ts";
import type { GardenCategory } from "./gardenCatalog.ts";
import type { GardenPlacement } from "./gardenGrid.ts";

/** Di cosa ha bisogno un angolo: una copia di uno qualunque di questi oggetti, o tanti oggetti diversi di una scheda. */
export type CornerNeed = { oneOf: readonly string[] } | { different: GardenCategory; count: number };

export interface GardenCorner { id: string; name: string; needs: readonly CornerNeed[] }

/** Quanto vicine devono stare: ognuna a non più di due tessere da quella «di mezzo», contando i bordi dell'ingombro. */
export const CORNER_REACH = 2;

const one = (...items: string[]): CornerNeed => ({ oneOf: items });
const corner = (id: string, name: string, ...needs: CornerNeed[]): GardenCorner => ({ id, name, needs });

export const GARDEN_CORNERS: readonly GardenCorner[] = [
  corner("te", "L'angolo del tè", one("tavolino"), one("sdraio")),
  corner("lettura", "L'angolo di lettura", one("panchina"), one("lampione")),
  corner("orto", "L'orto", one("aiuola"), one("annaffiatoio")),
  corner("gatto", "L'angolo del gatto", one("casetta-gatto"), one("tiragraffi"), one("cesto-cuscino")),
  corner("porcellino", "La casa del porcellino", one("casetta-porcellino"), one("tunnel"), one("cesto-carote")),
  corner("uccelli", "L'angolo degli uccelli", one("bagnetto"), one("casetta-uccelli"), one("altalena-uccelli")),
  corner("prato-fiorito", "Il prato fiorito", { different: "flowers", count: 4 }),
  corner("bosco", "L'angolo del bosco", one("funghi"), one("felci"), one("mughetti")),
  corner("festa", "La festa in giardino", one("bandierine"), one("picnic"), one("tavolino")),
  corner("rose", "L'arco delle rose", one("arco-rose"), one("panchina", "ponticello")),
  // Due per isola, ognuno con una cosa del suo animale
  corner("vivaio", "Il vivaio", one("aiuola"), one("lavanda"), one("tulipani")),
  corner("acqua", "L'angolo dell'acqua", one("annaffiatoio"), one("ponticello"), one("felci")),
  corner("picnic", "Il picnic", one("picnic"), one("cesto-carote")),
  corner("recinto", "Il recinto", one("casetta-porcellino"), one("cancelletto"), one("trifoglio")),
  corner("vento", "La musica del vento", one("carillon"), one("altalena-uccelli")),
  corner("bagno-sole", "Il bagno al sole", one("bagnetto"), one("sdraio"), one("girasole")),
  corner("salotto", "Il salotto del gatto", one("cesto-cuscino"), one("tavolino"), one("lampione")),
  corner("palestra", "La palestra del gatto", one("tiragraffi"), one("amaca")),
  // Il Riccio, sulla sua isola
  corner("tana", "La tana d'autunno", one("tana-foglie"), one("mucchio-foglie"), one("tronco-cavo")),
  corner("dispensa", "La dispensa d'autunno", one("cassetta-mele"), one("carriola-ghiande"), one("zucca-lanterna")),
  // La Tartaruga, sulla sua isola
  corner("rifugio", "Il rifugio della tartaruga", one("rifugio-paglia"), one("sasso-sole"), one("lanterna-carta")),
  corner("fragole", "L'orto delle fragole", one("aiuola-fragole"), one("lattuga"), one("laghetto")),
];

export function cornerWithId(id: string): GardenCorner | undefined { return GARDEN_CORNERS.find((c) => c.id === id); }

function box(placement: GardenPlacement): { col0: number; col1: number; row0: number; row1: number } | null {
  const x = itemWithId(placement.item);
  if (!x) return null;
  const footprint = applyTurn(x.footprint, placement.turned);
  return { col0: placement.col, col1: placement.col + footprint.cols - 1, row0: placement.row, row1: placement.row + footprint.rows - 1 };
}

/** La distanza fra due copie in tessere (la maggiore tra colonne e righe): 1 se si toccano, 0 se sono la stessa. */
export function cornerDistance(a: GardenPlacement, b: GardenPlacement): number {
  const first = box(a), second = box(b);
  if (first === null || second === null) return Number.MAX_SAFE_INTEGER;
  if (a.id === b.id) return 0;
  const dCol = Math.max(0, Math.max(first.col0 - second.col1, second.col0 - first.col1));
  const dRow = Math.max(0, Math.max(first.row0 - second.row1, second.row0 - first.row1));
  return Math.max(dCol, dRow, 1);
}

function fulfil(needs: readonly CornerNeed[], candidates: readonly GardenPlacement[]): GardenPlacement[] | null {
  const used = new Set<string>();
  const members: GardenPlacement[] = [];
  for (const need of needs) {
    if ("oneOf" in need) {
      const found = candidates.find((c) => !used.has(c.id) && need.oneOf.includes(c.item));
      if (!found) return null;
      used.add(found.id);
      members.push(found);
    } else {
      const seen = new Set<string>();
      const picked: GardenPlacement[] = [];
      for (const candidate of candidates) {
        if (used.has(candidate.id)) continue;
        const x = itemWithId(candidate.item);
        if (!x || x.category !== need.different || seen.has(candidate.item)) continue;
        seen.add(candidate.item);
        picked.push(candidate);
        if (picked.length === need.count) break;
      }
      if (picked.length !== need.count) return null;
      for (const p of picked) used.add(p.id);
      members.push(...picked);
    }
  }
  return members;
}

/** Gli angoli che le copie di un'isola formano adesso: per ognuno, le copie che lo formano (nell'ordine dell'elenco). */
export function formedCorners(placements: readonly GardenPlacement[]): Map<string, string[]> {
  const result = new Map<string, string[]>();
  for (const c of GARDEN_CORNERS) {
    for (const center of placements) {
      const near = placements.filter((p) => cornerDistance(center, p) <= CORNER_REACH);
      const members = fulfil(c.needs, near);
      if (members === null) continue;
      const ids = new Set(members.map((m) => m.id));
      result.set(c.id, placements.filter((p) => ids.has(p.id)).map((p) => p.id));
      break;
    }
  }
  return result;
}
