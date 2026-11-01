// Il disegno del giardino, come GardenView in GardenWindow.swift: il paesaggio, le colline, il terreno delle isole, le case, i ponti, le cose e i
// compagni, la luce dell'ora e della stagione. Le misure sono quelle della scena del Mac (1000 × 600 punti); la telecamera (zoom e spostamento) è
// una sola per tutto il mondo. Qui c'è solo il disegno: le regole sono in `core/garden*.ts`.

import { applyTurn, companionHeight, fitsIsland, gardenImage, itemWithId, joinedImage, litImage } from "../../core/gardenCatalog.ts";
import type { GardenItem } from "../../core/gardenCatalog.ts";
import { formedCorners } from "../../core/gardenCorners.ts";
import {
  BRIDGES, bridgeId, bridgePieceCenters, bridgeSpan, canPlaceFootprint, decals, DECAL_ANCHORS, GRASS_COUNT, grassGrid, grassWeightsFor, HILL_BELOW_RATIO, HILL_HEIGHT_RATIO,
  HILL_WIDTH_RATIO, hillFrame, ISLAND_MAX_SIZE, islandContains, islandCorner, isWalkable, LANDMARK_ART, LANDMARK_SIDE, landmarkTiles, linkArms, occupiedTiles, PATH_COUNT,
  pathTiles, pathVariants, pathWeightsFor,
  terrainTag, tileKey, WORLD_EXTENT, WORLD_REACH, worldSlot,
} from "../../core/gardenGrid.ts";
import type { GardenPlacement, GardenTile } from "../../core/gardenGrid.ts";
import { lampAmount, lightAt, lightMultiplier } from "../../core/gardenSky.ts";
import type { GardenLight, Season } from "../../core/gardenSky.ts";
import { petInfo } from "../../core/pets.ts";
import type { GardenData, GardenIslandData } from "../../shared/gardenApi.ts";
import { aspect, isDrawn, makeCanvas, NO_TINT, picture, ready, scaled, tintOf } from "./sprites.ts";
import type { Sprite, Tint } from "./sprites.ts";

export const SCENE_W = 1000, SCENE_H = 600;
const CENTER = { x: SCENE_W / 2, y: SCENE_H / 2 };
/** Con la collina sotto, l'isola comincia qui (c'è posto sopra per le cose alte). */
const HILL_TOP = 104;
export const ZOOM_MIN = 0.4, ZOOM_MAX = 2.5;
/** I piedi di un oggetto stanno un po' sotto il centro della sua tessera. */
const FEET_OFFSET = 0.22;
/** Da quanta luce dei lampioni in su si vedono accese le cose con il disegno acceso (il braciere). */
const LIT_THRESHOLD = 0.25;
/** Il paesaggio dipinto è più grande della finestra: centrato su di essa a zoom 1. */
const BACKDROP_SCALE = 1.9;
const BACKDROP = { x: SCENE_W * (1 - BACKDROP_SCALE) / 2, y: SCENE_H * (1 - BACKDROP_SCALE) / 2, w: SCENE_W * BACKDROP_SCALE, h: SCENE_H * BACKDROP_SCALE };
const WORLD_MARGIN = { top: 340, left: 480, bottom: 520, right: 480 };

const rgba = (r: number, g: number, b: number, a = 1): string => `rgba(${r}, ${g}, ${b}, ${a})`;
const unit = (r: number, g: number, b: number, a = 1): string => rgba(r * 255, g * 255, b * 255, a);

// ---- la proiezione

/** L'isola vista di sbieco: ogni tessera è un rombo largo `tileW` e alto la metà; `ox`, `oy` è il vertice in alto. */
export class Iso {
  readonly size: number;
  readonly tileW: number;
  readonly ox: number;
  readonly oy: number;
  constructor(size: number, tileW: number, ox: number, oy: number) {
    this.size = size;
    this.tileW = tileW;
    this.ox = ox;
    this.oy = oy;
  }
  get tileH(): number { return this.tileW / 2; }
  /** L'altezza del lato di terra, in proporzione alle tessere. */
  get edge(): number { return Math.max(this.tileW * 0.26, 8); }
  /** Quanto si disegna grande un oggetto: l'altezza del catalogo ÷ 135 per la larghezza di una tessera. */
  get scale(): number { return this.tileW / 135; }
  point(col: number, row: number): { x: number; y: number } {
    return { x: this.ox + (col - row) * this.tileW / 2, y: this.oy + (col + row) * this.tileH / 2 };
  }
  center(t: GardenTile): { x: number; y: number } { return this.point(t.col + 0.5, t.row + 0.5); }
  grid(x: number, y: number): { col: number; row: number } {
    const a = (x - this.ox) / (this.tileW / 2), b = (y - this.oy) / (this.tileH / 2);
    return { col: (a + b) / 2, row: (b - a) / 2 };
  }
}

/** La larghezza di una tessera a zoom 1: l'isola più grande, con la sua collina, sta tutta nella scena. */
export const BASE_TILE_W = Math.min((SCENE_W - 16) / (ISLAND_MAX_SIZE * HILL_WIDTH_RATIO), (SCENE_H - HILL_TOP - 14) / (ISLAND_MAX_SIZE * HILL_HEIGHT_RATIO));

export interface Camera { zoom: number; panX: number; panY: number }

/** Il mondo con questa telecamera: la tessera e dove sta il suo angolo (0, 0). */
export function worldView(camera: Camera): { tileW: number; ox: number; oy: number } {
  return {
    tileW: BASE_TILE_W * camera.zoom,
    ox: CENTER.x + (SCENE_W / 2 - CENTER.x) * camera.zoom + camera.panX,
    oy: CENTER.y + (HILL_TOP - CENTER.y) * camera.zoom + camera.panY,
  };
}

export function isoOf(island: GardenIslandData, camera: Camera): Iso | null {
  const corner = islandCorner(island.id);
  if (!corner) return null;
  const view = worldView(camera);
  return new Iso(island.size, view.tileW, view.ox + (corner.col - corner.row) * view.tileW / 2, view.oy + (corner.col + corner.row) * view.tileW / 4);
}

export function worldIso(camera: Camera): Iso {
  const view = worldView(camera);
  return new Iso(WORLD_EXTENT, view.tileW, view.ox, view.oy);
}

/** Lo zoom che mostra tutta un'isola di questa grandezza. */
export const islandZoom = (size: number): number => Math.min(Math.max(ISLAND_MAX_SIZE / Math.max(size, 1), ZOOM_MIN), ZOOM_MAX);

/** La vista che mostra tutta un'isola: il suo vertice in alto al solito posto. */
export function islandCamera(island: GardenIslandData): Camera {
  const zoom = islandZoom(island.size);
  const corner = islandCorner(island.id) ?? { col: 0, row: 0 };
  const view = worldView({ zoom, panX: 0, panY: 0 });
  return {
    zoom, panX: SCENE_W / 2 - view.ox - (corner.col - corner.row) * view.tileW / 2,
    panY: HILL_TOP - view.oy - (corner.col + corner.row) * view.tileW / 4,
  };
}

/** La vista che mostra tutte le isole, con le colline. */
export function worldCamera(): Camera {
  const base = worldView({ zoom: 1, panX: 0, panY: 0 });
  const island = ISLAND_MAX_SIZE * base.tileW;
  const sideHill = Math.max((HILL_WIDTH_RATIO - 1) / 2, 0) * island;
  const left = WORLD_REACH.left * base.tileW / 2 - sideHill, right = WORLD_REACH.right * base.tileW / 2 + sideHill;
  const top = -base.tileW * 1.6, bottom = WORLD_REACH.depth * base.tileW / 4 + HILL_BELOW_RATIO * island;
  const zoom = Math.min(Math.max(Math.min((SCENE_W - 40) / (right - left), (SCENE_H - 120) / (bottom - top)), ZOOM_MIN), ZOOM_MAX);
  const box = { x: base.ox + (left + right) / 2, y: base.oy + (top + bottom) / 2 };
  return { zoom, panX: SCENE_W / 2 - CENTER.x - (box.x - CENTER.x) * zoom, panY: SCENE_H / 2 + 14 - CENTER.y - (box.y - CENTER.y) * zoom };
}

/** Il centro della scena resta sempre nel mondo (o a una tessera dal bordo). */
export function clampCamera(camera: Camera): Camera {
  const world = worldIso(camera);
  const g = world.grid(CENTER.x, CENTER.y);
  const n = WORLD_EXTENT;
  const col = Math.min(Math.max(g.col, -1), n + 1), row = Math.min(Math.max(g.row, -1), n + 1);
  if (col === g.col && row === g.row) return camera;
  const inside = world.point(col, row);
  return { ...camera, panX: camera.panX + CENTER.x - inside.x, panY: camera.panY + CENTER.y - inside.y };
}

/** Ingrandisce di `factor` attorno a un punto della scena (quello sotto il mouse resta dov'è). */
export function zoomCamera(camera: Camera, factor: number, at: { x: number; y: number } = CENTER): Camera {
  const target = Math.min(Math.max(camera.zoom * factor, ZOOM_MIN), ZOOM_MAX);
  if (target === camera.zoom) return camera;
  const ratio = target / camera.zoom;
  return clampCamera({
    zoom: target,
    panX: at.x - CENTER.x - (at.x - CENTER.x - camera.panX) * ratio,
    panY: at.y - CENTER.y - (at.y - CENTER.y - camera.panY) * ratio,
  });
}

/** L'isola aperta più vicina al centro della vista, se è chiaramente più vicina di quella mostrata (così sul confine non balla). */
export function focusedIsland(data: GardenData, camera: Camera): string {
  const g = worldIso(camera).grid(CENTER.x, CENTER.y);
  const distance = (island: GardenIslandData): number => {
    const corner = islandCorner(island.id);
    if (!corner) return Infinity;
    const dc = Math.max(corner.col - g.col, 0, g.col - (corner.col + island.size)), dr = Math.max(corner.row - g.row, 0, g.row - (corner.row + island.size));
    return Math.sqrt(dc * dc + dr * dr);
  };
  const shown = data.islands.find((i) => i.id === data.shown);
  const current = shown ? distance(shown) : Infinity;
  let best: { id: string; distance: number } | null = null;
  for (const island of data.islands) {
    if (!island.open) continue;
    const d = distance(island);
    if (best === null || d < best.distance) best = { id: island.id, distance: d };
  }
  return best !== null && best.id !== data.shown && best.distance + 0.75 < current ? best.id : data.shown;
}

/** Le isole alla vista di adesso, dal fondo (in alto) al davanti. */
function worldIslands(data: GardenData, camera: Camera): Array<{ island: GardenIslandData; iso: Iso }> {
  const slotDepth = (id: string): number => { const s = worldSlot(id); return s ? s.col + s.row : 0; };
  return data.islands
    .flatMap((island) => { const iso = isoOf(island, camera); return iso ? [{ island, iso }] : []; })
    .sort((a, b) => slotDepth(a.island.id) - slotDepth(b.island.id));
}

// ---- i colori

interface Palette { veil: string }

function palette(season: Season): Palette {
  switch (season) {
    case "spring": return { veil: rgba(255, 232, 238, 0.14) };
    case "summer": return { veil: rgba(255, 244, 200, 0.12) };
    case "autumn": return { veil: rgba(255, 190, 110, 0.24) };
    case "winter": return { veil: rgba(225, 238, 255, 0.34) };
  }
}

/** Il carattere di ogni isola: una tinta leggera sul terreno e sulla collina (d'inverno, sotto la neve, più leggera). */
function islandWash(island: string, season: Season): string | null {
  const k = season === "winter" ? 0.55 : 1;
  switch (island) {
    case "pianty": return rgba(96, 200, 84, 0.16 * k);
    case "porcellino": return rgba(238, 150, 96, 0.24 * k);
    case "ciccio": return rgba(70, 170, 214, 0.22 * k);
    case "gattino": return rgba(112, 132, 204, 0.26 * k);
    case "riccio": return rgba(212, 124, 64, 0.24 * k);
    default: return null;
  }
}

const HILL_NAMES: Readonly<Record<Season, string>> = { spring: "primavera", summer: "estate", autumn: "autunno", winter: "inverno" };

// ---- le immagini che servono, da chiedere in anticipo

export function wantedImages(data: GardenData): string[] {
  const keys: string[] = ["giardino/sfondo", "giardino/sfondo_inverno", `giardino/collina_${HILL_NAMES[data.season]}`];
  const winter = data.season === "winter";
  for (let i = 1; i <= GRASS_COUNT; i++) keys.push(winter ? `giardino/tessera_neve_${i}` : `giardino/tessera_erba_${i}`);
  for (let i = 1; i <= PATH_COUNT; i++) keys.push(winter ? `giardino/tessera_sentiero_neve_${i}` : `giardino/tessera_sentiero_${i}`);
  for (let i = 1; i <= 24; i++) keys.push(`giardino/dettaglio_${i}`);
  for (const island of data.islands) {
    keys.push(`giardino/casa_${island.id}`);
    if (island.open) keys.push(petInfo(island.id).iconImage.replace(/\.png$/, ""));
    for (const p of island.placements) {
      const x = itemWithId(p.item);
      if (!x) continue;
      keys.push("giardino/" + gardenImage(x));
      const lit = litImage(x);
      if (lit) keys.push("giardino/" + x.id, "giardino/" + lit);
    }
  }
  for (const direction of ["colonna", "riga"]) for (const variant of [1, 2]) keys.push(`giardino/ponte_${direction}_${variant}`);
  return keys;
}

// ---- il paesaggio

const backdropCache = new Map<string, HTMLCanvasElement>();

/** Il lago d'inverno ha il suo paesaggio, se c'è. */
const frozen = (season: Season): boolean => season === "winter" && picture("giardino/sfondo_inverno") !== null;
const pictureKey = (season: Season): string => (frozen(season) ? "giardino/sfondo_inverno" : "giardino/sfondo");

/** Il paesaggio con l'inquadratura del Mac al centro e tutt'attorno copie specchiate (continua senza stacchi), sfocato: un pixel per punto. */
function backdropWorld(season: Season): HTMLCanvasElement | null {
  const key = pictureKey(season);
  const known = backdropCache.get(key);
  if (known) return known;
  const source = picture(key);
  if (!source) return null;
  const scale = Math.max(BACKDROP.w / source.width, BACKDROP.h / source.height);
  const w = source.width * scale, h = source.height * scale;
  const m = WORLD_MARGIN;
  const width = BACKDROP.w + m.left + m.right, height = BACKDROP.h + m.top + m.bottom;
  const pad = 24;
  // le copie: quella al centro com'è, le altre specchiate (in orizzontale, in verticale o tutte e due)
  const raw = makeCanvas(width + 2 * pad, height + 2 * pad);
  const ctx = raw.getContext("2d")!;
  const x0 = pad + m.left - (w - BACKDROP.w) * 0.40, y0 = pad + m.top + BACKDROP.h - h;
  for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) {
    ctx.save();
    ctx.translate(x0 + dx * w + (dx !== 0 ? w : 0), y0 + dy * h + (dy !== 0 ? h : 0));
    ctx.scale(dx === 0 ? 1 : -1, dy === 0 ? 1 : -1);
    ctx.drawImage(source, 0, 0, w, h);
    ctx.restore();
  }
  const made = makeCanvas(width, height);
  const out = made.getContext("2d")!;
  out.filter = `blur(${2 * BACKDROP_SCALE}px)`;
  out.drawImage(raw, -pad, -pad);
  backdropCache.set(key, made);
  return made;
}

function drawBackdrop(ctx: CanvasRenderingContext2D, camera: Camera, season: Season): void {
  ctx.fillStyle = unit(0.62, 0.75, 0.55);
  ctx.fillRect(-SCENE_W, -SCENE_H, SCENE_W * 3, SCENE_H * 3);
  const image = backdropWorld(season);
  if (image) {
    const m = WORLD_MARGIN;
    const center = { x: BACKDROP.x + BACKDROP.w / 2, y: BACKDROP.y + BACKDROP.h / 2 };
    const x = center.x + (BACKDROP.x - m.left - center.x) * camera.zoom + camera.panX;
    const y = center.y + (BACKDROP.y - m.top - center.y) * camera.zoom + camera.panY;
    ctx.imageSmoothingQuality = "low";
    ctx.drawImage(image, x, y, image.width * camera.zoom, image.height * camera.zoom);
    ctx.imageSmoothingQuality = "high";
  }
  ctx.fillStyle = palette(season).veil;
  ctx.fillRect(-SCENE_W, -SCENE_H, SCENE_W * 3, SCENE_H * 3);
}

/** Dove sta, a zoom 1 e senza spostamenti, un punto del disegno del paesaggio (`u`, `v` da 0 a 1): il fumo e le luci del casale. */
function backdropPoint(u: number, v: number, season: Season): { x: number; y: number } | null {
  const source = picture(pictureKey(season));
  if (!source) return null;
  const target = { w: BACKDROP.w * 2, h: BACKDROP.h * 2 };
  const scale = Math.max(target.w / source.width, target.h / source.height);
  const w = source.width * scale, h = source.height * scale;
  const cropX = (w - target.w) * 0.40;
  return { x: (u * w - cropX) / 2 + BACKDROP.x, y: (target.h - (1 - v) * h) / 2 + BACKDROP.y };
}

const cameraPoint = (p: { x: number; y: number }, camera: Camera): { x: number; y: number } =>
  ({ x: CENTER.x + (p.x - CENTER.x) * camera.zoom + camera.panX, y: CENTER.y + (p.y - CENTER.y) * camera.zoom + camera.panY });

function cottageWindows(season: Season): Array<{ u: number; v: number }> {
  const list = frozen(season)
    ? [[0.0813, 0.3990], [0.0875, 0.3644], [0.0938, 0.3993], [0.1072, 0.4040], [0.1228, 0.4010], [0.1432, 0.3631]]
    : [[0.0921, 0.3576], [0.1114, 0.3904], [0.1263, 0.3916], [0.1456, 0.3564]];
  return list.map(([u, v]) => ({ u: u!, v: v! }));
}

// ---- la collina

const tintedHills = new Map<string, HTMLCanvasElement>();

function hillImage(season: Season, key: string, color: string | null): HTMLCanvasElement | HTMLImageElement | null {
  const base = picture(`giardino/collina_${HILL_NAMES[season]}`);
  if (!base || color === null) return base as HTMLImageElement | null;
  const cacheKey = `${season}|${key}`;
  const known = tintedHills.get(cacheKey);
  if (known) return known;
  const made = makeCanvas(base.width, base.height);
  const ctx = made.getContext("2d")!;
  ctx.drawImage(base, 0, 0);
  ctx.globalCompositeOperation = "source-atop";
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, made.width, made.height);
  tintedHills.set(cacheKey, made);
  return made;
}

/** Un gradiente radiale con i colori a distanze uguali, disegnato in un'ellisse (`sx`, `sy` la schiaccia). */
function radial(ctx: CanvasRenderingContext2D, x: number, y: number, radius: number, colors: string[], sx = 1, sy = 1): void {
  if (radius <= 0) return;
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(sx, sy);
  const gradient = ctx.createRadialGradient(0, 0, 0, 0, 0, radius);
  colors.forEach((color, index) => gradient.addColorStop(index / (colors.length - 1), color));
  ctx.fillStyle = gradient;
  ctx.fillRect(-radius, -radius, radius * 2, radius * 2);
  ctx.restore();
}

function drawHill(ctx: CanvasRenderingContext2D, iso: Iso, season: Season, island: string, dark: boolean): void {
  const image = dark ? hillImage(season, "buio", unit(0.04, 0.06, 0.14, 0.62)) : hillImage(season, island, islandWash(island, season));
  if (!image) return;
  const n = iso.size;
  const frame = hillFrame(iso.point(0, n), iso.point(n, 0));
  if (frame.x > SCENE_W + 300 || frame.y > SCENE_H + 180 || frame.x + frame.width < -300 || frame.y + frame.height < -180) return;
  const k = frame.scale / 1.385;
  const baseY = frame.y + frame.height;
  const midX = frame.x + frame.width / 2;
  const shadow = season === "winter" ? [88, 100, 128] : [60, 52, 30];
  radial(ctx, midX, baseY - 26 * k, frame.width * 0.46, [0.30, 0.16, 0].map((a) => rgba(shadow[0]!, shadow[1]!, shadow[2]!, a)), 1, 0.16);
  ctx.imageSmoothingQuality = "low";
  ctx.drawImage(image, frame.x, frame.y, frame.width, frame.height);
  ctx.imageSmoothingQuality = "high";
  const mist = season === "winter" ? [232, 238, 248] : [240, 236, 224];
  for (const [fx, fy, width, height, alpha] of [[0.26, -26, 150, 18, 0.34], [0.50, -8, 220, 24, 0.40], [0.74, -26, 150, 18, 0.34]] as const) {
    radial(ctx, frame.x + fx * frame.width, baseY + fy * k, width * k * 1.3,
      [alpha, alpha * 0.5, 0].map((a) => rgba(mist[0]!, mist[1]!, mist[2]!, a)), 1, height / width);
  }
}

// ---- il terreno di un'isola, dipinto una volta per isola, grandezza, tessera e stagione

interface Ground { canvas: HTMLCanvasElement; width: number; height: number; originX: number; originY: number }
const grounds = new Map<string, Ground>();

function diamond(ctx: CanvasRenderingContext2D, iso: Iso, t: GardenTile): void {
  const top = iso.point(t.col, t.row), right = iso.point(t.col + 1, t.row), bottom = iso.point(t.col + 1, t.row + 1), left = iso.point(t.col, t.row + 1);
  ctx.beginPath();
  ctx.moveTo(top.x, top.y);
  ctx.lineTo(right.x, right.y);
  ctx.lineTo(bottom.x, bottom.y);
  ctx.lineTo(left.x, left.y);
  ctx.closePath();
}

function paintGround(ctx: CanvasRenderingContext2D, iso: Iso, season: Season, island: string, carrying: boolean): void {
  const winter = season === "winter";
  const tag = terrainTag(island);
  const grass = grassGrid(iso.size, grassWeightsFor(season), tag);
  const path = pathTiles(island, iso.size);
  const pathIndex = new Map(path.map((t, i) => [tileKey(t), i]));
  const variants = pathVariants(path.length, pathWeightsFor(season), tag);
  ctx.imageSmoothingQuality = "high";
  for (let row = 0; row < iso.size; row++) for (let col = 0; col < iso.size; col++) {
    const t = { col, row };
    const index = pathIndex.get(tileKey(t));
    const onPath = index !== undefined;
    const key = onPath
      ? `giardino/${winter ? "tessera_sentiero_neve" : "tessera_sentiero"}_${variants[index]! + 1}`
      : `giardino/${winter ? "tessera_neve" : "tessera_erba"}_${grass[row * iso.size + col]! + 1}`;
    const image = picture(key);
    const top = iso.point(col, row), left = iso.point(col, row + 1);
    if (image) ctx.drawImage(image, left.x - 0.6, top.y - 0.3, iso.tileW + 1.2, iso.tileH + 0.6);
    diamond(ctx, iso, t);
    if (image) {
      ctx.save();
      ctx.globalCompositeOperation = "multiply";
      if (season === "autumn") {
        ctx.fillStyle = onPath ? rgba(244, 220, 178) : rgba(236, 196, 120);
        ctx.fill();
      }
      // il sentiero un po' più scuro del prato (d'inverno meno, sulla neve)
      if (onPath) {
        ctx.fillStyle = winter ? rgba(226, 228, 238) : rgba(204, 188, 164);
        ctx.fill();
      }
      ctx.restore();
    } else {
      ctx.fillStyle = onPath ? rgba(226, 208, 170) : rgba(152, 197, 112);
      ctx.fill();
    }
    ctx.strokeStyle = rgba(255, 255, 255, carrying ? 0.34 : 0.14);
    ctx.lineWidth = 1;
    ctx.stroke();
  }
  // i dettagli sparsi sul terreno, dal fondo al davanti
  const placed: Array<{ depth: number; col: number; row: number; d: ReturnType<typeof decals>[number] }> = [];
  for (let row = 0; row < iso.size; row++) for (let col = 0; col < iso.size; col++) {
    for (const d of decals(col, row, season, pathIndex.has(tileKey({ col, row })), tag)) placed.push({ depth: col + row + d.u + d.v, col, row, d });
  }
  placed.sort((a, b) => a.depth - b.depth);
  for (const entry of placed) {
    const image = picture(`giardino/dettaglio_${entry.d.image + 1}`);
    if (!image) continue;
    const p = iso.point(entry.col + entry.d.u, entry.row + entry.d.v);
    const width = entry.d.size * iso.tileW, height = width * image.height / image.width;
    const x = p.x - width / 2, y = p.y - height * DECAL_ANCHORS[entry.d.group];
    ctx.save();
    if (entry.d.flipped) { ctx.translate(x + width / 2, 0); ctx.scale(-1, 1); ctx.translate(-(x + width / 2), 0); }
    ctx.drawImage(image, x, y, width, height);
    ctx.restore();
  }
}

function ground(iso: Iso, season: Season, island: string, dpr: number, version: number, carrying: boolean): Ground {
  const key = `${island}|${iso.size}|${Math.round(iso.tileW * 100)}|${season}|${dpr}|${version}|${carrying}`;
  const known = grounds.get(key);
  if (known) return known;
  const n = iso.size, margin = 40, top = iso.tileW * 0.6 + 20;
  const width = n * iso.tileW + 2 * margin, height = n * iso.tileH + iso.edge + top + margin;
  const made = makeCanvas(width * dpr, height * dpr);
  const ctx = made.getContext("2d")!;
  ctx.scale(dpr, dpr);
  paintGround(ctx, new Iso(n, iso.tileW, width / 2, top), season, island, carrying);
  const wash = islandWash(island, season);
  if (wash) {
    ctx.globalCompositeOperation = "source-atop";
    ctx.fillStyle = wash;
    ctx.fillRect(0, 0, width, height);
  }
  if (grounds.size >= 12) grounds.clear();
  const result = { canvas: made, width, height, originX: width / 2, originY: top };
  grounds.set(key, result);
  return result;
}

/** Il contorno dell'isola con i suoi lati di terra. */
function outline(ctx: CanvasRenderingContext2D, iso: Iso): void {
  const n = iso.size, t = iso.edge;
  const top = iso.point(0, 0), right = iso.point(n, 0), front = iso.point(n, n), left = iso.point(0, n);
  ctx.moveTo(top.x, top.y);
  ctx.lineTo(right.x, right.y);
  ctx.lineTo(right.x, right.y + t);
  ctx.lineTo(front.x, front.y + t);
  ctx.lineTo(left.x, left.y + t);
  ctx.lineTo(left.x, left.y);
  ctx.closePath();
}

// ---- le case e i ponti

function landmarkPlacement(island: string, iso: Iso): { x: number; y: number; sx: number; sy: number; sprite: Sprite; key: string } | null {
  const art = LANDMARK_ART[island];
  const key = `giardino/casa_${island}`;
  const s = ready(key);
  if (!art || !s) return null;
  const center = iso.point(LANDMARK_SIDE / 2, LANDMARK_SIDE / 2);
  const sx = iso.tileW * LANDMARK_SIDE / 2 / art.halfWidth, sy = iso.tileW * LANDMARK_SIDE / 4 / art.halfHeight;
  return { x: center.x - art.centerX * sx, y: center.y - art.centerY * sy, sx, sy, sprite: s, key };
}

function drawLandmark(ctx: CanvasRenderingContext2D, island: string, iso: Iso, open: boolean, dpr: number): void {
  const house = landmarkPlacement(island, iso);
  if (!house) return;
  const s = house.sprite;
  const x = house.x + s.src.x * house.sx, y = house.y + s.src.y * house.sy, w = s.src.w * house.sx, h = s.src.h * house.sy;
  if (x > SCENE_W + 300 || y > SCENE_H + 180 || x + w < -300 || y + h < -180) return;
  ctx.drawImage(scaled(s, house.key, w * dpr, h * dpr, open ? NO_TINT : { red: 92, green: 98, blue: 130 }), x, y, w, h);
}

/** Un pezzo di ponte, con il centro della sua striscia (lunga due tessere, larga una) su `center`; il disegno si scala a parte in larghezza e in altezza. */
function drawBridgePiece(ctx: CanvasRenderingContext2D, alongColumns: boolean, variant: number, center: { x: number; y: number }, tileW: number, dpr: number): void {
  const key = `giardino/ponte_${alongColumns ? "colonna" : "riga"}_${variant}`;
  const s = ready(key);
  if (!s) return;
  const sx = tileW / 122, sy = tileW / 150;
  const width = s.src.w * sx, height = s.src.h * sy;
  const anchorX = (alongColumns ? 119.5 : s.width - 119.5) - s.src.x;
  const anchorY = 127 - s.src.y;
  ctx.drawImage(scaled(s, key, width * dpr, height * dpr), center.x - anchorX * sx, center.y - anchorY * sy, width, height);
}

function drawBridges(ctx: CanvasRenderingContext2D, data: GardenData, camera: Camera, dpr: number): void {
  const world = worldIso(camera);
  for (const bridge of BRIDGES) {
    if (!data.bridges.includes(bridgeId(bridge))) continue;
    const first = data.islands.find((i) => i.id === bridge.first), second = data.islands.find((i) => i.id === bridge.second);
    if (!first?.open || !second?.open) continue;
    const span = bridgeSpan(bridge, first.size);
    if (!span) continue;
    bridgePieceCenters(span.from, span.to).forEach((center, index) => {
      const p = bridge.alongColumns ? world.point(center, span.across) : world.point(span.across, center);
      drawBridgePiece(ctx, bridge.alongColumns, index % 2 + 1, p, world.tileW, dpr);
    });
  }
}

// ---- la scena ferma: paesaggio, colline, terreni, case, ponti e luce, in un disegno solo (si rifà quando cambia qualcosa)

function applyLight(ctx: CanvasRenderingContext2D, light: GardenLight): void {
  if (light.tintStrength <= 0.001) return;
  const m = lightMultiplier(light);
  ctx.save();
  ctx.globalCompositeOperation = "multiply";
  ctx.fillStyle = rgba(m.red, m.green, m.blue);
  ctx.fillRect(-SCENE_W, -SCENE_H, SCENE_W * 3, SCENE_H * 3);
  ctx.restore();
}

/** I bordi scuriti del paesaggio e, di sera, il buio: stanno fermi sulla finestra. */
function drawOverlay(ctx: CanvasRenderingContext2D, season: Season, light: GardenLight): void {
  const radius = Math.hypot(SCENE_W / 2, SCENE_H / 2);
  const [r, g, b, a] = frozen(season) ? [0.14, 0.19, 0.28, 0.26] : [0.15, 0.20, 0.10, 0.30];
  radial(ctx, CENTER.x, CENTER.y, radius, [unit(r!, g!, b!, 0), unit(r!, g!, b!, a)]);
  if (light.tintStrength > 0.001 && light.darkness > 0.1) {
    radial(ctx, CENTER.x, CENTER.y, radius, [unit(0.55, 0.58, 0.80, 0), unit(0.28, 0.30, 0.55, Math.min(light.darkness * 1.3, 0.7))]);
  }
}

export function drawStaticScene(ctx: CanvasRenderingContext2D, data: GardenData, camera: Camera, light: GardenLight, dpr: number, version: number, carrying = false): void {
  drawBackdrop(ctx, camera, data.season);
  const islands = worldIslands(data, camera);
  for (const { island, iso } of islands) drawHill(ctx, iso, data.season, island.id, !island.open);
  for (const { island, iso } of islands) {
    const g = ground(iso, data.season, island.id, dpr, version, carrying);
    const x = iso.ox - g.originX, y = iso.oy - g.originY;
    if (x < SCENE_W + 300 && y < SCENE_H + 180 && x + g.width > -300 && y + g.height > -180) ctx.drawImage(g.canvas, x, y, g.width, g.height);
    if (!island.open) {
      ctx.fillStyle = unit(0.04, 0.06, 0.14, 0.66);
      ctx.beginPath();
      outline(ctx, iso);
      ctx.fill();
    }
  }
  for (const { island, iso } of islands) drawLandmark(ctx, island.id, iso, island.open, dpr);
  drawBridges(ctx, data, camera, dpr);
  applyLight(ctx, light);
}

// ---- le cose e i compagni, dal fondo al davanti

interface Entity {
  key: string;
  sprite: Sprite;
  feet: { x: number; y: number };
  rect: { x: number; y: number; w: number; h: number };
  shadow: { x: number; y: number; w: number; h: number } | null;
  turned: boolean;
  depth: number;
  placement: GardenPlacement | null;
  item: GardenItem | null;
  island: string;
}

function makeEntity(key: string, referenceHeight: number, feet: { x: number; y: number }, shadowWidth: number | null, turned: boolean,
  depth: number, iso: Iso): Omit<Entity, "placement" | "item" | "island"> | null {
  const s = ready(key);
  if (!s) return null;
  let height = referenceHeight * iso.scale, width = height * aspect(s);
  // una cosa sul lato è larga un lato di tessera, e la sua base obliqua ha i piedi a metà
  if (s.sideWidth !== null) {
    const k = iso.tileW / 2 / s.sideWidth;
    width = s.src.w * k;
    height = s.src.h * k;
  }
  const rect = { x: feet.x - s.feetAcross * width, y: feet.y - height + s.footDrop * height, w: width, h: height };
  let shadow = null;
  if (shadowWidth !== null) {
    const h = Math.max(shadowWidth * 0.34, 5);
    shadow = { x: feet.x - shadowWidth / 2, y: feet.y - h * 0.55, w: shadowWidth, h };
  }
  return { key, sprite: s, feet, rect, shadow, turned, depth };
}

/** Il disegno acceso è più alto di quello spento (la fiamma), con gli stessi piedi e la stessa larghezza. */
function litHeightFactor(x: GardenItem): number {
  const lit = litImage(x);
  const on = lit ? ready("giardino/" + lit) : null, off = ready("giardino/" + x.id);
  return on && off ? on.src.h / Math.max(off.src.h, 1) : 1;
}

/** Le cose e i compagni, dal fondo al davanti; `skip` è quella che si sta trascinando (l'id della copia, o `compagno:<id>`): si disegna a parte. */
function entities(data: GardenData, camera: Camera, light: GardenLight, skip: string | null = null): Entity[] {
  const result: Entity[] = [];
  const lit = lampAmount(light) >= LIT_THRESHOLD;
  const visible = (p: { x: number; y: number }): boolean => p.x > -80 && p.x < SCENE_W + 80 && p.y > -140 && p.y < SCENE_H + 140;
  for (const { island, iso } of worldIslands(data, camera)) {
    if (!island.open) continue;
    const corner = islandCorner(island.id)!;
    const base = corner.col + corner.row;
    const linked = new Map<string, Set<string>>();
    for (const p of island.placements) {
      if (!itemWithId(p.item)?.joins || p.id === skip) continue;
      const set = linked.get(p.item) ?? new Set<string>();
      set.add(tileKey(p));
      linked.set(p.item, set);
    }
    for (const p of island.placements) {
      const x = itemWithId(p.item);
      if (!x || p.id === skip) continue;
      const footprint = applyTurn(x.footprint, p.turned);
      const groundPoint = iso.point(p.col + footprint.cols / 2, p.row + footprint.rows / 2);
      if (!visible(groundPoint)) continue;
      const feet = { x: groundPoint.x, y: groundPoint.y + iso.tileH * (x.axial ? 0 : FEET_OFFSET) };
      const front = p.col + footprint.cols - 1 + p.row + footprint.rows - 1;
      const shadowWidth = x.castsShadow ? Math.min(iso.tileW * 0.62 * Math.max(footprint.cols, footprint.rows), iso.tileW * 1.3) : null;
      // il disegno: quelle che si uniscono ai vicini hanno i bracci (e non si specchiano), quelle con il disegno acceso di sera sono accese
      let key = "giardino/" + gardenImage(x), turned = p.turned, height = x.height;
      if (x.joins) {
        key = "giardino/" + joinedImage(x, linkArms(p, linked.get(x.id) ?? new Set(), p.turned));
        turned = false;
      } else if (lit && litImage(x)) {
        key = "giardino/" + litImage(x)!;
        height = x.height * litHeightFactor(x);
      }
      const made = makeEntity(key, height, feet, shadowWidth, turned, base + front + 0.5, iso);
      if (made) result.push({ ...made, placement: p, item: x, island: island.id });
    }
    if (island.companion && skip !== `compagno:${island.id}`) {
      const pet = petInfo(island.id);
      const groundPoint = iso.center(island.companion);
      if (visible(groundPoint)) {
        const feet = { x: groundPoint.x, y: groundPoint.y + iso.tileH * FEET_OFFSET };
        const made = makeEntity(pet.iconImage.replace(/\.png$/, ""), companionHeight(pet.id), feet, iso.tileW * 0.5, false,
          base + island.companion.col + island.companion.row + 1, iso);
        if (made) result.push({ ...made, placement: null, item: null, island: island.id });
      }
    }
  }
  return result.sort((a, b) => a.depth - b.depth);
}

function drawEntity(ctx: CanvasRenderingContext2D, e: Entity, season: Season, tint: Tint, dpr: number): void {
  if (e.shadow) {
    ctx.fillStyle = season === "winter" ? unit(0.30, 0.38, 0.52, 0.22) : unit(0.24, 0.32, 0.20, 0.28);
    ctx.beginPath();
    ctx.ellipse(e.shadow.x + e.shadow.w / 2, e.shadow.y + e.shadow.h / 2, e.shadow.w / 2, e.shadow.h / 2, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  const image = scaled(e.sprite, e.key, e.rect.w * dpr, e.rect.h * dpr, tint);
  ctx.save();
  if (e.turned) {
    const mid = e.rect.x + e.rect.w / 2;
    ctx.translate(mid, 0);
    ctx.scale(-1, 1);
    ctx.translate(-mid, 0);
  }
  ctx.drawImage(image, e.rect.x, e.rect.y, e.rect.w, e.rect.h);
  ctx.restore();
}

/** I lampioni accesi (e le altre luci): una luce calda attorno al disegno e una pozza sul prato. */
function drawLampGlows(ctx: CanvasRenderingContext2D, laid: Entity[], data: GardenData, camera: Camera, light: GardenLight): void {
  const strength = lampAmount(light);
  if (strength <= 0.01) return;
  // il lampione dell'angolo di lettura fa più luce
  const reading = new Set<string>();
  for (const island of data.islands) for (const id of formedCorners(island.placements).get("lettura") ?? []) reading.add(id);
  const tileW = worldView(camera).tileW;
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  for (const e of laid) {
    const glow = e.item?.glow;
    if (!glow || !e.placement) continue;
    if (e.item!.litDrawing && strength < LIT_THRESHOLD) continue;
    const boost = reading.has(e.placement.id) ? 1.45 : 1;
    const power = strength * glow.strength;
    const warm = (a: number): string => rgba(glow.red, glow.green, glow.blue, a);
    const radius = tileW * glow.radius;
    const top = { x: e.rect.x + e.rect.w / 2, y: e.rect.y + e.rect.h * glow.top };
    radial(ctx, top.x, top.y, radius * boost, [warm(0.48 * power * Math.min(boost, 1.2)), warm(0.14 * power * Math.min(boost, 1.2)), warm(0)]);
    radial(ctx, e.feet.x, e.feet.y, radius * 1.2 * boost, [warm(0.34 * power), warm(0)], 1, 0.5);
  }
  ctx.restore();
}

/** Di sera le finestre del casale si accendono (non sopra le isole, che stanno davanti). */
function drawCottageWindows(ctx: CanvasRenderingContext2D, data: GardenData, camera: Camera, light: GardenLight): void {
  const strength = lampAmount(light);
  if (strength <= 0.02) return;
  ctx.save();
  ctx.beginPath();
  ctx.rect(-20, -20, SCENE_W + 40, SCENE_H + 40);
  for (const { iso } of worldIslands(data, camera)) outline(ctx, iso);
  ctx.clip("evenodd");
  ctx.globalCompositeOperation = "lighter";
  for (const w of cottageWindows(data.season)) {
    const fixed = backdropPoint(w.u, w.v, data.season);
    if (!fixed) continue;
    const c = cameraPoint(fixed, camera);
    radial(ctx, c.x, c.y, 20 * 0.5 * camera.zoom * BACKDROP_SCALE * 0.55, [rgba(255, 208, 120, 0.8 * strength), rgba(255, 208, 120, 0.25 * strength), rgba(255, 208, 120, 0)]);
  }
  ctx.restore();
}

/** Di sera le finestre delle case si accendono. */
function drawLandmarkLights(ctx: CanvasRenderingContext2D, data: GardenData, camera: Camera, light: GardenLight): void {
  const strength = lampAmount(light);
  if (strength <= 0.02) return;
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  for (const { island, iso } of worldIslands(data, camera)) {
    if (!island.open) continue;
    const house = landmarkPlacement(island.id, iso);
    if (!house) continue;
    for (const lamp of LANDMARK_ART[island.id]!.lights) {
      const c = { x: house.x + lamp.u * house.sprite.width * house.sx, y: house.y + lamp.v * house.sprite.height * house.sy };
      if (c.x < -80 || c.y < -80 || c.x > SCENE_W + 80 || c.y > SCENE_H + 80) continue;
      radial(ctx, c.x, c.y, lamp.size * iso.tileW * 0.55, [rgba(255, 208, 120, 0.55 * strength), rgba(255, 208, 120, 0.18 * strength), rgba(255, 208, 120, 0)]);
    }
  }
  ctx.restore();
}

// ---- tutto insieme

/** La luce dell'ora e della stagione dei dati. */
export const lightOf = (data: GardenData): GardenLight => lightAt(data.hour, data.season);

export interface SceneLayers {
  /** La scena ferma già pronta, grande quanto la finestra (in pixel veri), con la chiave che dice quando rifarla. */
  still: HTMLCanvasElement | null;
  stillKey: string;
}

/** Quello che si sta trascinando: dove cadrebbe (le tessere verdi o rosse) e il suo disegno, sotto il mouse o sulla tessera. */
export interface Carrying {
  skip: string | null;
  tiles: GardenTile[];
  valid: boolean;
  island: string;
  ghost: { key: string; height: number; feet: { x: number; y: number }; shadowWidth: number | null; turned: boolean; alpha: number } | null;
}

function drawHighlight(ctx: CanvasRenderingContext2D, iso: Iso, tiles: GardenTile[], valid: boolean): void {
  for (const t of tiles) {
    if (!islandContains(t, iso.size)) continue;
    const top = iso.point(t.col, t.row), right = iso.point(t.col + 1, t.row), bottom = iso.point(t.col + 1, t.row + 1), left = iso.point(t.col, t.row + 1);
    const inset = 2;
    ctx.beginPath();
    ctx.moveTo(top.x, top.y + inset * 0.5);
    ctx.lineTo(right.x - inset, right.y);
    ctx.lineTo(bottom.x, bottom.y - inset * 0.5);
    ctx.lineTo(left.x + inset, left.y);
    ctx.closePath();
    ctx.fillStyle = valid ? rgba(80, 200, 105, 0.5) : rgba(226, 80, 66, 0.5);
    ctx.fill();
    ctx.strokeStyle = valid ? rgba(60, 160, 85) : rgba(190, 56, 46);
    ctx.lineWidth = 2;
    ctx.stroke();
  }
}

export function drawGarden(ctx: CanvasRenderingContext2D, layers: SceneLayers, data: GardenData, camera: Camera, dpr: number, version: number,
  carrying: Carrying | null = null): void {
  const light = lightOf(data);
  const key = JSON.stringify([camera, data.season, data.islands.map((i) => [i.id, i.size, i.open]), data.bridges, Math.round(light.darkness * 40),
    tintOf(lightMultiplier(light)), dpr, version, carrying !== null]);
  if (layers.still === null || layers.stillKey !== key) {
    const still = layers.still ?? makeCanvas(SCENE_W * dpr, SCENE_H * dpr);
    still.width = Math.round(SCENE_W * dpr);
    still.height = Math.round(SCENE_H * dpr);
    const s = still.getContext("2d")!;
    s.setTransform(dpr, 0, 0, dpr, 0, 0);
    s.imageSmoothingQuality = "high";
    drawStaticScene(s, data, camera, light, dpr, version, carrying !== null);
    drawOverlay(s, data.season, light);
    layers.still = still;
    layers.stillKey = key;
  }
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.drawImage(layers.still!, 0, 0);
  ctx.restore();
  const tint = tintOf(lightMultiplier(light));
  const island = carrying ? data.islands.find((i) => i.id === carrying.island) : undefined;
  const iso = island ? isoOf(island, camera) : null;
  if (carrying && iso) drawHighlight(ctx, iso, carrying.tiles, carrying.valid);
  const laid = entities(data, camera, light, carrying?.skip ?? null);
  for (const e of laid) drawEntity(ctx, e, data.season, tint, dpr);
  if (carrying?.ghost && iso) {
    const g = carrying.ghost;
    const made = makeEntity(g.key, g.height, g.feet, g.shadowWidth, g.turned, 0, iso);
    if (made) {
      ctx.save();
      ctx.globalAlpha = g.alpha;
      drawEntity(ctx, { ...made, rect: { ...made.rect, y: made.rect.y - 6 }, placement: null, item: null, island: carrying.island }, data.season, tint, dpr);
      ctx.restore();
    }
  }
  drawLampGlows(ctx, laid, data, camera, light);
  drawCottageWindows(ctx, data, camera, light);
  drawLandmarkLights(ctx, data, camera, light);
}

// ---- per il mouse: cosa c'è sotto un punto, e dove ci sta una cosa

export type Hit = { kind: "placed"; id: string; island: string; feet: { x: number; y: number } } | { kind: "companion"; pet: string; island: string; feet: { x: number; y: number }; rect: { x: number; y: number; w: number; h: number } };

/** La cosa più davanti sotto il punto, contando solo dove l'immagine è disegnata (con una cella di margine). */
export function hitAt(data: GardenData, camera: Camera, x: number, y: number): Hit | null {
  const laid = entities(data, camera, lightOf(data));
  for (let i = laid.length - 1; i >= 0; i--) {
    const e = laid[i]!;
    if (x < e.rect.x || y < e.rect.y || x > e.rect.x + e.rect.w || y > e.rect.y + e.rect.h) continue;
    let u = (x - e.rect.x) / e.rect.w;
    const v = (y - e.rect.y) / e.rect.h;
    if (e.turned) u = 1 - u;
    if (!isDrawn(e.sprite, u, v)) continue;
    if (e.placement) return { kind: "placed", id: e.placement.id, island: e.island, feet: e.feet };
    return { kind: "companion", pet: e.island, island: e.island, feet: e.feet, rect: e.rect };
  }
  return null;
}

/** L'isola sotto un punto della scena (dentro i suoi bordi), se c'è. */
export function islandAt(data: GardenData, camera: Camera, x: number, y: number): string | null {
  const islands = worldIslands(data, camera);
  for (let i = islands.length - 1; i >= 0; i--) {
    const { island, iso } = islands[i]!;
    const g = iso.grid(x, y);
    if (g.col >= -0.2 && g.row >= -0.2 && g.col < iso.size + 0.2 && g.row < iso.size + 0.2) return island.id;
  }
  return null;
}

/** Le tessere coperte dalle copie di un'isola e dalla sua casa (senza `ignoring`). */
function occupiedOn(island: GardenIslandData, ignoring: string | null): Set<string> {
  const result = occupiedTiles(island.placements, ignoring);
  for (const t of landmarkTiles(island.id)) result.add(tileKey(t));
  return result;
}

/** Ci sta una copia di `item` con l'angolo in fondo su `origin`? (Le stesse regole di `Garden.canPlace`.) */
export function canPlaceOn(island: GardenIslandData, item: string, origin: GardenTile, turned: boolean, ignoring: string | null): boolean {
  const x = itemWithId(item);
  if (!x || !fitsIsland(x, island.id)) return false;
  return canPlaceFootprint(applyTurn(x.footprint, turned), origin, island.size, occupiedOn(island, ignoring), island.id);
}

/** Un compagno può andare lì? Su una tessera dove si cammina. */
export function canStandOn(island: GardenIslandData, t: GardenTile): boolean {
  return isWalkable(t, island.size, occupiedOn(island, null));
}

/** Dove stanno i piedi di un oggetto messo con l'angolo in fondo su `origin`. */
export function feetOf(iso: Iso, item: GardenItem, origin: GardenTile, turned: boolean): { x: number; y: number } {
  const footprint = applyTurn(item.footprint, turned);
  const p = iso.point(origin.col + footprint.cols / 2, origin.row + footprint.rows / 2);
  return { x: p.x, y: p.y + iso.tileH * (item.axial ? 0 : FEET_OFFSET) };
}

export { FEET_OFFSET };
