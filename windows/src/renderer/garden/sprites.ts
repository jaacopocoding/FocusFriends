// Le immagini del giardino, lette e analizzate una volta sola (GardenSprites.swift): la parte che si vede davvero, una griglia per capire dove cade
// un clic, e i disegni «sul lato» (la staccionata, le bandierine, l'amaca) adagiati sull'asse di una tessera, con i bracci verso i vicini.
// Una chiave è il percorso dentro `assets/` senza «.png» (`giardino/lampione`, `gattino/frame1`); quelle sul lato hanno in più `@asse`, i lati e i bracci
// (`giardino/amaca@asse2`, `giardino/cancelletto@asse#10`).

import { AXIAL_SUFFIX, GARDEN_ITEMS } from "../../core/gardenCatalog.ts";
import { ARM_DOWN_LEFT, ARM_DOWN_RIGHT, ARM_UP_LEFT, ARM_UP_RIGHT } from "../../core/gardenGrid.ts";

type Source = HTMLImageElement | HTMLCanvasElement;

export interface Sprite {
  image: Source;
  width: number;
  height: number;
  /** La parte non trasparente, in pixel dell'immagine (origine in alto a sinistra). */
  src: { x: number; y: number; w: number; h: number };
  mask: Uint8Array;
  columns: number;
  rows: number;
  /** Solo sul lato: quanto sta sotto i piedi il fondo della parte visibile, in frazioni della sua altezza. */
  footDrop: number;
  /** Solo sul lato: dove stanno i piedi dentro la parte visibile, in frazioni della sua larghezza. */
  feetAcross: number;
  /** Solo sul lato: quanti pixel dell'immagine fanno un lato di tessera. */
  sideWidth: number | null;
}

export const aspect = (s: Sprite): number => s.src.w / Math.max(s.src.h, 1);

/** C'è qualcosa di disegnato in (u, v) dentro la parte visibile (v dall'alto), o a una cella di distanza? */
export function isDrawn(s: Sprite, u: number, v: number): boolean {
  if (s.columns <= 0 || s.rows <= 0 || s.mask.length === 0) return true;
  const column = Math.floor(u * s.columns), row = Math.floor(v * s.rows);
  for (let r = Math.max(row - 1, 0); r <= Math.min(row + 1, s.rows - 1); r++) {
    for (let c = Math.max(column - 1, 0); c <= Math.min(column + 1, s.columns - 1); c++) if (s.mask[r * s.columns + c]) return true;
  }
  return false;
}

const loaded = new Map<string, Sprite | null>();
const pending = new Map<string, Promise<Sprite | null>>();
let onLoad: (() => void) | null = null;

/** Chiamata quando un'immagine finisce di caricarsi (la scena si ridisegna). */
export function whenSpritesLoad(callback: () => void): void { onLoad = callback; }

function canvas(width: number, height: number): HTMLCanvasElement {
  const made = document.createElement("canvas");
  made.width = Math.max(1, Math.round(width));
  made.height = Math.max(1, Math.round(height));
  return made;
}

/** Cerca i pixel non trasparenti (sopra 24 su 255) e la griglia dei punti disegnati, al massimo 64 celle sul lato lungo. */
function analyze(image: Source): Sprite {
  const w = image.width, h = image.height;
  const full: Sprite = { image, width: w, height: h, src: { x: 0, y: 0, w, h }, mask: new Uint8Array(0), columns: 0, rows: 0, footDrop: 0, feetAcross: 0.5, sideWidth: null };
  if (w <= 0 || h <= 0) return full;
  const work = canvas(w, h);
  const ctx = work.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(image, 0, 0);
  const data = ctx.getImageData(0, 0, w, h).data;
  let minX = w, maxX = -1, minY = h, maxY = -1;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (data[(y * w + x) * 4 + 3]! > 24) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < minX || maxY < minY) return full;
  const boxW = maxX - minX + 1, boxH = maxY - minY + 1, long = 64;
  const columns = boxW >= boxH ? long : Math.max(1, Math.round(long * boxW / boxH));
  const rows = boxH > boxW ? long : Math.max(1, Math.round(long * boxH / boxW));
  const mask = new Uint8Array(columns * rows);
  for (let y = minY; y <= maxY; y++) {
    const row = Math.min(Math.trunc((y - minY) * rows / boxH), rows - 1);
    for (let x = minX; x <= maxX; x++) {
      if (data[(y * w + x) * 4 + 3]! > 24) mask[row * columns + Math.min(Math.trunc((x - minX) * columns / boxW), columns - 1)] = 1;
    }
  }
  return { ...full, src: { x: minX, y: minY, w: boxW, h: boxH }, mask, columns, rows };
}

function loadImage(path: string): Promise<HTMLImageElement | null> {
  const image = new Image();
  image.src = `ff://app/assets/${path}.png`;
  return image.decode().then(() => image, () => null);
}

/** Quanto si allunga in verticale un disegno di fronte adagiato su un lato con la pendenza `slope`. */
const axialStretch = (slope: number): number => 1 + 0.44 * slope;
/** Un pezzo solo sul lato è un po' più lungo del lato della tessera, perché i pezzi di fila si tocchino. */
const SIDE_OVERLAP = 1.04;

/** Un disegno di fronte adagiato sul lato di una tessera: piegato, con la base che scende andando a destra (come i lati dei rombi). */
async function axial(base: string, sides: number, arms: number | null): Promise<Sprite | null> {
  const flat = await sprite(base);
  if (!flat) return null;
  const id = base.slice(base.lastIndexOf("/") + 1);
  const slope = GARDEN_ITEMS.find((x) => x.id === id)?.slope ?? 0.5;
  const w = flat.src.w, h = flat.src.h * axialStretch(slope);
  const height = Math.ceil(h + slope * w);
  let result = canvas(w, height);
  const ctx = result.getContext("2d")!;
  ctx.imageSmoothingQuality = "high";
  ctx.setTransform(1, slope, 0, 1, 0, 0);
  ctx.drawImage(flat.image, flat.src.x, flat.src.y, flat.src.w, flat.src.h, 0, height - slope * w - h, w, h);
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  if (arms !== null) result = joinedArms(result, arms);
  const made = analyze(result);
  const bottomGap = made.height - (made.src.y + made.src.h);
  made.footDrop = (slope * w / 2 - bottomGap) / Math.max(made.src.h, 1);
  if (arms !== null) made.feetAcross = (made.width / 2 - made.src.x) / Math.max(made.src.w, 1);
  made.sideWidth = made.width / (sides * (sides === 1 ? SIDE_OVERLAP : 1));
  return made;
}

/** Dal pezzo dritto ai soli bracci chiesti: la metà a sinistra va in alto a sinistra, quella a destra in basso a destra, e le stesse metà specchiate fanno gli altri due lati. */
function joinedArms(whole: HTMLCanvasElement, arms: number): HTMLCanvasElement {
  const w = whole.width, h = whole.height, mid = Math.floor(w / 2);
  const result = canvas(w, h);
  const ctx = result.getContext("2d")!;
  const draw = (fromX: number, width: number, at: number, mirrored: boolean): void => {
    ctx.save();
    if (mirrored) { ctx.translate(w, 0); ctx.scale(-1, 1); }
    ctx.drawImage(whole, fromX, 0, width, h, at, 0, width, h);
    ctx.restore();
  };
  if (arms & ARM_UP_LEFT) draw(0, mid, 0, false);
  if (arms & ARM_UP_RIGHT) draw(0, mid, 0, true);
  if (arms & ARM_DOWN_LEFT) draw(mid, w - mid, mid, true);
  if (arms & ARM_DOWN_RIGHT) draw(mid, w - mid, mid, false);
  return result;
}

/** L'immagine (caricata e analizzata), o null se non c'è. La prima volta si carica in sottofondo. */
export function sprite(key: string): Promise<Sprite | null> {
  const known = pending.get(key);
  if (known) return known;
  let made: Promise<Sprite | null>;
  const marker = key.indexOf(AXIAL_SUFFIX);
  if (marker >= 0) {
    const [sidesText, armsText] = key.slice(marker + AXIAL_SUFFIX.length).split("#");
    made = axial(key.slice(0, marker), Number(sidesText) || 1, armsText === undefined ? null : Number(armsText));
  } else {
    made = loadImage(key).then((image) => (image ? analyze(image) : null));
  }
  made = made.then((result) => {
    loaded.set(key, result);
    onLoad?.();
    return result;
  });
  pending.set(key, made);
  return made;
}

/** L'immagine se è già pronta; altrimenti la chiede e intanto null. */
export function ready(key: string): Sprite | null {
  if (loaded.has(key)) return loaded.get(key) ?? null;
  void sprite(key);
  return null;
}

/** Sono pronte tutte queste immagini (o non esistono)? */
export function allSettled(keys: readonly string[]): boolean {
  return keys.every((key) => loaded.has(key));
}

// ---- la stessa immagine alla grandezza in pixel con cui la si disegna, già tinta dalla luce del momento

export interface Tint { red: number; green: number; blue: number }
export const NO_TINT: Tint = { red: 255, green: 255, blue: 255 };
const isNoTint = (t: Tint): boolean => t.red === 255 && t.green === 255 && t.blue === 255;

/** Dal colore con cui si moltiplica la scena, a scalini di 6 (così non si rifanno gli oggetti ad ogni minuto del tramonto). */
export function tintOf(multiplier: { red: number; green: number; blue: number }): Tint {
  const step = (value: number): number => Math.min(255, Math.max(0, Math.round(value / 6) * 6));
  return { red: step(multiplier.red), green: step(multiplier.green), blue: step(multiplier.blue) };
}

const scaledCache = new Map<string, HTMLCanvasElement>();

/** La sola parte visibile, grande `pixelWidth × pixelHeight`, moltiplicata per la tinta (l'opacità resta com'è). */
export function scaled(s: Sprite, key: string, pixelWidth: number, pixelHeight: number, tint: Tint = NO_TINT): HTMLCanvasElement {
  const pw = Math.max(1, Math.round(pixelWidth)), ph = Math.max(1, Math.round(pixelHeight));
  const cacheKey = `${key}|${pw}x${ph}|${tint.red},${tint.green},${tint.blue}`;
  const known = scaledCache.get(cacheKey);
  if (known) return known;
  const made = canvas(pw, ph);
  const ctx = made.getContext("2d")!;
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(s.image, s.src.x, s.src.y, s.src.w, s.src.h, 0, 0, pw, ph);
  if (!isNoTint(tint)) {
    ctx.globalCompositeOperation = "multiply";
    ctx.fillStyle = `rgb(${tint.red}, ${tint.green}, ${tint.blue})`;
    ctx.fillRect(0, 0, pw, ph);
    ctx.globalCompositeOperation = "destination-in";
    ctx.drawImage(s.image, s.src.x, s.src.y, s.src.w, s.src.h, 0, 0, pw, ph);
  }
  if (scaledCache.size > 600) scaledCache.clear();
  scaledCache.set(cacheKey, made);
  return made;
}

/** Un'immagine qualunque (lo sfondo, la collina) già caricata, intera. */
export function picture(key: string): Source | null {
  return ready(key)?.image ?? null;
}

export { canvas as makeCanvas };
