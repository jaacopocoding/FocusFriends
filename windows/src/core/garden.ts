// Il giardino di chi usa l'app: l'album delle figurine trovate, le copie messe sulle isole, dove stanno i compagni, gli angoli, gli ospiti, i ponti.
// Sta in `giardino.json` accanto ai dati (FORMATI.md §5), con le stesse regole di Garden.swift: un file delle versioni 1–3 si porta alla 4 tenendo
// da parte l'originale, uno rovinato si mette da parte, uno più nuovo si legge senza riscriverlo. Usa `node:fs`: sta nel processo principale.

import { randomUUID } from "node:crypto";
import { copyFileSync, existsSync, renameSync, rmSync } from "node:fs";
import { join } from "node:path";
import { readText, stringifyJson, writeFileAtomic } from "./files.ts";
import { applyTurn, completedSpreads, fitsIsland, GARDEN_ITEMS, isStarter, itemNumber, itemWithId, RETIRED_ITEMS, welcomeGift } from "./gardenCatalog.ts";
import type { GardenItem } from "./gardenCatalog.ts";
import { GARDEN_CORNERS, formedCorners } from "./gardenCorners.ts";
import { interactionOf, sceneId } from "./gardenInteractions.ts";
import { cloneDropState, credit, DROP_MINIMUM_SECONDS, DropStream, giftProgress, hash, hasSomethingToFind, isEligible, minutesToNextGift, roll, startingDropState } from "./gardenDrops.ts";
import type { GardenDrop, GardenDropState, GardenGift } from "./gardenDrops.ts";
import {
  BRIDGES, bridgeId, canPlaceFootprint, defaultCompanionTile, FALLBACK_HOME, footprintTiles, freeOrigins, ISLAND_MAX_SIZE, islandContains,
  islandSizeFor, ISLANDS, isKnownIsland, landmarkTiles, nearestOrigin, nearestWalkable, newcomers, occupiedTiles, pathTiles, pendingBridges,
  STARTER_ORIGINS, tileFromLegacy, tileKey,
} from "./gardenGrid.ts";
import type { GardenBridge, GardenPlacement, GardenSpot, GardenTile } from "./gardenGrid.ts";
import { MINIMUM_SECONDS } from "./log.ts";
import type { StudySession } from "./log.ts";

/** 4: più isole, una per compagno. */
export const GARDEN_FORMAT_VERSION = 4;
/** La versione delle regole delle isole: la 1 è «un oggetto di un animale solo sulla sua isola». */
export const ISLAND_RULES_VERSION = 1;
/** Un tetto di sicurezza alle copie su ogni isola. */
export const MAX_PLACEMENTS = 150;

/** Un ospite che ha già fatto visita: quando (come «2026-10-26»), quante volte e cosa l'aveva attirato. */
export interface GardenGuest { first: string; visits: number; reason: string }
export interface GardenGuestWelcome { isFirst: boolean; gift: GardenDrop | null }
/** Il regalo di benvenuto che arriva con il ponte di un'isola; `placement` null se non c'era posto. */
export interface GardenBridgeWelcome { island: string; item: string; placement: string | null }

/** Cosa ha fatto la sistemazione delle cose degli animali: quante copie sono passate sull'isola giusta e quante sono tornate nella cassetta. */
export interface GardenRulesReport { moved: number; returned: number }

export function rulesReportLine(report: GardenRulesReport): string {
  if (report.moved > 0 && report.returned > 0) return "Le cose degli animali sono andate sulle loro isole, o nella cassetta.";
  if (report.moved > 0) return "Le cose degli animali sono andate sulle loro isole.";
  return "Le cose di isole ancora chiuse sono tornate nella cassetta.";
}

export interface GardenOptions {
  /** L'adesso (per il nome del file rovinato messo da parte). */
  now?: () => number;
  /** Modalità sviluppatore: tutte le figurine sono nell'album. */
  developer?: () => boolean;
  /** Per provare i regali senza studiare ore: un focus da un minuto conta, e ogni minuto vale un'ora (`quickGifts` sul Mac). */
  quickGifts?: () => boolean;
  /** Gli identificativi delle copie nuove (per le prove). */
  makeId?: () => string;
}

// ---- lettura rigorosa, come il Codable di Swift: un campo del tipo sbagliato rende rovinato tutto il file

class Corrupt extends Error {}
const UUID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

type Json = Record<string, unknown>;
const isObject = (v: unknown): v is Json => typeof v === "object" && v !== null && !Array.isArray(v);

function obj(v: unknown): Json { if (!isObject(v)) throw new Corrupt(); return v; }
function int(v: unknown): number { if (typeof v !== "number" || !Number.isInteger(v)) throw new Corrupt(); return v; }
function num(v: unknown): number { if (typeof v !== "number" || !Number.isFinite(v)) throw new Corrupt(); return v; }
function str(v: unknown): string { if (typeof v !== "string") throw new Corrupt(); return v; }
function bool(v: unknown): boolean { if (typeof v !== "boolean") throw new Corrupt(); return v; }
function strings(v: unknown): string[] { if (!Array.isArray(v)) throw new Corrupt(); return v.map(str); }
/** Un campo facoltativo: assente o null = undefined; altrimenti del tipo giusto. */
function opt<T>(source: Json, key: string, decode: (v: unknown) => T): T | undefined {
  const value = source[key];
  return value === undefined || value === null ? undefined : decode(value);
}
function dict<T>(v: unknown, decode: (v: unknown) => T): Record<string, T> {
  const source = obj(v);
  const result: Record<string, T> = {};
  for (const [key, value] of Object.entries(source)) result[key] = decode(value);
  return result;
}

interface DecodedPlacement extends GardenPlacement { legacy: GardenSpot | null }
interface CompanionPlace { col?: number; row?: number; x?: number; y?: number }

function decodePlacement(raw: unknown): DecodedPlacement {
  const source = obj(raw);
  const id = str(source["id"]);
  if (!UUID_PATTERN.test(id)) throw new Corrupt();
  const item = str(source["item"]);
  const island = opt(source, "island", str) ?? "";
  const turned = opt(source, "turned", bool) ?? false;
  const col = opt(source, "col", int), row = opt(source, "row", int);
  if (col !== undefined && row !== undefined) return { id: id.toUpperCase(), item, island, col, row, turned, legacy: null };
  // un file delle versioni 1 e 2: la posizione nel prato libero
  return { id: id.toUpperCase(), item, island, col: 0, row: 0, turned, legacy: { x: num(source["x"]), y: num(source["y"]) } };
}

function decodeDrops(raw: unknown): GardenDropState {
  const source = obj(raw);
  return {
    found: dict(source["found"], int), sinceRare: int(source["sinceRare"]), sinceLegendary: int(source["sinceLegendary"]),
    studyBank: Math.max(opt(source, "studyBank", int) ?? 0, 0),
  };
}

function decodeGuest(raw: unknown): GardenGuest {
  const source = obj(raw);
  return { first: str(source["first"]), visits: int(source["visits"]), reason: str(source["reason"]) };
}

interface Contents {
  version: number;
  unlocked?: string[];
  spent?: number;
  drops?: GardenDropState;
  lastRolled?: string;
  unseen?: string[];
  pendingGifts?: number;
  legacySpent?: number;
  placements: DecodedPlacement[];
  companions: Record<string, CompanionPlace>;
  home?: string;
  corners?: string[];
  guests?: Record<string, GardenGuest>;
  scenes?: string[];
  bridges?: string[];
  welcomed?: string[];
  islandRules?: number;
  rulesNotice?: GardenRulesReport;
}

function decodeContents(raw: unknown): Contents {
  const source = obj(raw);
  if (!Array.isArray(source["placements"])) throw new Corrupt();
  const companions = dict(source["companions"], (v): CompanionPlace => {
    const place = obj(v);
    return { col: opt(place, "col", int), row: opt(place, "row", int), x: opt(place, "x", num), y: opt(place, "y", num) };
  });
  return {
    version: int(source["version"]),
    unlocked: opt(source, "unlocked", strings),
    spent: opt(source, "spent", int),
    drops: opt(source, "drops", decodeDrops),
    lastRolled: opt(source, "lastRolled", str),
    unseen: opt(source, "unseen", strings),
    pendingGifts: opt(source, "pendingGifts", int),
    legacySpent: opt(source, "legacySpent", int),
    placements: (source["placements"] as unknown[]).map(decodePlacement),
    companions,
    home: opt(source, "home", str),
    corners: opt(source, "corners", strings),
    guests: opt(source, "guests", (v) => dict(v, decodeGuest)),
    scenes: opt(source, "scenes", strings),
    bridges: opt(source, "bridges", strings),
    welcomed: opt(source, "welcomed", strings),
    islandRules: opt(source, "islandRules", int),
    rulesNotice: opt(source, "rulesNotice", (v) => { const r = obj(v); return { moved: int(r["moved"]), returned: int(r["returned"]) }; }),
  };
}

export class Garden {
  readonly directory: string;
  private readonly file: string;
  private readonly now: () => number;
  private readonly developer: () => boolean;
  private readonly quickGifts: () => boolean;
  private readonly makeId: () => string;

  private _drops: GardenDropState = startingDropState();
  private _lastRolled: string | null = null;
  private _unseen = new Set<string>();
  private _pendingGifts = 0;
  private legacySpent: number | null = null;
  private _allPlacements: GardenPlacement[] = [];
  private _home: string | null = null;
  private shown: string | null = null;
  private _companionTiles = new Map<string, GardenTile>();
  private _corners: string[] = [];
  private _guests: Record<string, GardenGuest> = {};
  private _scenes: string[] = [];
  private _bridges: string[] = [];
  private _welcomed: string[] = [];
  private bridgesUnsettled = false;
  private welcomedUnsettled = false;
  private rulesUnsettled = false;
  private rulesNotice: GardenRulesReport | null = null;
  /** Dice se un'isola è aperta (il suo compagno è sbloccato). Senza, sono tutte aperte. */
  isIslandOpen: ((island: string) => boolean) | null = null;
  private _formedCorners = new Map<string, string[]>();
  private newCorners: string[] = [];
  private observers: Array<() => void> = [];
  private _readOnly = false;
  private legacyBackupName: string | null = null;
  private pendingProblems: string[] = [];
  private problemHandler: ((message: string) => void) | undefined;
  private writeFailureReported = false;

  constructor(directory: string, options: GardenOptions = {}) {
    this.directory = directory;
    this.file = join(directory, "giardino.json");
    this.now = options.now ?? (() => Date.now());
    this.developer = options.developer ?? (() => false);
    this.quickGifts = options.quickGifts ?? (() => false);
    this.makeId = options.makeId ?? (() => randomUUID().toUpperCase());
    this.load();
  }

  // ---- lettura

  set onProblem(handler: ((message: string) => void) | undefined) {
    this.problemHandler = handler;
    if (handler && this.pendingProblems.length > 0) {
      const pending = this.pendingProblems;
      this.pendingProblems = [];
      pending.forEach(handler);
    }
  }

  private report(message: string): void {
    if (this.problemHandler) this.problemHandler(message);
    else this.pendingProblems.push(message);
  }

  private load(): void {
    if (!existsSync(this.file)) {
      this.startFresh();
      return;
    }
    const text = readText(this.file);
    if (text === null) {
      this._readOnly = true;
      this.report("Il file del giardino non si legge: non lo modifico.");
      return;
    }
    let contents: Contents | null = null;
    try {
      contents = decodeContents(JSON.parse(text.replace(/^﻿/, "")));
    } catch {
      contents = null;
    }
    if (contents === null) {
      // rovinato: lo metto da parte invece di sovrascriverlo alla prossima modifica
      const asideName = `giardino.corrotto-${Math.floor(this.now() / 1000)}.json`;
      try {
        renameSync(this.file, join(this.directory, asideName));
        this.report(`Il file del giardino era rovinato: l'ho messo da parte come ${asideName}.`);
      } catch {
        this._readOnly = true;
        this.report("Il file del giardino è rovinato e non riesco a metterlo da parte: non lo modifico.");
      }
      this.startFresh();
      return;
    }
    if (contents.version > GARDEN_FORMAT_VERSION) {
      this._readOnly = true;
      this.report("Il giardino è di una versione più nuova di questa app: lo leggo ma non lo modifico.");
    }
    const decoded = contents.placements.slice(0, MAX_PLACEMENTS * ISLANDS.length);
    this._home = contents.home !== undefined && isKnownIsland(contents.home) ? contents.home : null;
    const legacyCompanions = new Map<string, GardenSpot>();
    for (const [petId, place] of Object.entries(contents.companions)) {
      if (place.col !== undefined && place.row !== undefined) this._companionTiles.set(petId, { col: place.col, row: place.row });
      else if (place.x !== undefined && place.y !== undefined) legacyCompanions.set(petId, { x: place.x, y: place.y });
    }
    const placedItems = new Set(decoded.map((p) => p.item));
    if (contents.version >= 2 && contents.drops) {
      this._drops = contents.drops;
      // una cosa sull'isola è per forza trovata
      for (const id of placedItems) if ((this._drops.found[id] ?? 0) < 1) this._drops.found[id] = 1;
      this._lastRolled = contents.lastRolled ?? null;
      this._unseen = new Set(contents.unseen ?? []);
      this._pendingGifts = Math.max(contents.pendingGifts ?? 0, 0);
      this.legacySpent = contents.legacySpent ?? null;
    } else {
      // versione 1: gli oggetti sbloccati restano nell'album, e quelli messi nel prato sono trovati
      this._drops = startingDropState();
      for (const id of contents.unlocked ?? []) if (itemWithId(id)) this._drops.found[id] = 1;
      for (const id of placedItems) this._drops.found[id] = 1;
      this.legacySpent = Math.max(contents.spent ?? 0, 0);
    }
    // gli oggetti tolti dal catalogo spariscono da album e isole; il file com'era si tiene da parte, una volta
    let placements = decoded;
    if (placements.some((p) => RETIRED_ITEMS.has(p.item)) || Object.keys(this._drops.found).some((id) => RETIRED_ITEMS.has(id))
      || [...this._unseen].some((id) => RETIRED_ITEMS.has(id))) {
      placements = placements.filter((p) => !RETIRED_ITEMS.has(p.item));
      for (const id of Object.keys(this._drops.found)) if (RETIRED_ITEMS.has(id)) delete this._drops.found[id];
      this._unseen = new Set([...this._unseen].filter((id) => !RETIRED_ITEMS.has(id)));
      if (contents.version >= GARDEN_FORMAT_VERSION) this.legacyBackupName = "giardino-prima-delle-rimozioni.json";
    }
    if (contents.version < GARDEN_FORMAT_VERSION) this.legacyBackupName = `giardino-formato${Math.max(contents.version, 1)}.json`;
    if (contents.bridges !== undefined) {
      const known = new Set(BRIDGES.map(bridgeId));
      this._bridges = contents.bridges.filter((id) => known.has(id));
    } else {
      this.bridgesUnsettled = true;
    }
    if (contents.welcomed !== undefined) this._welcomed = contents.welcomed.filter(isKnownIsland);
    else this.welcomedUnsettled = true;
    if ((this.bridgesUnsettled || this.welcomedUnsettled) && this.legacyBackupName === null) this.legacyBackupName = "giardino-prima-dei-ponti.json";
    this.rulesUnsettled = (contents.islandRules ?? 0) < ISLAND_RULES_VERSION;
    this.rulesNotice = contents.rulesNotice ?? null;
    this._corners = contents.corners ?? [];
    this._guests = contents.guests ?? {};
    this._scenes = contents.scenes ?? [];
    this._allPlacements = placements.map(({ legacy: _, ...rest }) => rest);
    this.settle(placements, legacyCompanions);
    this._formedCorners = formedCorners(this.placements);
  }

  /** Un giardino nuovo: l'album parte con gli oggetti della dotazione, già sull'isola. */
  private startFresh(): void {
    this._drops = startingDropState();
    this._lastRolled = null;
    this._unseen = new Set();
    this._pendingGifts = 0;
    this.legacySpent = null;
    this._companionTiles = new Map();
    this._allPlacements = [];
    this._home = null;
    this.shown = null;
    this._corners = [];
    this.newCorners = [];
    this._guests = {};
    this._scenes = [];
    this._bridges = [];
    this._welcomed = [];
    this.bridgesUnsettled = true;
    this.welcomedUnsettled = true;
    this.rulesUnsettled = false;
    this.rulesNotice = null;
    for (const x of GARDEN_ITEMS.filter(isStarter)) {
      const origin = STARTER_ORIGINS[x.id];
      if (origin) this._allPlacements.push({ id: this.makeId(), item: x.id, island: "", col: origin.col, row: origin.row, turned: false });
    }
    this._formedCorners = formedCorners(this.placements);
  }

  /** Dopo la lettura: le posizioni del prato libero diventano tessere, e quello che non ci sta esce dall'isola (resta nella cassetta). Isola per isola. */
  private settle(decoded: readonly DecodedPlacement[], legacyCompanions: ReadonlyMap<string, GardenSpot>): void {
    const occupied = new Map<string, Set<string>>();
    const occupiedOn = (island: string): Set<string> => occupied.get(island) ?? new Set();
    const occupy = (island: string, tiles: readonly GardenTile[]): void => {
      const set = occupied.get(island) ?? new Set<string>();
      for (const t of tiles) set.add(tileKey(t));
      occupied.set(island, set);
    };
    const sizes = new Map<string, number>();
    const size = (island: string): number => {
      let known = sizes.get(island);
      if (known === undefined) {
        known = this.islandSizeOf(island);
        sizes.set(island, known);
      }
      return known;
    };
    const settled: GardenPlacement[] = [];
    const onPath: GardenPlacement[] = [];
    for (const entry of decoded) {
      const { legacy, ...placement } = entry;
      const x = itemWithId(placement.item);
      if (!x) {
        settled.push(placement);
        continue;
      }
      const island = this.resolved(placement.island);
      const footprint = applyTurn(x.footprint, placement.turned);
      if (legacy !== null) {
        const desired = tileFromLegacy(legacy, size(island));
        const origin = nearestOrigin(desired, footprint, size(island), occupiedOn(island), island);
        if (origin === null) continue;
        placement.col = origin.col;
        placement.row = origin.row;
      } else if (!canPlaceFootprint(footprint, placement, size(island), occupiedOn(island), island)) {
        // sul sentiero dell'isola (che può essere cambiato) si sposta dopo; fuori dall'isola o sopra un'altra cosa esce dall'isola
        const path = new Set([...pathTiles(island, size(island)), ...landmarkTiles(island)].map(tileKey));
        const covered = footprintTiles(footprint, placement);
        if (covered.every((t) => islandContains(t, size(island))) && covered.some((t) => path.has(tileKey(t)))) onPath.push(placement);
        continue;
      }
      occupy(island, footprintTiles(footprint, placement));
      settled.push(placement);
    }
    for (const placement of onPath) {
      const x = itemWithId(placement.item);
      if (!x) continue;
      const island = this.resolved(placement.island);
      const footprint = applyTurn(x.footprint, placement.turned);
      const origin = nearestOrigin(placement, footprint, size(island), occupiedOn(island), island);
      if (origin === null) continue;
      placement.col = origin.col;
      placement.row = origin.row;
      occupy(island, footprintTiles(footprint, origin));
      settled.push(placement);
    }
    this._allPlacements = settled;
    // i compagni del prato libero: sull'isola di casa
    const home = this.homeIsland;
    for (const [petId, spot] of legacyCompanions) {
      const desired = tileFromLegacy(spot, size(home));
      this._companionTiles.set(petId, nearestWalkable(desired, size(home), occupiedOn(home)) ?? desired);
    }
  }

  // ---- lo stato

  get isReadOnly(): boolean { return this._readOnly; }
  get drops(): GardenDropState { return this._drops; }
  get lastRolled(): string | null { return this._lastRolled; }
  get unseen(): ReadonlySet<string> { return this._unseen; }
  get pendingGifts(): number { return this._pendingGifts; }
  get allPlacements(): readonly GardenPlacement[] { return this._allPlacements; }
  get home(): string | null { return this._home; }
  get companionTiles(): ReadonlyMap<string, GardenTile> { return this._companionTiles; }
  get corners(): readonly string[] { return this._corners; }
  get guests(): Readonly<Record<string, GardenGuest>> { return this._guests; }
  /** Le scene dei compagni già viste («gattino-amaca»), nell'ordine in cui si sono viste: la sezione «Scene» dell'album. */
  get scenes(): readonly string[] { return this._scenes; }
  get bridges(): readonly string[] { return this._bridges; }
  get welcomed(): readonly string[] { return this._welcomed; }
  get formedCorners(): ReadonlyMap<string, string[]> { return this._formedCorners; }

  addObserver(observer: () => void): void { this.observers.push(observer); }

  // ---- le isole

  get homeIsland(): string { return this._home ?? FALLBACK_HOME; }
  get shownIsland(): string { return this.shown ?? this.homeIsland; }

  showIsland(id: string): void {
    if (!isKnownIsland(id) || id === this.shownIsland) return;
    this.shown = id;
    this.updateCorners();
    this.observers.forEach((o) => o());
  }

  /** Decide l'isola di casa, una volta sola; le copie senza isola stanno lì. */
  adoptHome(id: string): void {
    if (this._home !== null || !isKnownIsland(id)) return;
    this._home = id;
    for (const p of this._allPlacements) if (p.island === "") p.island = id;
    this.relocateOffPath(id);
    this.save();
  }

  /** Le copie di un'isola che stanno sul suo sentiero vanno sulla tessera libera più vicina. */
  private relocateOffPath(island: string): void {
    const size = this.islandSizeOf(island);
    for (const p of this._allPlacements) {
      if (this.resolved(p.island) !== island) continue;
      const x = itemWithId(p.item);
      if (!x) continue;
      const footprint = applyTurn(x.footprint, p.turned);
      const others = this.occupiedTilesOn(island, p.id);
      if (canPlaceFootprint(footprint, p, size, others, island)) continue;
      const origin = nearestOrigin(p, footprint, size, others, island);
      if (origin) { p.col = origin.col; p.row = origin.row; }
    }
  }

  /** L'isola vera di un id che può essere vuoto (= casa). */
  private resolved(island: string): string { return island === "" ? this.homeIsland : island; }
  /** Quello che si scrive nella copia: finché la casa non è decisa, quella di casa resta vuota. */
  private stored(island: string): string { return this._home === null && island === FALLBACK_HOME ? "" : island; }

  placementsOn(island: string): GardenPlacement[] {
    const target = this.resolved(island);
    return this._allPlacements.filter((p) => this.resolved(p.island) === target);
  }

  get placements(): GardenPlacement[] { return this.placementsOn(this.shownIsland); }

  // ---- l'album

  has(id: string): boolean { return (this._drops.found[id] ?? 0) > 0; }

  /** L'oggetto è nell'album? (In modalità sviluppatore sono tutti.) */
  isFound(id: string): boolean {
    if (!itemWithId(id)) return false;
    return this.has(id) || this.developer();
  }

  get foundCount(): number { return GARDEN_ITEMS.filter((x) => this.has(x.id)).length; }

  markSeen(): void {
    if (this._unseen.size === 0) return;
    this._unseen = new Set();
    this.save();
  }

  // ---- i regali

  private isOpen(island: string): boolean { return this.isIslandOpen ? this.isIslandOpen(island) : true; }

  /** Gli oggetti che un regalo può essere: gli universali e quelli degli animali sbloccati (l'elenco fa parte del tiro). */
  get dropPool(): GardenItem[] { return GARDEN_ITEMS.filter((x) => x.island === null || this.isOpen(x.island)); }

  /** Un focus appena finito: se conta, i suoi minuti vanno nella riserva e, se bastano, esce la figurina e va subito sull'isola. */
  rollGift(session: StudySession, streakDays: number): GardenGift {
    const quick = this.quickGifts();
    const minimum = quick ? MINIMUM_SECONDS : DROP_MINIMUM_SECONDS;
    const sessionId = session.id.toUpperCase();
    if (!isEligible(session, minimum) || this._lastRolled === sessionId) return { kind: "notEligible" };
    const pool = this.dropPool;
    const somethingToFind = hasSomethingToFind(this._drops, pool);
    const state = cloneDropState(this._drops);
    const drop = credit(sessionId, streakDays, session.seconds, state, pool, quick ? 60 : 1);
    this._drops = state;
    this._lastRolled = sessionId;
    if (drop === null) {
      this.save();
      return somethingToFind ? { kind: "progress" } : { kind: "complete" };
    }
    this._unseen.add(drop.item);
    this.autoPlace(drop.item, null, sessionId);
    this.save();
    return { kind: "found", drop };
  }

  get minutesToNextGift(): number | null { return minutesToNextGift(this._drops, this.dropPool); }
  get nextGiftProgress(): number | null { return giftProgress(this._drops, this.dropPool); }

  /** Chi aveva il giardino della versione 1: i punti guadagnati e non spesi diventano regali da aprire (una volta sola). */
  convertLegacyPoints(earned: number): void {
    if (this.legacySpent === null) return;
    this._pendingGifts = Math.max(earned - this.legacySpent, 0);
    this.legacySpent = null;
    this.save();
  }

  /** Apre i regali in attesa: uno per punto, sempre gli stessi (dipendono dal numero d'ordine). */
  openPendingGifts(): GardenDrop[] {
    if (this._pendingGifts <= 0) return [];
    const opened: GardenDrop[] = [];
    const state = cloneDropState(this._drops);
    const pool = this.dropPool;
    for (let number = 1; number <= this._pendingGifts; number++) {
      const id = `REGALO-${number}`;
      const drop = roll(id, 1, DROP_MINIMUM_SECONDS, state, pool);
      if (drop === null) continue;
      opened.push(drop);
      this._unseen.add(drop.item);
      this._drops = cloneDropState(state);
      this.autoPlace(drop.item, null, id);
    }
    this._drops = state;
    this._pendingGifts = 0;
    this.save();
    return opened;
  }

  /** Mette una copia appena trovata su una tessera libera scelta dal numero: una cosa di un animale sulla sua isola, una universale su quella di casa. */
  private autoPlace(id: string, island: string | null, salt: string): string | null {
    const x = itemWithId(id);
    if (!x) return null;
    const target = island ?? x.island ?? this.homeIsland;
    if (!fitsIsland(x, target) || this.placementsOn(target).length >= MAX_PLACEMENTS) return null;
    const origins = freeOrigins(x.footprint, this.islandSizeOf(target), this.occupiedTilesOn(target), target);
    if (origins.length === 0) return null;
    const stream = new DropStream(hash("posto-" + salt.toUpperCase()));
    const origin = origins[Math.min(Math.trunc(stream.next() * origins.length), origins.length - 1)]!;
    const placement: GardenPlacement = { id: this.makeId(), item: id, island: this.stored(target), col: origin.col, row: origin.row, turned: false };
    this._allPlacements.push(placement);
    return placement.id;
  }

  // ---- i ponti e i benvenuti

  isBuilt(bridge: GardenBridge): boolean { return this._bridges.includes(bridgeId(bridge)); }

  /** Se gli elenchi dei ponti e dei benvenuti mancano li calcola e li salva subito: i ponti fra le isole già aperte sono già costruiti. */
  settleBridges(open: ReadonlySet<string>): void {
    if (!this.bridgesUnsettled && !this.welcomedUnsettled) return;
    if (this.bridgesUnsettled) {
      this._bridges = pendingBridges(open, new Set()).map(bridgeId);
      this.bridgesUnsettled = false;
    }
    if (this.welcomedUnsettled) {
      const linked = new Set(BRIDGES.filter((b) => this._bridges.includes(bridgeId(b))).flatMap((b) => [b.first, b.second]));
      this._welcomed = ISLANDS.filter((id) => open.has(id) || linked.has(id) || id === this.homeIsland);
      this.welcomedUnsettled = false;
    }
    this.save();
  }

  pendingBridges(open: ReadonlySet<string>): GardenBridge[] {
    return this.bridgesUnsettled ? [] : pendingBridges(open, new Set(this._bridges));
  }

  pendingWelcomes(open: ReadonlySet<string>): string[] {
    return this.welcomedUnsettled ? [] : newcomers(open, new Set(this._welcomed), this.homeIsland);
  }

  /** Segna costruiti i ponti e accolte le isole, e dà a ciascuna il regalo di benvenuto (sull'isola, se c'è posto). Un salvataggio solo. */
  buildBridges(built: readonly GardenBridge[], islands: readonly string[]): GardenBridgeWelcome[] {
    if (this.bridgesUnsettled || this.welcomedUnsettled) return [];
    for (const bridge of built) if (!this._bridges.includes(bridgeId(bridge))) this._bridges.push(bridgeId(bridge));
    const welcomes: GardenBridgeWelcome[] = [];
    for (const island of islands) {
      if (!this._welcomed.includes(island)) this._welcomed.push(island);
      const gift = welcomeGift(island, (id) => this.has(id));
      if (gift === null) continue;
      this._drops.found[gift] = 1;
      this._unseen.add(gift);
      welcomes.push({ island, item: gift, placement: this.autoPlace(gift, island, "BENVENUTO-" + island) });
    }
    this.save();
    return welcomes;
  }

  // ---- le cose degli animali

  /** Una volta sola per file: le copie di un animale su un'isola che non è la sua passano su quella giusta, vicine fra loro, o tornano nella cassetta. */
  settleRules(): void {
    if (!this.rulesUnsettled || this._readOnly || this._home === null) return;
    this.rulesUnsettled = false;
    const misplaced: GardenPlacement[] = [];
    const staying: GardenPlacement[] = [];
    for (const p of this._allPlacements) {
      const owner = itemWithId(p.item)?.island ?? null;
      if (owner !== null && this.resolved(p.island) !== owner) misplaced.push(p);
      else staying.push(p);
    }
    if (misplaced.length === 0) {
      this.save();
      return;
    }
    this.keepCopy("giardino-prima-delle-regole.json");
    this._allPlacements = staying;
    let moved = 0, returned = 0;
    for (const owner of ISLANDS) {
      const group = misplaced.map((element, offset) => ({ element, offset })).filter((e) => itemWithId(e.element.item)?.island === owner);
      if (group.length === 0) continue;
      const size = this.islandSizeOf(owner);
      const meanCol = group.reduce((sum, e) => sum + e.element.col, 0) / group.length;
      const meanRow = group.reduce((sum, e) => sum + e.element.row, 0) / group.length;
      const anchor = { col: Math.min(Math.max(swiftRound(meanCol), 0), size - 1), row: Math.min(Math.max(swiftRound(meanRow), 0), size - 1) };
      const area = (id: string): number => { const x = itemWithId(id); return (x?.footprint.cols ?? 1) * (x?.footprint.rows ?? 1); };
      const order = [...group].sort((a, b) => {
        const areaA = area(a.element.item), areaB = area(b.element.item);
        if (areaA !== areaB) return areaB - areaA;
        const indexA = itemNumber(a.element.item) ?? 0, indexB = itemNumber(b.element.item) ?? 0;
        return indexA !== indexB ? indexA - indexB : a.offset - b.offset;
      });
      for (const entry of order) {
        const x = itemWithId(entry.element.item);
        const origin = x && this.isOpen(owner) && this.placementsOn(owner).length < MAX_PLACEMENTS
          ? nearestOrigin(anchor, applyTurn(x.footprint, entry.element.turned), size, this.occupiedTilesOn(owner), owner) : null;
        if (origin === null) {
          returned += 1;
          continue;
        }
        this._allPlacements.push({ ...entry.element, col: origin.col, row: origin.row, island: this.stored(owner) });
        moved += 1;
      }
    }
    this.rulesNotice = { moved, returned };
    this.save();
  }

  /** Cosa ha fatto `settleRules`, una volta sola. */
  takeRulesNotice(): GardenRulesReport | null {
    const report = this.rulesNotice;
    if (report === null) return null;
    this.rulesNotice = null;
    this.save();
    return report;
  }

  /** Tiene da parte il file com'è adesso, con questo nome (se c'è già una copia con quel nome non la tocca). */
  private keepCopy(name: string): void {
    const backup = join(this.directory, name);
    try {
      if (existsSync(this.file) && !existsSync(backup)) copyFileSync(this.file, backup);
    } catch { /* come in Swift: si va avanti */ }
  }

  // ---- l'isola e le copie

  /** Quante tessere per lato: 8, una in più per ogni doppia pagina completata, fino a 10 (e mai meno di quanto serve a quello che c'è sopra). */
  islandSizeOf(island: string): number {
    let size = islandSizeFor(completedSpreads((id) => this.isFound(id)));
    for (const p of this.placementsOn(island)) {
      const x = itemWithId(p.item);
      if (!x) continue;
      const footprint = applyTurn(x.footprint, p.turned);
      size = Math.max(size, p.col + footprint.cols, p.row + footprint.rows);
    }
    return Math.min(size, ISLAND_MAX_SIZE);
  }

  get islandSize(): number { return this.islandSizeOf(this.shownIsland); }

  /** Le tessere coperte dalle copie di un'isola e dalla sua casa (senza contare `ignoring`). */
  occupiedTilesOn(island: string, ignoring: string | null = null): Set<string> {
    const result = occupiedTiles(this.placementsOn(island), ignoring);
    for (const t of landmarkTiles(island)) result.add(tileKey(t));
    return result;
  }

  /** Le cose che si possono mettere su quell'isola: tutte quelle trovate che ci stanno, nell'ordine dell'album. */
  tray(island: string | null = null): GardenItem[] {
    const target = island === null ? this.shownIsland : this.resolved(island);
    return GARDEN_ITEMS.filter((x) => fitsIsland(x, target) && this.has(x.id));
  }

  canPlace(id: string, at: GardenTile, turned = false, island: string | null = null, ignoring: string | null = null): boolean {
    const x = itemWithId(id);
    if (!x) return false;
    const target = island === null ? this.shownIsland : this.resolved(island);
    if (!fitsIsland(x, target)) return false;
    return canPlaceFootprint(applyTurn(x.footprint, turned), at, this.islandSizeOf(target), this.occupiedTilesOn(target, ignoring), target);
  }

  /** Mette una copia (se l'hai trovata e ci sta). */
  place(id: string, at: GardenTile, turned = false, island: string | null = null): GardenPlacement | null {
    const target = island === null ? this.shownIsland : this.resolved(island);
    if (!this.isFound(id) || this.placementsOn(target).length >= MAX_PLACEMENTS || !this.canPlace(id, at, turned, target)) return null;
    const made: GardenPlacement = { id: this.makeId(), item: id, island: this.stored(target), col: at.col, row: at.row, turned };
    this._allPlacements.push(made);
    this.save();
    return made;
  }

  /** Mette una copia su una tessera libera qualunque (un tocco sulla cassetta): sempre la stessa per lo stesso numero di copie. */
  placeSomewhere(id: string, island: string | null = null): GardenPlacement | null {
    const x = itemWithId(id);
    if (!x) return null;
    const target = island === null ? this.shownIsland : this.resolved(island);
    const origins = freeOrigins(x.footprint, this.islandSizeOf(target), this.occupiedTilesOn(target), target);
    if (origins.length === 0) return null;
    const stream = new DropStream(hash(`tocco-${this.placementsOn(target).length}-` + id));
    return this.place(id, origins[Math.min(Math.trunc(stream.next() * origins.length), origins.length - 1)]!, false, target);
  }

  /** Sposta una copia (e la gira, se si dice), sulla sua isola o su un'altra. False se lì non ci sta: resta dov'era. */
  move(placementId: string, to: GardenTile, turned: boolean | null = null, island: string | null = null): boolean {
    const p = this._allPlacements.find((x) => x.id === placementId);
    if (!p) return false;
    const newTurned = turned ?? p.turned;
    const target = island === null ? this.resolved(p.island) : this.resolved(island);
    if (!isKnownIsland(target) || !this.canPlace(p.item, to, newTurned, target, placementId)) return false;
    p.col = to.col;
    p.row = to.row;
    p.turned = newTurned;
    if (island !== null && target !== this.resolved(p.island)) p.island = this.stored(target);
    this.updateCorners();
    this.save();
    return true;
  }

  placement(id: string): GardenPlacement | undefined { return this._allPlacements.find((p) => p.id === id); }

  /** Gira una copia di un quarto, se così ci sta ancora. */
  rotate(placementId: string): boolean {
    const p = this.placement(placementId);
    return p ? this.move(placementId, p, !p.turned) : false;
  }

  remove(placementId: string): void {
    const index = this._allPlacements.findIndex((p) => p.id === placementId);
    if (index < 0) return;
    this._allPlacements.splice(index, 1);
    this.save();
  }

  /** Quante copie di un oggetto ci sono su tutte le isole. */
  count(id: string): number { return this._allPlacements.filter((p) => p.item === id).length; }

  // ---- i compagni

  companionTile(petId: string, index: number): GardenTile {
    return this._companionTiles.get(petId) ?? defaultCompanionTile(index, isKnownIsland(petId) ? petId : null);
  }

  setCompanionTile(petId: string, to: GardenTile): void {
    if (!islandContains(to, this.islandSize)) return;
    this._companionTiles.set(petId, { col: to.col, row: to.row });
    this.save();
  }

  // ---- gli angoli

  private updateCorners(): boolean {
    let found = false;
    for (const island of ISLANDS) {
      const formed = formedCorners(this.placementsOn(island));
      if (island === this.shownIsland) this._formedCorners = formed;
      for (const corner of GARDEN_CORNERS) {
        if (!formed.has(corner.id) || this._corners.includes(corner.id)) continue;
        this._corners.push(corner.id);
        this.newCorners.push(corner.id);
        found = true;
      }
    }
    return found;
  }

  formedCornersOn(island: string): Map<string, string[]> { return formedCorners(this.placementsOn(island)); }

  /** Guarda se le copie formano un angolo non ancora sbloccato e, se sì, lo sblocca e salva. */
  discoverCorners(): void { if (this.updateCorners()) this.save(); }

  /** Gli angoli sbloccati da quando si è chiesto l'ultima volta (per le stelline). */
  takeNewCorners(): string[] {
    const result = this.newCorners;
    this.newCorners = [];
    return result;
  }

  // ---- gli ospiti

  /** Saluti un ospite: la prima volta entra nel diario e lascia un regalo (sempre lo stesso per la stessa specie). */
  welcomeGuest(id: string, day: string, reason: string): GardenGuestWelcome {
    const known = this._guests[id];
    if (known) {
      this._guests[id] = { ...known, visits: known.visits + 1 };
      this.save();
      return { isFirst: false, gift: null };
    }
    this._guests[id] = { first: day, visits: 1, reason };
    const state = cloneDropState(this._drops);
    const salt = `OSPITE-${id}`;
    const gift = roll(salt, 1, DROP_MINIMUM_SECONDS, state, this.dropPool);
    if (gift) {
      this._drops = state;
      this._unseen.add(gift.item);
      this.autoPlace(gift.item, null, salt);
    }
    this.save();
    return { isFirst: true, gift };
  }

  /** Un compagno ha usato una cosa davanti a te: la prima volta la sua scena entra nell'album (e si salva). Dice se è la prima volta. */
  noteScene(pet: string, item: string): boolean {
    const scene = interactionOf(pet, item);
    if (!scene || this._scenes.includes(sceneId(scene))) return false;
    this._scenes.push(sceneId(scene));
    this.save();
    return true;
  }

  // ---- da capo

  /** Toglie tutto (per «Cancella tutto…»): si riparte dalla dotazione. */
  reset(): void {
    this.startFresh();
    try { rmSync(this.file, { force: true }); } catch { /* niente da fare */ }
    this._readOnly = false;
    this.legacyBackupName = null;
    this.observers.forEach((o) => o());
  }

  private save(): void {
    this.updateCorners();
    if (!this._readOnly) {
      if (this.legacyBackupName !== null) {
        const name = this.legacyBackupName;
        this.legacyBackupName = null;
        this.keepCopy(name);
      }
      const companions: Record<string, GardenTile> = {};
      for (const [petId, t] of this._companionTiles) companions[petId] = { col: t.col, row: t.row };
      const contents = {
        version: GARDEN_FORMAT_VERSION,
        drops: { found: this._drops.found, sinceRare: this._drops.sinceRare, sinceLegendary: this._drops.sinceLegendary, studyBank: this._drops.studyBank },
        lastRolled: this._lastRolled ?? undefined,
        unseen: [...this._unseen].sort(),
        pendingGifts: this._pendingGifts,
        legacySpent: this.legacySpent ?? undefined,
        placements: this._allPlacements.map((p) => ({ id: p.id, item: p.item, island: p.island === "" ? undefined : p.island, col: p.col, row: p.row, turned: p.turned })),
        companions,
        home: this._home ?? undefined,
        corners: this._corners.length === 0 ? undefined : this._corners,
        guests: Object.keys(this._guests).length === 0 ? undefined : this._guests,
        scenes: this._scenes.length === 0 ? undefined : this._scenes,
        bridges: this.bridgesUnsettled ? undefined : this._bridges,
        welcomed: this.welcomedUnsettled ? undefined : this._welcomed,
        islandRules: this.rulesUnsettled ? undefined : ISLAND_RULES_VERSION,
        rulesNotice: this.rulesNotice ?? undefined,
      };
      try {
        writeFileAtomic(this.file, stringifyJson(contents));
        this.writeFailureReported = false;
      } catch (error) {
        if (!this.writeFailureReported) {
          this.writeFailureReported = true;
          this.report(`Non riesco a salvare il giardino: ${error instanceof Error ? error.message : String(error)}.`);
        }
      }
    }
    this.observers.forEach((o) => o());
  }
}

/** Come `rounded()` di Swift: a metà si allontana dallo zero (Math.round va verso +∞). */
function swiftRound(x: number): number { return x < 0 ? -Math.round(-x) : Math.round(x); }

