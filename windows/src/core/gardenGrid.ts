// L'isola a tessere, le regole di dove stanno le cose, il terreno, i sentieri, le case e il mondo con i ponti: come GardenGrid.swift.
// Una tessera ha `col` verso destra e in basso, `row` verso sinistra e in basso: (0, 0) è l'angolo in fondo. Niente `node:*`.

import { applyTurn, itemWithId } from "./gardenCatalog.ts";
import type { GardenFootprint } from "./gardenCatalog.ts";
import { mixedHash } from "./gardenDrops.ts";
import type { Season } from "./gardenSky.ts";

export interface GardenTile { col: number; row: number }

/** Una copia di un oggetto messa su un'isola: la tessera del suo angolo in fondo, e se è girata. */
export interface GardenPlacement {
  /** Un UUID in maiuscolo, come lo scrive Swift. */
  id: string;
  item: string;
  /** L'isola (l'id del compagno); vuoto = quella di casa, finché non è decisa. */
  island: string;
  col: number;
  row: number;
  turned: boolean;
}

/** Un punto del vecchio prato libero (versioni 1 e 2): frazioni della scena, x da sinistra e y dall'alto. */
export interface GardenSpot { x: number; y: number }

export const tileKey = (tile: GardenTile): string => `${tile.col},${tile.row}`;
const tile = (col: number, row: number): GardenTile => ({ col, row });
const compareRowCol = (a: GardenTile, b: GardenTile): number => (a.row - b.row) || (a.col - b.col);

// ---- il prato di prima

export const LEGACY_LAWN = { minX: 0.03, maxX: 0.97, minY: 0.56, maxY: 0.99 } as const;

// ---- l'isola

export const ISLAND_BASE_SIZE = 8;
export const ISLAND_MAX_SIZE = 10;

export function islandSizeFor(completedSpreads: number): number {
  return Math.min(ISLAND_BASE_SIZE + Math.max(completedSpreads, 0), ISLAND_MAX_SIZE);
}

/** Il vecchio sentiero fisso (vale dove non si dice l'isola: i file di prova e le prove di contratto). */
export function isLegacyPath(t: GardenTile): boolean {
  return (t.row === 3 && t.col >= 0 && t.col <= 3) || (t.col === 3 && t.row >= 3 && t.row <= 5) || (t.row === 5 && t.col >= 3);
}

/** Le tessere del vecchio sentiero, dall'ingresso all'uscita. */
export function legacyPathTiles(size: number): GardenTile[] {
  const result = [0, 1, 2, 3].map((col) => tile(col, 3));
  result.push(tile(3, 4), tile(3, 5));
  if (size > 4) for (let col = 4; col < size; col++) result.push(tile(col, 5));
  return result;
}

export function islandContains(t: GardenTile, size: number): boolean {
  return t.col >= 0 && t.row >= 0 && t.col < size && t.row < size;
}

// ---- dove stanno le cose

/** Le tessere che un oggetto occupa con l'angolo in fondo in `origin`. */
export function footprintTiles(footprint: GardenFootprint, origin: GardenTile): GardenTile[] {
  const result: GardenTile[] = [];
  for (let dc = 0; dc < footprint.cols; dc++) for (let dr = 0; dr < footprint.rows; dr++) result.push(tile(origin.col + dc, origin.row + dr));
  return result;
}

/** Le tessere occupate dalle copie (`skipping`: una da non contare, quella che si sta spostando). */
export function occupiedTiles(placements: readonly GardenPlacement[], skipping: string | null = null): Set<string> {
  const result = new Set<string>();
  for (const placement of placements) {
    if (placement.id === skipping) continue;
    const x = itemWithId(placement.item);
    if (!x) continue;
    for (const t of footprintTiles(applyTurn(x.footprint, placement.turned), placement)) result.add(tileKey(t));
  }
  return result;
}

/** Ci sta? Dentro l'isola, fuori dal sentiero (e dalla casa) e senza coprire altro. */
export function canPlaceFootprint(footprint: GardenFootprint, origin: GardenTile, size: number, occupied: ReadonlySet<string>, island: string | null = null): boolean {
  const path = island === null ? null : new Set(pathTiles(island, size).map(tileKey));
  for (const t of footprintTiles(footprint, origin)) {
    if (!islandContains(t, size) || (path === null ? isLegacyPath(t) : path.has(tileKey(t))) || occupied.has(tileKey(t))) return false;
    if (island !== null && landmarkContains(t, island)) return false;
  }
  return true;
}

export function isWalkable(t: GardenTile, size: number, occupied: ReadonlySet<string>): boolean {
  return islandContains(t, size) && !occupied.has(tileKey(t));
}

/** Tutti i posti dove si può mettere un oggetto, per righe. */
export function freeOrigins(footprint: GardenFootprint, size: number, occupied: ReadonlySet<string>, island: string | null = null): GardenTile[] {
  const result: GardenTile[] = [];
  for (let row = 0; row < size; row++) for (let col = 0; col < size; col++) {
    if (canPlaceFootprint(footprint, tile(col, row), size, occupied, island)) result.push(tile(col, row));
  }
  return result;
}

/** Le tessere a distanza `distance` (di Manhattan) da `center`, nell'ordine di riga e colonna. */
function ring(center: GardenTile, distance: number): GardenTile[] {
  const result: GardenTile[] = [];
  for (let dc = -distance; dc <= distance; dc++) {
    const remaining = distance - Math.abs(dc);
    result.push(tile(center.col + dc, center.row + remaining));
    if (remaining > 0) result.push(tile(center.col + dc, center.row - remaining));
  }
  return result.sort(compareRowCol);
}

/** Il posto libero più vicino a `desired` (a parità, il più in fondo e a sinistra), o null. */
export function nearestOrigin(desired: GardenTile, footprint: GardenFootprint, size: number, occupied: ReadonlySet<string>, island: string | null = null): GardenTile | null {
  for (let distance = 0; distance <= 2 * size; distance++) {
    const found = ring(desired, distance).find((t) => canPlaceFootprint(footprint, t, size, occupied, island));
    if (found) return found;
  }
  return null;
}

/** La tessera dove si può camminare più vicina a `desired`. */
export function nearestWalkable(desired: GardenTile, size: number, occupied: ReadonlySet<string>): GardenTile | null {
  for (let distance = 0; distance <= 2 * size; distance++) {
    const found = ring(desired, distance).find((t) => isWalkable(t, size, occupied));
    if (found) return found;
  }
  return null;
}

/** Dove cade, sull'isola, un punto del vecchio prato libero. */
export function tileFromLegacy(spot: GardenSpot, size: number): GardenTile {
  const x = Math.min(Math.max(spot.x, LEGACY_LAWN.minX), LEGACY_LAWN.maxX), y = Math.min(Math.max(spot.y, LEGACY_LAWN.minY), LEGACY_LAWN.maxY);
  const u = (x - LEGACY_LAWN.minX) / (LEGACY_LAWN.maxX - LEGACY_LAWN.minX);
  const v = (y - LEGACY_LAWN.minY) / (LEGACY_LAWN.maxY - LEGACY_LAWN.minY);
  const col = Math.floor(size * (v + u - 0.5)), row = Math.floor(size * (v - u + 0.5));
  return tile(Math.min(Math.max(col, 0), size - 1), Math.min(Math.max(row, 0), size - 1));
}

/** Dove sta un compagno finché non lo si sposta: sul sentiero, a distanza uno dall'altro. */
export function defaultCompanionTile(index: number, island: string | null = null): GardenTile {
  const slot = ((index % 4) + 4) % 4;
  if (island === null) return legacyPathTiles(ISLAND_BASE_SIZE)[[2, 4, 6, 8][slot]!]!;
  const path = pathTiles(island, ISLAND_BASE_SIZE);
  return path[Math.min(Math.trunc(path.length * [0.2, 0.4, 0.6, 0.8][slot]!), path.length - 1)]!;
}

/** Dove stanno le cose della dotazione quando si comincia. I mughetti stavano in (2, 7), dove ora passa il sentiero della Tartaruga. */
export const STARTER_ORIGINS: Readonly<Record<string, GardenTile>> = {
  margherite: tile(7, 2), trifoglio: tile(0, 7), mughetti: tile(6, 6),
};

// ---- le cose che si uniscono (la staccionata)

/** I lati del rombo da cui parte un pezzo: verso la tessera con una colonna in meno, una riga in meno, una riga in più, una colonna in più. */
export const ARM_UP_LEFT = 1, ARM_UP_RIGHT = 2, ARM_DOWN_LEFT = 4, ARM_DOWN_RIGHT = 8;

function oppositeArms(arms: number): number {
  let result = 0;
  if (arms & ARM_UP_LEFT) result |= ARM_DOWN_RIGHT;
  if (arms & ARM_DOWN_RIGHT) result |= ARM_UP_LEFT;
  if (arms & ARM_UP_RIGHT) result |= ARM_DOWN_LEFT;
  if (arms & ARM_DOWN_LEFT) result |= ARM_UP_RIGHT;
  return result;
}

/** I lati da cui parte il pezzo in `t`: verso ogni vicino uguale; senza vicini va dritto nel verso scelto girandolo, con uno solo prosegue dritto. */
export function linkArms(t: GardenTile, linked: ReadonlySet<string>, turned: boolean): number {
  let arms = 0;
  if (linked.has(tileKey(tile(t.col - 1, t.row)))) arms |= ARM_UP_LEFT;
  if (linked.has(tileKey(tile(t.col, t.row - 1)))) arms |= ARM_UP_RIGHT;
  if (linked.has(tileKey(tile(t.col, t.row + 1)))) arms |= ARM_DOWN_LEFT;
  if (linked.has(tileKey(tile(t.col + 1, t.row)))) arms |= ARM_DOWN_RIGHT;
  if (arms === 0) return turned ? ARM_UP_RIGHT | ARM_DOWN_LEFT : ARM_UP_LEFT | ARM_DOWN_RIGHT;
  return [ARM_UP_LEFT, ARM_UP_RIGHT, ARM_DOWN_LEFT, ARM_DOWN_RIGHT].includes(arms) ? arms | oppositeArms(arms) : arms;
}

// ---- il terreno

export const GRASS_COUNT = 12;
export const GRASS_WEIGHTS: readonly number[] = [0.15, 0.09, 0.12, 0.09, 0.06, 0.06, 0.05, 0.05, 0.04, 0.06, 0.02, 0.07];
export const PATH_COUNT = 8;
export const PATH_WEIGHTS: readonly number[] = [0.04, 0.14, 0.16, 0.20, 0.14, 0.08, 0.12, 0.12];
export const SNOW_WEIGHTS: readonly number[] = [0.14, 0.13, 0.07, 0.07, 0.07, 0.06, 0.05, 0.04, 0.12, 0.08, 0.04, 0.13];
export const SNOW_PATH_WEIGHTS: readonly number[] = [0.10, 0.16, 0.16, 0.22, 0.12, 0.10, 0.10, 0.04];

export const grassWeightsFor = (season: Season): readonly number[] => (season === "winter" ? SNOW_WEIGHTS : GRASS_WEIGHTS);
export const pathWeightsFor = (season: Season): readonly number[] => (season === "winter" ? SNOW_PATH_WEIGHTS : PATH_WEIGHTS);

const runLength = (index: number, line: number, tag: string): number => 2 + (mixedHash(`corsa-${tag}${line},${index}`) % 2);

function pick(col: number, row: number, salt: number, weights: readonly number[], tag: string): number {
  const total = weights.reduce((a, b) => a + b, 0);
  const draw = mixedHash(`terra-${tag}${col},${row},${salt}`) / 4_294_967_296 * total;
  let sum = 0;
  for (let index = 0; index < weights.length; index++) {
    sum += weights[index]!;
    if (draw < sum) return index;
  }
  return weights.length - 1;
}

/** La tessera del sentiero per ognuna delle prime `count` tessere del sentiero: a gruppi di 2 o 3 uguali, un gruppo diverso dal precedente. */
export function pathVariants(count: number, weights: readonly number[] = PATH_WEIGHTS, tag = ""): number[] {
  const result: number[] = [];
  let previous = -1;
  while (result.length < count) {
    const start = result.length;
    let choice = pick(start, -1, 0, weights, tag);
    for (let salt = 1; choice === previous && salt <= 4; salt++) choice = pick(start, -1, salt, weights, tag);
    const run = runLength(start, -1, tag);
    for (let i = 0; i < run && result.length < count; i++) result.push(choice);
    previous = choice;
  }
  return result;
}

/** La tessera d'erba di ogni tessera di un'isola `size × size`, per righe (`row * size + col`). */
export function grassGrid(size: number, weights: readonly number[] = GRASS_WEIGHTS, tag = ""): number[] {
  const grid = new Array<number>(size * size).fill(0);
  for (let row = 0; row < size; row++) {
    let col = 0, previous = -1;
    while (col < size) {
      const up = row > 0 ? grid[(row - 1) * size + col]! : -1;
      let choice = pick(col, row, 0, weights, tag);
      for (let salt = 1; (choice === previous || choice === up) && salt <= 4; salt++) choice = pick(col, row, salt, weights, tag);
      const run = runLength(col, row, tag);
      for (let offset = 0; offset < run; offset++) if (col + offset < size) grid[row * size + col + offset] = choice;
      previous = choice;
      col += run;
    }
  }
  return grid;
}

export const EDGE_COUNT = 3;

/** Quali delle tre strisce del bordo vanno, una dopo l'altra, su un lato dell'isola (`face` 0 = sinistro, 1 = destro): mai due uguali di seguito. */
export function edgeSequence(face: number, count: number): number[] {
  const result: number[] = [];
  for (let index = 0; index < count; index++) {
    const draw = (salt: number): number => mixedHash(`bordo-${face},${index},${salt}`) % EDGE_COUNT;
    let choice = draw(0);
    for (let salt = 1; index > 0 && choice === result[index - 1] && salt <= 4; salt++) choice = draw(salt);
    result.push(choice);
  }
  return result;
}

// ---- i dettagli sparsi sul terreno

export const DECAL_COUNT = 24;
export type DecalGroup = "tufts" | "clover" | "flowers" | "stones" | "leaves" | "petals" | "snow";
const DECAL_GROUPS: readonly DecalGroup[] = ["tufts", "clover", "flowers", "stones", "leaves", "petals", "snow"];
/** Gli indici delle immagini di ogni gruppo (`dettaglio_<n>.png`, da 0): da `from` incluso a `to` escluso. */
export const DECAL_IMAGES: Readonly<Record<DecalGroup, { from: number; to: number }>> = {
  tufts: { from: 0, to: 4 }, clover: { from: 4, to: 6 }, flowers: { from: 6, to: 10 }, stones: { from: 10, to: 13 },
  leaves: { from: 13, to: 17 }, petals: { from: 17, to: 20 }, snow: { from: 20, to: 24 },
};
/** Dove poggia sul terreno: 0 = il centro dell'immagine sta sul punto, 1 = il bordo in basso. */
export const DECAL_ANCHORS: Readonly<Record<DecalGroup, number>> = {
  tufts: 0.9, clover: 0.9, flowers: 0.9, stones: 0.75, snow: 0.7, leaves: 0.5, petals: 0.5,
};

export interface Decal { image: number; group: DecalGroup; u: number; v: number; size: number; flipped: boolean }

interface DecalRule { group: DecalGroup; chance: number; maxCount: number; size: [number, number] }
const rule = (group: DecalGroup, chance: number, maxCount: number, low: number, high: number): DecalRule => ({ group, chance, maxCount, size: [low, high] });

function decalRules(season: Season, onPath: boolean): DecalRule[] {
  if (onPath) {
    switch (season) {
      case "spring": return [rule("stones", 0.08, 1, 0.10, 0.14), rule("petals", 0.18, 1, 0.14, 0.18)];
      case "summer": return [rule("stones", 0.10, 1, 0.10, 0.14)];
      case "autumn": return [rule("leaves", 0.45, 2, 0.13, 0.17), rule("stones", 0.06, 1, 0.10, 0.14)];
      case "winter": return [rule("snow", 0.10, 1, 0.26, 0.36)];
    }
  }
  switch (season) {
    case "spring":
      return [rule("tufts", 0.40, 1, 0.28, 0.40), rule("clover", 0.10, 1, 0.26, 0.34), rule("flowers", 0.30, 2, 0.10, 0.13),
        rule("stones", 0.06, 1, 0.14, 0.20), rule("petals", 0.12, 1, 0.14, 0.18)];
    case "summer":
      return [rule("tufts", 0.40, 1, 0.28, 0.40), rule("clover", 0.10, 1, 0.26, 0.34), rule("flowers", 0.28, 2, 0.10, 0.13),
        rule("stones", 0.06, 1, 0.14, 0.20)];
    case "autumn":
      return [rule("tufts", 0.18, 1, 0.28, 0.40), rule("stones", 0.08, 1, 0.14, 0.20), rule("leaves", 0.60, 2, 0.13, 0.17),
        rule("clover", 0.04, 1, 0.26, 0.34)];
    case "winter":
      return [rule("snow", 0.22, 1, 0.30, 0.42), rule("stones", 0.05, 1, 0.14, 0.20)];
  }
}

const decalUnit = (col: number, row: number, group: DecalGroup, index: number, salt: number, tag: string): number =>
  mixedHash(`dettaglio-${tag}${col},${row},${DECAL_GROUPS.indexOf(group)},${index},${salt}`) / 4_294_967_296;

/** I dettagli sulla tessera (col, row): sempre gli stessi per la stessa tessera, stagione e tipo di tessera. */
export function decals(col: number, row: number, season: Season, onPath: boolean, tag = ""): Decal[] {
  const result: Decal[] = [];
  for (const r of decalRules(season, onPath)) {
    for (let index = 0; index < r.maxCount; index++) {
      if (!(decalUnit(col, row, r.group, index, 0, tag) < r.chance)) continue;
      const images = DECAL_IMAGES[r.group], count = images.to - images.from;
      result.push({
        image: images.from + Math.min(Math.trunc(decalUnit(col, row, r.group, index, 1, tag) * count), count - 1), group: r.group,
        u: 0.14 + decalUnit(col, row, r.group, index, 2, tag) * 0.72, v: 0.14 + decalUnit(col, row, r.group, index, 3, tag) * 0.72,
        size: r.size[0] + decalUnit(col, row, r.group, index, 4, tag) * (r.size[1] - r.size[0]),
        flipped: decalUnit(col, row, r.group, index, 5, tag) < 0.5,
      });
    }
  }
  return result;
}

// ---- la collina sotto l'isola (`collina_<stagione>.png`, con un buco a rombo in cima)

export const HILL = {
  imageWidth: 1497, imageHeight: 720,
  holeLeft: { x: 340, y: 262 }, holeRight: { x: 1158, y: 260 }, holeTop: { x: 752, y: 69 }, holeBottom: { x: 753, y: 466 },
  /** Il buco è l'86 % dell'isola: l'isola ne copre il bordo. */
  fit: 0.86,
} as const;

export interface HillFrame { x: number; y: number; width: number; height: number; scale: number }

export function hillFrame(islandLeft: { x: number; y: number }, islandRight: { x: number; y: number }): HillFrame {
  const holeWidth = HILL.holeRight.x - HILL.holeLeft.x;
  const scale = (islandRight.x - islandLeft.x) * HILL.fit / holeWidth;
  const centerX = (HILL.holeLeft.x + HILL.holeRight.x) / 2, centerY = (HILL.holeLeft.y + HILL.holeRight.y) / 2;
  const islandCenterX = (islandLeft.x + islandRight.x) / 2, islandCenterY = (islandLeft.y + islandRight.y) / 2;
  return { x: islandCenterX - centerX * scale, y: islandCenterY - centerY * scale, width: HILL.imageWidth * scale, height: HILL.imageHeight * scale, scale };
}

const holeWidth = HILL.holeRight.x - HILL.holeLeft.x;
/** Quanto è larga la collina, quanto scende sotto gli angoli laterali dell'isola, e quanto è alta dall'angolo in alto: in larghezze d'isola. */
export const HILL_WIDTH_RATIO = HILL.imageWidth * HILL.fit / holeWidth;
export const HILL_BELOW_RATIO = (HILL.imageHeight - (HILL.holeLeft.y + HILL.holeRight.y) / 2) * HILL.fit / holeWidth;
export const HILL_HEIGHT_RATIO = 0.25 + HILL_BELOW_RATIO;

// ---- le isole: una per compagno, nell'ordine dei compagni

export const ISLANDS: readonly string[] = ["pianty", "porcellino", "ciccio", "gattino", "riccio", "tartaruga"];
export const FALLBACK_HOME = "pianty";
export const isKnownIsland = (id: string): boolean => ISLANDS.includes(id);
/** Cosa si aggiunge ai sorteggi del terreno perché ogni isola abbia i suoi (quella di Pianty è com'è sempre stata). */
export const terrainTag = (id: string): string => (id === FALLBACK_HOME ? "" : id + "/");

// ---- le case: 3×3 tessere nell'angolo in alto

export const LANDMARK_SIDE = 3;
export const SHIPPED_LANDMARKS: ReadonlySet<string> = new Set(["pianty", "porcellino", "ciccio", "gattino", "riccio", "tartaruga"]);
/** Le case che ci sono adesso (le prove possono toglierle). */
export const builtLandmarks: Set<string> = new Set(SHIPPED_LANDMARKS);

export interface LandmarkArt {
  centerX: number; centerY: number; halfWidth: number; halfHeight: number;
  lights: ReadonlyArray<{ u: number; v: number; size: number }>;
}

const lights = (...values: Array<[number, number, number]>) => values.map(([u, v, size]) => ({ u, v, size }));

/** Come sta il disegno della casa rispetto alle 3×3 tessere, in pixel del disegno ritagliato (da `tools/cutout_case.py`), e dove brillano le finestre. */
export const LANDMARK_ART: Readonly<Record<string, LandmarkArt>> = {
  pianty: { centerX: 465.5, centerY: 616, halfWidth: 462, halfHeight: 270, lights: lights([0.31, 0.64, 0.75], [0.19, 0.51, 0.55], [0.70, 0.60, 0.80], [0.80, 0.52, 0.55]) },
  porcellino: { centerX: 465.5, centerY: 616, halfWidth: 462, halfHeight: 270, lights: lights([0.31, 0.38, 0.50]) },
  ciccio: { centerX: 416.5, centerY: 638, halfWidth: 413.5, halfHeight: 251.5, lights: lights([0.49, 0.63, 0.90], [0.47, 0.10, 0.35]) },
  gattino: { centerX: 416.5, centerY: 652.5, halfWidth: 413.5, halfHeight: 253.5, lights: lights([0.71, 0.57, 0.70], [0.30, 0.70, 0.35]) },
  riccio: { centerX: 479.5, centerY: 465, halfWidth: 476.5, halfHeight: 312, lights: lights([0.41, 0.33, 0.55], [0.66, 0.54, 0.60]) },
  tartaruga: { centerX: 443.5, centerY: 330, halfWidth: 440.5, halfHeight: 260, lights: lights([0.56, 0.54, 0.60], [0.28, 0.39, 0.40], [0.75, 0.42, 0.45], [0.36, 0.49, 0.30]) },
};

export function landmarkTiles(island: string): GardenTile[] {
  if (!builtLandmarks.has(island)) return [];
  const result: GardenTile[] = [];
  for (let row = 0; row < LANDMARK_SIDE; row++) for (let col = 0; col < LANDMARK_SIDE; col++) result.push(tile(col, row));
  return result;
}

export function landmarkContains(t: GardenTile, island: string): boolean {
  return builtLandmarks.has(island) && t.col >= 0 && t.row >= 0 && t.col < LANDMARK_SIDE && t.row < LANDMARK_SIDE;
}

// ---- il mondo: le isole in una griglia di celle, con un ponte fra due celle vicine

export interface GardenBridge {
  first: string;
  second: string;
  /** Le due isole stanno una di seguito all'altra lungo le colonne (il ponte scende verso destra), o lungo le righe. */
  alongColumns: boolean;
}

export const bridgeId = (bridge: GardenBridge): string => `${bridge.first}-${bridge.second}`;
export const bridgeTouches = (bridge: GardenBridge, island: string): boolean => bridge.first === island || bridge.second === island;

export const WORLD_GAP = 4;
export const WORLD_CELL = ISLAND_MAX_SIZE + WORLD_GAP;

const SLOTS: Readonly<Record<string, GardenTile>> = {
  pianty: tile(0, 0), porcellino: tile(1, 0), ciccio: tile(0, 1), gattino: tile(1, 1), riccio: tile(2, 1), tartaruga: tile(2, 0),
};
const slotList = Object.values(SLOTS);

export function worldSlot(island: string): GardenTile | null { return SLOTS[island] ?? null; }

/** Quante tessere è largo e alto il mondo (un quadrato che contiene tutte le celle). */
export const WORLD_EXTENT = Math.max(...slotList.map((s) => Math.max(s.col, s.row))) * WORLD_CELL + ISLAND_MAX_SIZE;

/** Quanto arriva il mondo sullo schermo, in tessere dal vertice (0, 0): a sinistra, a destra e in basso. */
export const WORLD_REACH = (() => {
  const across = slotList.map((s) => (s.col - s.row) * WORLD_CELL), down = slotList.map((s) => (s.col + s.row) * WORLD_CELL);
  return { left: Math.min(...across) - ISLAND_MAX_SIZE, right: Math.max(...across) + ISLAND_MAX_SIZE, depth: Math.max(...down) + ISLAND_MAX_SIZE };
})();

/** Il vertice «in alto» di un'isola, in colonne e righe del mondo. */
export function islandCorner(island: string): { col: number; row: number } | null {
  const slot = SLOTS[island];
  return slot ? { col: slot.col * WORLD_CELL, row: slot.row * WORLD_CELL } : null;
}

/** I ponti, sempre nello stesso ordine (le isole come stanno in `ISLANDS`). */
export const BRIDGES: readonly GardenBridge[] = (() => {
  const result: GardenBridge[] = [];
  for (const first of ISLANDS) for (const second of ISLANDS) {
    const a = SLOTS[first], b = SLOTS[second];
    if (!a || !b) continue;
    if (b.col === a.col + 1 && b.row === a.row) result.push({ first, second, alongColumns: true });
    else if (b.row === a.row + 1 && b.col === a.col) result.push({ first, second, alongColumns: false });
  }
  return result;
})();

/** La striscia che un ponte deve coprire: lungo il suo asse da `from` a `to`, e sull'altro asse `across` (il centro della tessera d'approdo). */
export function bridgeSpan(bridge: GardenBridge, firstSize: number): { from: number; to: number; across: number } | null {
  const a = islandCorner(bridge.first), b = islandCorner(bridge.second), slot = SLOTS[bridge.first];
  if (!a || !b || !slot) return null;
  const landing = PATH_LANDING_INDEX + 0.5;
  if (bridge.alongColumns) return { from: a.col + firstSize, to: b.col, across: slot.row * WORLD_CELL + landing };
  return { from: a.row + firstSize, to: b.row, across: slot.col * WORLD_CELL + landing };
}

/** I ponti fra due isole aperte che non sono già costruiti. */
export function pendingBridges(open: ReadonlySet<string>, built: ReadonlySet<string>): GardenBridge[] {
  return BRIDGES.filter((b) => open.has(b.first) && open.has(b.second) && !built.has(bridgeId(b)));
}

/** Le isole aperte che non hanno ancora ricevuto il regalo di benvenuto, tranne quella di casa. */
export function newcomers(open: ReadonlySet<string>, welcomed: ReadonlySet<string>, home: string): string[] {
  return ISLANDS.filter((id) => id !== home && open.has(id) && !welcomed.has(id));
}

export const BRIDGE_PIECE_LENGTH = 2;

/** I centri dei pezzi di un ponte lungo da `from` a `to`, lungo l'asse. */
export function bridgePieceCenters(from: number, to: number): number[] {
  const count = Math.max(Math.ceil(Math.max(to - from, 0) / BRIDGE_PIECE_LENGTH), 1);
  const middle = (from + to) / 2;
  return Array.from({ length: count }, (_, i) => middle + (i - (count - 1) / 2) * BRIDGE_PIECE_LENGTH);
}

// ---- il sentiero di ogni isola: una curva larga fra le due tessere dove arrivano i suoi ponti

/** La fila (o colonna) dove un ponte tocca l'isola, contando da zero dal bordo vicino. */
export const PATH_LANDING_INDEX = 5;

export type PathFace = "colStart" | "colEnd" | "rowStart" | "rowEnd";
export interface PathLanding { face: PathFace; tile: GardenTile }

/** Dove arrivano i ponti di un'isola, nell'ordine dei ponti del mondo. */
export function pathLandings(island: string, size: number): PathLanding[] {
  const last = Math.max(size - 1, 0), at = Math.min(PATH_LANDING_INDEX, last);
  const result: PathLanding[] = [];
  for (const bridge of BRIDGES) {
    if (bridge.first === island) {
      result.push(bridge.alongColumns ? { face: "colEnd", tile: tile(last, at) } : { face: "rowEnd", tile: tile(at, last) });
    }
    if (bridge.second === island) {
      result.push(bridge.alongColumns ? { face: "colStart", tile: tile(0, at) } : { face: "rowStart", tile: tile(at, 0) });
    }
  }
  return result;
}

function inward(face: PathFace): { col: number; row: number } {
  switch (face) {
    case "colStart": return { col: 1, row: 0 };
    case "colEnd": return { col: -1, row: 0 };
    case "rowStart": return { col: 0, row: 1 };
    case "rowEnd": return { col: 0, row: -1 };
  }
}

const unit = (text: string): number => mixedHash(text) / 4_294_967_296;
const pathCache = new Map<string, GardenTile[]>();

/** Le tessere del sentiero di un'isola grande `size`, dal primo approdo al secondo. Un'isola che non c'è: il vecchio sentiero. */
export function pathTiles(island: string, size: number): GardenTile[] {
  const key = `${island}|${size}`;
  let known = pathCache.get(key);
  if (!known) {
    known = generatePath(island, size);
    pathCache.set(key, known);
  }
  return known;
}

export function pathContains(t: GardenTile, island: string, size: number): boolean {
  return pathTiles(island, size).some((x) => x.col === t.col && x.row === t.row);
}

function generatePath(island: string, size: number): GardenTile[] {
  const full = generateFullPath(island);
  if (size >= ISLAND_MAX_SIZE) return full;
  const tiles = full.filter((t) => islandContains(t, size));
  const known = new Set(tiles.map(tileKey));
  for (const landing of pathLandings(island, size)) if (!known.has(tileKey(landing.tile))) addSpur(landing, tiles, known);
  return tiles;
}

const inLandmarkCorner = (t: GardenTile): boolean => t.col < LANDMARK_SIDE && t.row < LANDMARK_SIDE;

function generateFullPath(island: string): GardenTile[] {
  const all = pathLandings(island, ISLAND_MAX_SIZE);
  const first = all[0];
  if (!first) return legacyPathTiles(ISLAND_MAX_SIZE);
  const lands = all.length === 1 ? [first, plannedLanding(first)] : all.slice(0, 2);
  let best: GardenTile[] = [];
  let curve: GardenTile[] | null = null;
  for (let attempt = 0; attempt < 9; attempt++) {
    best = generateCurve(island, lands, 1 + 0.08 * attempt);
    if (!best.some(inLandmarkCorner)) {
      curve = best;
      break;
    }
  }
  const tiles = curve ?? best.filter((t) => !inLandmarkCorner(t));
  const known = new Set(tiles.map(tileKey));
  for (const landing of all.slice(2)) if (!known.has(tileKey(landing.tile))) addSpur(landing, tiles, known);
  return tiles;
}

/** Il secondo approdo di un'isola con un ponte solo: sul lato vicino, nello stesso punto dove un ponte la toccherebbe. */
function plannedLanding(landing: PathLanding): PathLanding {
  const at = landing.tile.col === 0 || landing.tile.col === ISLAND_MAX_SIZE - 1 ? landing.tile.row : landing.tile.col;
  return landing.face === "colStart" || landing.face === "colEnd" ? { face: "rowStart", tile: tile(at, 0) } : { face: "colStart", tile: tile(0, at) };
}

/** Un tratto dritto dall'approdo fino alla tessera del sentiero più vicina (si aggiungono solo tessere). */
function addSpur(landing: PathLanding, tiles: GardenTile[], known: Set<string>): void {
  const distance = (t: GardenTile): number => Math.abs(t.col - landing.tile.col) + Math.abs(t.row - landing.tile.row);
  let nearest: GardenTile | null = null;
  for (const t of tiles) if (nearest === null || distance(t) < distance(nearest)) nearest = t;
  if (nearest === null) {
    tiles.push(landing.tile);
    known.add(tileKey(landing.tile));
    return;
  }
  let current = landing.tile;
  const added = [current];
  const step = (from: number, to: number): number => (from === to ? from : from + (to > from ? 1 : -1));
  if (inward(landing.face).col !== 0) {
    while (current.col !== nearest.col) { current = tile(step(current.col, nearest.col), current.row); added.push(current); }
    while (current.row !== nearest.row) { current = tile(current.col, step(current.row, nearest.row)); added.push(current); }
  } else {
    while (current.row !== nearest.row) { current = tile(current.col, step(current.row, nearest.row)); added.push(current); }
    while (current.col !== nearest.col) { current = tile(step(current.col, nearest.col), current.row); added.push(current); }
  }
  for (const t of added.reverse()) {
    if (known.has(tileKey(t))) continue;
    tiles.push(t);
    known.add(tileKey(t));
  }
}

function generateCurve(island: string, lands: readonly PathLanding[], stretch: number): GardenTile[] {
  const size = ISLAND_MAX_SIZE, n = size;
  const center = (t: GardenTile) => ({ col: t.col + 0.5, row: t.row + 0.5 });
  const p0 = center(lands[0]!.tile), p3 = center(lands[1]!.tile);
  const d0 = inward(lands[0]!.face), d3 = inward(lands[1]!.face);
  const reach = n * (0.30 + 0.30 * unit("sentiero-entra-" + island)) * stretch;
  const skew0 = n * (unit("sentiero-piega-a-" + island) - 0.5) * 0.9;
  const skew3 = n * (unit("sentiero-piega-b-" + island) - 0.5) * 0.9;
  const p1 = { col: p0.col + d0.col * reach - d0.row * skew0, row: p0.row + d0.row * reach + d0.col * skew0 };
  const p2 = { col: p3.col + d3.col * reach - d3.row * skew3, row: p3.row + d3.row * reach + d3.col * skew3 };
  const frequency = 1 + unit("sentiero-onda-" + island);
  const phase = unit("sentiero-fase-" + island);
  const steps = 80;
  const samples: Array<{ col: number; row: number; radius: number }> = [];
  for (let s = 0; s <= steps; s++) {
    const t = s / steps, u = 1 - t;
    const col = u * u * u * p0.col + 3 * u * u * t * p1.col + 3 * u * t * t * p2.col + t * t * t * p3.col;
    const row = u * u * u * p0.row + 3 * u * u * t * p1.row + 3 * u * t * t * p2.row + t * t * t * p3.row;
    samples.push({ col, row, radius: 0.95 + 0.42 * (0.5 + 0.5 * Math.sin(2 * Math.PI * (frequency * t + phase))) });
  }
  const found: Array<{ tile: GardenTile; order: number }> = [];
  for (let row = 0; row < size; row++) for (let col = 0; col < size; col++) {
    const c = { col: col + 0.5, row: row + 0.5 };
    let best = Infinity, bestStep = 0;
    samples.forEach((sample, index) => {
      const margin = Math.sqrt((c.col - sample.col) * (c.col - sample.col) + (c.row - sample.row) * (c.row - sample.row)) - sample.radius;
      if (margin < best) { best = margin; bestStep = index; }
    });
    if (best <= 0) found.push({ tile: tile(col, row), order: bestStep });
  }
  const tiles = found.sort((a, b) => (a.order - b.order) || (a.tile.row - b.tile.row) || (a.tile.col - b.tile.col)).map((x) => x.tile);
  for (const landing of lands) if (!tiles.some((t) => t.col === landing.tile.col && t.row === landing.tile.row)) tiles.push(landing.tile);
  return tiles;
}
