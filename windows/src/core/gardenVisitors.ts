// Gli ospiti: un animaletto che passa a trovarti sull'isola, a seconda della stagione, dell'ora e di cosa c'è. Come GardenVisitors.swift. Niente `node:*`.

import { itemWithId } from "./gardenCatalog.ts";
import { route } from "./gardenCompanions.ts";
import { cornerWithId } from "./gardenCorners.ts";
import { mixedHash } from "./gardenDrops.ts";
import { isWalkable } from "./gardenGrid.ts";
import type { GardenPlacement, GardenTile } from "./gardenGrid.ts";
import type { Season } from "./gardenSky.ts";

export type GardenDaySlot = "morning" | "day" | "evening" | "night";

/** 6–10 mattina, 10–17 giorno, 17–21 sera, il resto notte. */
export function daySlotOf(hour: number): GardenDaySlot {
  if (hour >= 6 && hour < 10) return "morning";
  if (hour >= 10 && hour < 17) return "day";
  if (hour >= 17 && hour < 21) return "evening";
  return "night";
}

export interface GardenVisitorHaunt { corner: string; item: string }

export interface GardenVisitor {
  id: string;
  /** Col suo articolo: «Il pettirosso», «L'anatroccolo». */
  name: string;
  feminine: boolean;
  /** I comuni vengono se c'è una di queste cose sull'isola… */
  items: readonly string[];
  /** …i rari se si è formato uno di questi angoli. */
  haunts: readonly GardenVisitorHaunt[];
  seasons: readonly Season[];
  slots: readonly GardenDaySlot[];
  height: number;
  weight: number;
}

export const isRareVisitor = (v: GardenVisitor): boolean => v.items.length === 0;
/** L'immagine: `assets/giardino/visitatore_<id>.png`. */
export const visitorImage = (v: GardenVisitor): string => "visitatore_" + v.id;
/** «venuto» o «venuta». */
export const visitorCame = (v: GardenVisitor): string => (v.feminine ? "venuta" : "venuto");

const ALL_SEASONS: readonly Season[] = ["spring", "summer", "autumn", "winter"];
const NOT_WINTER: readonly Season[] = ["spring", "summer", "autumn"];

const visitor = (id: string, name: string, feminine: boolean, items: string[], haunts: GardenVisitorHaunt[], seasons: readonly Season[],
  slots: GardenDaySlot[], height: number, weight: number): GardenVisitor => ({ id, name, feminine, items, haunts, seasons, slots, height, weight });

export const GARDEN_VISITORS: readonly GardenVisitor[] = [
  visitor("pettirosso", "Il pettirosso", false, ["bagnetto", "casetta-uccelli"], [], ALL_SEASONS, ["morning", "day", "evening"], 50, 1),
  visitor("cinciallegra", "La cinciallegra", true, ["casetta-uccelli", "girasole"], [], ALL_SEASONS, ["morning", "day"], 46, 1),
  visitor("coniglio", "Il coniglio", false, ["trifoglio", "aiuola", "lattuga"], [], NOT_WINTER, ["morning", "evening"], 62, 1),
  visitor("lumaca", "La lumaca", true, ["funghi", "felci", "mucchio-foglie"], [], ["spring", "autumn"], ["morning", "evening"], 32, 1),
  visitor("rana", "La rana", true, ["bagnetto", "ponticello", "annaffiatoio", "laghetto"], [], ["spring", "summer"], ["evening"], 36, 1),
  visitor("anatroccolo", "L'anatroccolo", false, ["ponticello", "bagnetto"], [], ["spring"], ["morning", "day"], 42, 1),
  visitor("lucertola", "La lucertola", true, ["panchina", "tunnel"], [], ["summer"], ["day"], 30, 1),
  // la lepre ha preso il posto della tartaruga, diventata una compagna
  visitor("lepre", "La lepre", true, ["sdraio", "picnic"], [], ["spring", "summer"], ["day"], 70, 1),
  visitor("topolino", "Il topolino", false, ["cesto-carote", "picnic"], [], ["autumn", "winter"], ["evening"], 30, 1),
  visitor("scoiattolo", "Lo scoiattolo", false, ["altalena", "amaca", "tiragraffi"], [], ["spring", "autumn"], ["morning", "day"], 66, 1),
  visitor("civetta", "La civetta", true, [], [{ corner: "lettura", item: "panchina" }], ALL_SEASONS, ["night"], 60, 0.4),
  visitor("volpe", "La volpe", true, [], [{ corner: "te", item: "tavolino" }, { corner: "festa", item: "picnic" }], ALL_SEASONS, ["evening", "night"], 86, 0.4),
];

export function visitorWithId(id: string): GardenVisitor | undefined { return GARDEN_VISITORS.find((v) => v.id === id); }

/** Chi potrebbe venire e vicino a quale copia si fermerebbe, con il motivo: una cosa (`item`) o un angolo (`corner`). */
export interface Attraction { visitor: GardenVisitor; placement: GardenPlacement; item: string; corner: string | null }

export function attractions(placements: readonly GardenPlacement[], formed: ReadonlyMap<string, readonly string[]>, season: Season, slot: GardenDaySlot): Attraction[] {
  const result: Attraction[] = [];
  for (const v of GARDEN_VISITORS) {
    if (!v.seasons.includes(season) || !v.slots.includes(slot)) continue;
    if (isRareVisitor(v)) {
      for (const haunt of v.haunts) {
        const members = formed.get(haunt.corner);
        const placement = members ? placements.find((p) => members.includes(p.id) && p.item === haunt.item) : undefined;
        if (!placement) continue;
        result.push({ visitor: v, placement, item: haunt.item, corner: haunt.corner });
        break;
      }
    } else {
      for (const wanted of v.items) {
        const placement = placements.find((p) => p.item === wanted);
        if (!placement) continue;
        result.push({ visitor: v, placement, item: wanted, corner: null });
        break;
      }
    }
  }
  return result;
}

/** Quanto spesso, nelle fasce in cui qualcuno potrebbe venire, viene davvero. */
export const PRESENCE_CHANCE = 0.8;

const unit = (text: string): number => mixedHash(text) / 4_294_967_296;

/** Chi viene in questa fascia di questo giorno (`day` come «2026-10-26»), o nessuno: lo stesso ogni volta che si apre il giardino. */
export function arrival(day: string, slot: GardenDaySlot, placements: readonly GardenPlacement[], formed: ReadonlyMap<string, readonly string[]>, season: Season): Attraction | null {
  const candidates = attractions(placements, formed, season, slot);
  if (candidates.length === 0 || !(unit(`ospite-presenza-${day}-${slot}`) < PRESENCE_CHANCE)) return null;
  const total = candidates.reduce((sum, c) => sum + c.visitor.weight, 0);
  const draw = unit(`ospite-scelta-${day}-${slot}`) * total;
  let sum = 0;
  for (const candidate of candidates) {
    sum += candidate.visitor.weight;
    if (draw < sum) return candidate;
  }
  return candidates[candidates.length - 1] ?? null;
}

/** Dove entra: la tessera libera sul bordo da cui la strada fino a `goal` è più vicina a `ideal` passi, e la strada (la prima è l'ingresso). */
export function entryRoute(goal: GardenTile, size: number, occupied: ReadonlySet<string>, ideal = 7, limit = 24): GardenTile[] | null {
  let best: GardenTile[] | null = null;
  for (let row = 0; row < size; row++) for (let col = 0; col < size; col++) {
    if (!(col === 0 || row === 0 || col === size - 1 || row === size - 1)) continue;
    const entry = { col, row };
    if (!isWalkable(entry, size, occupied)) continue;
    const steps = route(entry, goal, size, occupied, limit);
    if (steps === null) continue;
    const path = [entry, ...steps];
    if (best === null || Math.abs(path.length - ideal) < Math.abs(best.length - ideal)) best = path;
  }
  return best;
}

/** La riga del diario: cosa l'ha portato qui (il nome della cosa, o dell'angolo). */
export function reasonText(item: string, corner: string | null): string {
  const found = corner === null ? undefined : cornerWithId(corner);
  if (found) return found.name;
  return itemWithId(item)?.name ?? item;
}
