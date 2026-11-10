// Il disegno del giardino, come GardenView in GardenWindow.swift: il paesaggio, le colline, il terreno delle isole, le case, i ponti, le cose e i
// compagni, la luce dell'ora e della stagione. Le misure sono quelle della scena del Mac (1000 × 600 punti); la telecamera (zoom e spostamento) è
// una sola per tutto il mondo. Qui c'è solo il disegno: le regole sono in `core/garden*.ts`.

import { applyTurn, companionHeight, fitsIsland, gardenImage, itemWithId, joinedImage, litImage, swayStrength, waterSpot } from "../../core/gardenCatalog.ts";
import { poseImage } from "../../core/gardenCompanions.ts";
import type { GardenPose } from "../../core/gardenCompanions.ts";
import { interactionImage } from "../../core/gardenInteractions.ts";
import type { GardenInteraction } from "../../core/gardenInteractions.ts";
import { hash } from "../../core/gardenDrops.ts";
import type { GardenItem } from "../../core/gardenCatalog.ts";
import { formedCorners } from "../../core/gardenCorners.ts";
import {
  BRIDGES, bridgeId, bridgePieceCenters, bridgeSpan, canPlaceFootprint, decals, DECAL_ANCHORS, GRASS_COUNT, grassGrid, grassWeightsFor, HILL_BELOW_RATIO, HILL_HEIGHT_RATIO,
  HILL_WIDTH_RATIO, hillFrame, ISLAND_MAX_SIZE, islandContains, islandCorner, isWalkable, LANDMARK_ART, LANDMARK_SIDE, landmarkTiles, linkArms, occupiedTiles, PATH_COUNT,
  pathTiles, pathVariants, pathWeightsFor,
  terrainTag, tileKey, WORLD_EXTENT, WORLD_REACH, worldSlot,
} from "../../core/gardenGrid.ts";
import type { GardenPlacement, GardenTile } from "../../core/gardenGrid.ts";
import {
  burstStar, BURST_STAR_COUNT, butterfly, cornerFirefly, drift, firefly, FIREFLY_COUNT, fireflyAmount, lampAmount, lightAt, lightMultiplier, particle,
  particleCount, particleKind, ripple, smoke, smokeAmount, SMOKE_COUNT, smoothstep, sparkle, SPARKLE_COUNT, sway, wind,
} from "../../core/gardenSky.ts";
import type { GardenLight, Season } from "../../core/gardenSky.ts";
import { petInfo } from "../../core/pets.ts";
import type { GardenData, GardenIslandData } from "../../shared/gardenApi.ts";
import { aspect, isDrawn, makeCanvas, NO_TINT, picture, ready, scaled, sprite, tintOf } from "./sprites.ts";
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
const WORLD_MARGIN = { top: 340, left: 480, bottom: 520, right: 960 };

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
    case "tartaruga": return rgba(132, 160, 82, 0.24 * k);
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

/** Dove stanno i pezzi di un ponte alla vista di adesso (niente se una delle due isole è chiusa). */
function bridgePieces(bridge: (typeof BRIDGES)[number], data: GardenData, camera: Camera): Array<{ x: number; y: number; variant: number }> {
  const first = data.islands.find((i) => i.id === bridge.first), second = data.islands.find((i) => i.id === bridge.second);
  if (!first?.open || !second?.open) return [];
  const span = bridgeSpan(bridge, first.size);
  if (!span) return [];
  const world = worldIso(camera);
  return bridgePieceCenters(span.from, span.to).map((center, index) => {
    const p = bridge.alongColumns ? world.point(center, span.across) : world.point(span.across, center);
    return { ...p, variant: index % 2 + 1 };
  });
}

/** Quanti pezzi hanno questi ponti, in tutto. */
export function pieceCount(data: GardenData, ids: readonly string[]): number {
  return BRIDGES.filter((b) => ids.includes(bridgeId(b))).reduce((sum, b) => sum + bridgePieces(b, data, { zoom: 1, panX: 0, panY: 0 }).length, 0);
}

function drawBridges(ctx: CanvasRenderingContext2D, data: GardenData, camera: Camera, dpr: number, building: readonly string[] = []): void {
  const world = worldIso(camera);
  for (const bridge of BRIDGES) {
    if (!data.bridges.includes(bridgeId(bridge)) || building.includes(bridgeId(bridge))) continue;
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

export function drawStaticScene(ctx: CanvasRenderingContext2D, data: GardenData, camera: Camera, light: GardenLight, dpr: number, version: number, carrying = false,
  building: readonly string[] = []): void {
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
  drawBridges(ctx, data, camera, dpr, building);
  applyLight(ctx, light);
}

// ---- le cose e i compagni, dal fondo al davanti

/** La vita sull'isola, com'è in questo momento (la tiene aggiornata la pagina, `life.ts`): l'ora degli effetti, i compagni che camminano o fanno una
 *  posa, l'ospite. Il disegno la legge da qui. */
export interface WalkerView {
  from: GardenTile; to: GardenTile; progress: number; pose: GardenPose | null;
  /** Se sta usando una cosa (`GardenInteractions`): quale copia, quale scena, da quando. Intanto lui non si vede. */
  scene?: { placement: string; interaction: GardenInteraction; started: number } | null;
}
export interface VisitorView {
  id: string; image: string; height: number; island: string; from: GardenTile; to: GardenTile; progress: number; walking: boolean;
  facingRight: boolean; fade: number; hint: boolean;
}
export const life: { time: number; reduceMotion: boolean; walkers: Map<string, WalkerView>; visitor: VisitorView | null } = {
  time: 0, reduceMotion: false, walkers: new Map(), visitor: null,
};

interface Entity {
  kind: "placed" | "companion" | "visitor";
  alpha: number;
  /** Quanto ondeggia col vento (0 = fermo) e da dove parte l'onda; dov'è l'acqua nel disegno, se c'è. */
  sway: number;
  seed: number;
  tile: GardenTile;
  water: ReturnType<typeof waterSpot>;
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
  depth: number, iso: Iso): Omit<Entity, "placement" | "item" | "island" | "kind" | "alpha" | "sway" | "seed" | "tile" | "water"> | null {
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

/** La cosa usata da un compagno: la scena con lui dentro al posto del disegno della cosa, messa in modo che la cosa resti dov'era (come `sceneEntity` in
 *  GardenWindow.swift). Le cose sul lato passano per lo stesso disegno storto. Null finché l'immagine non è pronta (intanto si vede la cosa). */
function sceneEntity<T extends { key: string; sprite: Sprite; rect: { x: number; y: number; w: number; h: number }; turned: boolean }>(
  scene: GardenInteraction, made: T, x: GardenItem, key: string): T | null {
  if (x.axial) {
    const swapped = key.replace("giardino/" + x.id, interactionImage(scene));
    const s = ready(swapped);
    if (!s) { void sprite(swapped); return null; }
    return { ...made, key: swapped, sprite: s };
  }
  const own = interactionImage(scene), s = ready(own);
  if (!s) { void sprite(own); return null; }
  const k = made.rect.w / (made.sprite.width * scene.scale);
  const w = s.width * k, h = s.height * k;
  let left = made.rect.x - scene.x * k;
  if (made.turned) left = 2 * (made.rect.x + made.rect.w / 2) - left - w;      // specchiata: la scena si specchia attorno alla cosa
  return { ...made, key: own, sprite: s, rect: { x: left, y: made.rect.y - scene.y * k, w, h } };
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
    // le bandierine di una festa in giardino ondeggiano di più
    const party = new Set(formedCorners(island.placements).get("festa") ?? []);
    // le cose che un compagno sta usando diventano la scena con lui dentro
    const inUse = new Map<string, GardenInteraction>();
    for (const w of life.walkers.values()) if (w.scene) inUse.set(w.scene.placement, w.scene.interaction);
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
      let made = makeEntity(key, height, feet, shadowWidth, turned, base + front + 0.5, iso);
      const used = inUse.get(p.id);
      if (made && used) made = sceneEntity(used, made, x, key) ?? made;
      if (made) {
        result.push({
          ...made, kind: "placed", alpha: 1, sway: swayStrength(x) * (party.has(p.id) ? 1.7 : 1), seed: (hash(p.id) % 1000) / 1000, tile: { col: p.col, row: p.row },
          water: waterSpot(x), placement: p, item: x, island: island.id,
        });
      }
    }
    if (island.companion && skip !== `compagno:${island.id}` && !life.walkers.get(island.id)?.scene) {
      const pet = petInfo(island.id);
      // dove sta in questo momento: cammina da una tessera all'altra, con un saltello
      const walker = life.walkers.get(island.id) ?? { from: island.companion, to: island.companion, progress: 1, pose: null };
      const from = iso.center(walker.from), to = iso.center(walker.to);
      const t = walker.progress * walker.progress * (3 - 2 * walker.progress);
      const hop = walker.progress < 1 ? Math.sin(walker.progress * Math.PI) * iso.tileH * 0.18 : 0;
      const groundPoint = { x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t - hop };
      const cols = walker.from.col + (walker.to.col - walker.from.col) * t, rows = walker.from.row + (walker.to.row - walker.from.row) * t;
      if (visible(groundPoint)) {
        const feet = { x: groundPoint.x, y: groundPoint.y + iso.tileH * FEET_OFFSET };
        // se sta facendo una posa, il fotogramma di quel momento (se l'immagine c'è)
        const pose = walker.pose ? poseImage(pet.id, walker.pose, life.time) : null;
        const key = pose && ready(pose) ? pose : pet.iconImage.replace(/\.png$/, "");
        const made = makeEntity(key, companionHeight(pet.id), feet, iso.tileW * 0.5, false, base + cols + rows + 1, iso);
        if (made) result.push({ ...made, kind: "companion", alpha: 1, sway: 0, seed: 0, tile: walker.to, water: null, placement: null, item: null, island: island.id });
      }
    }
    const guest = life.visitor;
    if (guest && guest.island === island.id) {
      const from = iso.center(guest.from), to = iso.center(guest.to);
      const t = guest.progress * guest.progress * (3 - 2 * guest.progress);
      const hop = guest.walking ? Math.sin(guest.progress * Math.PI) * iso.tileH * 0.14 : 0;
      const feet = { x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t - hop + iso.tileH * FEET_OFFSET };
      const cols = guest.from.col + (guest.to.col - guest.from.col) * t, rows = guest.from.row + (guest.to.row - guest.from.row) * t;
      const made = makeEntity("giardino/" + guest.image, guest.height, feet, iso.tileW * 0.34, !guest.facingRight, base + cols + rows + 1, iso);
      if (made) result.push({ ...made, kind: "visitor", alpha: guest.fade, sway: 0, seed: 0, tile: guest.to, water: null, placement: null, item: null, island: island.id });
    }
  }
  return result.sort((a, b) => a.depth - b.depth);
}

function drawEntity(ctx: CanvasRenderingContext2D, e: Entity, season: Season, tint: Tint, dpr: number, tileW = 0): void {
  ctx.save();
  ctx.globalAlpha *= e.alpha;
  if (e.shadow) {
    ctx.fillStyle = season === "winter" ? unit(0.30, 0.38, 0.52, 0.22) : unit(0.24, 0.32, 0.20, 0.28);
    ctx.beginPath();
    ctx.ellipse(e.shadow.x + e.shadow.w / 2, e.shadow.y + e.shadow.h / 2, e.shadow.w / 2, e.shadow.h / 2, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  const image = scaled(e.sprite, e.key, e.rect.w * dpr, e.rect.h * dpr, tint);
  if (e.turned) {
    const mid = e.rect.x + e.rect.w / 2;
    ctx.translate(mid, 0);
    ctx.scale(-1, 1);
    ctx.translate(-mid, 0);
  }
  if (e.sway > 0 && !life.reduceMotion && tileW > 0) {
    // una pianta piegata dal vento: a strisce orizzontali, ognuna spostata di lato un po' di più della sottostante (la base sta ferma, la cima oscilla)
    const amplitude = e.sway * wind(season) * 2.6 * tileW / 94;
    const strips = 12, ph = image.height;
    for (let i = 0; i < strips; i++) {
      const first = Math.floor(i * ph / strips), last = Math.min(Math.floor((i + 1) * ph / strips) + (i === strips - 1 ? 0 : 1), ph);
      const middle = (first + (last - first) / 2) / ph;
      const dx = sway(life.time, e.tile.col, e.tile.row, e.seed, 1 - middle) * amplitude;
      ctx.drawImage(image, 0, first, image.width, last - first, e.rect.x + dx, e.rect.y + e.rect.h * first / ph, e.rect.w, e.rect.h * (last - first) / ph);
    }
  } else {
    ctx.drawImage(image, e.rect.x, e.rect.y, e.rect.w, e.rect.h);
  }
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
    // una fiamma vibra piano (non con «Riduci movimento»)
    const flicker = glow.flickers && !life.reduceMotion ? 1 + 0.09 * (Math.sin(life.time * 6.1 + e.seed * 40) + 0.6 * Math.sin(life.time * 11.3 + e.seed * 17)) : 1;
    const power = strength * glow.strength * flicker;
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

// ---- la vita ferma: l'acqua che luccica, il fumo, quello che cade, le lucciole, gli effetti degli angoli

/** Un colore sopra la scena (che è già tinta dalla luce): si tinge allo stesso modo. */
function litColor(r: number, g: number, b: number, a: number, light: GardenLight): string {
  const m = lightMultiplier(light);
  return rgba(r * m.red / 255, g * m.green / 255, b * m.blue / 255, a);
}

/** I luccichii e il cerchio d'acqua sulla vaschetta del bagnetto. */
function drawWater(ctx: CanvasRenderingContext2D, e: Entity, light: GardenLight): void {
  const spot = e.water;
  if (!spot) return;
  const cx = e.rect.x + spot.u * e.rect.w, cy = e.rect.y + spot.v * e.rect.h;
  const halfW = spot.halfWidth * e.rect.w, halfH = spot.halfHeight * e.rect.h;
  const time = life.reduceMotion ? 0 : life.time;
  ctx.save();
  ctx.beginPath();
  ctx.ellipse(cx, cy, halfW, halfH, 0, 0, Math.PI * 2);
  ctx.clip();
  const r = ripple(time, (e.tile.col * 7 + e.tile.row * 3) / 31);
  if (!life.reduceMotion && r.alpha > 0.01) {
    ctx.beginPath();
    ctx.ellipse(cx + r.x * halfW, cy + r.y * halfH, r.phase * halfW / 2, r.phase * halfH / 2, 0, 0, Math.PI * 2);
    ctx.strokeStyle = rgba(255, 255, 255, r.alpha);
    ctx.lineWidth = 1;
    ctx.stroke();
  }
  ctx.globalCompositeOperation = "lighter";
  const strength = 1 - light.darkness * 0.8;
  for (let i = 0; i < SPARKLE_COUNT; i++) {
    const s = sparkle(i, time);
    const a = s.glow * strength;
    if (a <= 0.03) continue;
    const x = cx + s.x * halfW, y = cy + s.y * halfH;
    radial(ctx, x, y, 4.5, [rgba(255, 255, 255, 0.8 * a), rgba(255, 255, 255, 0)]);
    ctx.fillStyle = rgba(255, 255, 255, Math.min(1, a * 1.2));
    ctx.beginPath();
    ctx.ellipse(x, y, 1, 1, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

/** Il fumo che esce dal camino del casale (sullo sfondo, dietro le isole). */
function drawChimneySmoke(ctx: CanvasRenderingContext2D, data: GardenData, camera: Camera): void {
  const amount = smokeAmount(data.season);
  const chimney = frozen(data.season) ? { u: 0.1198, v: 0.3110 } : { u: 0.1336, v: 0.3111 };
  const fixed = backdropPoint(chimney.u, chimney.v, data.season);
  if (amount <= 0.01 || !fixed) return;
  const mouth = cameraPoint(fixed, camera);
  ctx.save();
  ctx.beginPath();
  ctx.rect(-20, -20, SCENE_W + 40, SCENE_H + 40);
  for (const { iso } of worldIslands(data, camera)) outline(ctx, iso);
  ctx.clip("evenodd");
  const time = life.reduceMotion ? 3 : life.time;
  // sul bianco della neve il fumo chiaro non si vedrebbe: un po' più grigio
  const color = data.season === "winter" ? [204, 204, 214] : [226, 222, 224];
  const k = 0.5 * camera.zoom * BACKDROP_SCALE;
  for (let i = 0; i < SMOKE_COUNT; i++) {
    const puff = smoke(i, time, wind(data.season));
    const a = Math.min(puff.alpha * amount * 1.5, 0.8);
    if (a <= 0.01) continue;
    radial(ctx, mouth.x + puff.dx * k, mouth.y + puff.dy * k, puff.radius * 1.7 * k,
      [rgba(color[0]!, color[1]!, color[2]!, a), rgba(color[0]!, color[1]!, color[2]!, a * 0.55), rgba(color[0]!, color[1]!, color[2]!, 0)]);
  }
  ctx.restore();
}

/** Petali, foglie o neve che cadono, a seconda della stagione. */
function drawWeather(ctx: CanvasRenderingContext2D, season: Season, light: GardenLight): void {
  const kind = particleKind(season);
  if (!kind || life.reduceMotion) return;
  const leaves = [[214, 120, 50], [190, 84, 44], [226, 168, 60], [150, 104, 52]];
  for (let i = 0; i < particleCount(kind); i++) {
    const p = particle(kind, i, life.time, SCENE_W, SCENE_H);
    const c = kind === "petal" ? (p.tone < 0.5 ? [255, 196, 214] : [255, 238, 242]) : kind === "leaf" ? leaves[Math.min(Math.floor(p.tone * 4), 3)]! : [255, 255, 255];
    ctx.fillStyle = litColor(c[0]!, c[1]!, c[2]!, kind === "snow" ? p.alpha * 0.9 : p.alpha, light);
    ctx.beginPath();
    if (kind === "snow") {
      ctx.ellipse(p.x, p.y, p.size / 2, p.size / 2, 0, 0, Math.PI * 2);
    } else {
      const w = kind === "leaf" ? p.size * 1.7 : p.size * 1.5, h = kind === "leaf" ? p.size * 0.85 : p.size;
      ctx.ellipse(p.x, p.y, w / 2, h / 2, p.angle, 0, Math.PI * 2);
    }
    ctx.fill();
  }
}

/** Le lucciole: di sera, soprattutto d'estate. */
function drawFireflies(ctx: CanvasRenderingContext2D, season: Season, light: GardenLight): void {
  const amount = fireflyAmount(season, light);
  if (amount <= 0.01 || life.reduceMotion) return;
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  for (let i = 0; i < FIREFLY_COUNT; i++) {
    const f = firefly(i, life.time, SCENE_W, SCENE_H);
    const a = f.glow * amount;
    if (a <= 0.02) continue;
    radial(ctx, f.x, f.y, 10, [rgba(255, 238, 140, 0.85 * a), rgba(255, 238, 140, 0)]);
    ctx.fillStyle = rgba(255, 252, 210, Math.min(1, a * 1.3));
    ctx.beginPath();
    ctx.ellipse(f.x, f.y, 1.4, 1.4, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

/** Finché non l'hai salutato, sopra l'ospite c'è una stellina che pulsa piano. */
function drawVisitorHint(ctx: CanvasRenderingContext2D, laid: Entity[]): void {
  if (!life.visitor?.hint) return;
  const e = laid.find((x) => x.kind === "visitor");
  if (!e) return;
  const pulse = life.reduceMotion ? 0.5 : 0.5 + 0.5 * Math.sin(life.time * 3);
  starPath(ctx, e.rect.x + e.rect.w / 2, e.rect.y - 9 - 2 * pulse, 5 + 2 * pulse, 0);
  ctx.fillStyle = rgba(255, 208, 70, 0.75 + 0.25 * pulse);
  ctx.fill();
  ctx.strokeStyle = rgba(226, 140, 28);
  ctx.lineWidth = 0.9;
  ctx.stroke();
}

/** Una lettera o un simbolo (la «z» del sonno, un cuore, una nota) centrato su un punto e girato di `angle`. */
function glyph(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number, color: string, angle = 0): void {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(angle);
  ctx.font = `900 ${size}px system-ui, "Segoe UI", sans-serif`;
  ctx.fillStyle = color;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(text, 0, 0);
  ctx.restore();
}

/** Quello che gli angoli formati fanno sull'isola mostrata: vapore dal tavolino, gocce dall'annaffiatoio, «z», cuori e note dalle case, farfalle sul prato
 *  fiorito, nebbia e lucciole nel bosco, coriandoli alla festa, petali e luce rosata sotto l'arco. Niente con «Riduci movimento». */
/** Mentre un compagno usa una cosa: le «z» che salgono da chi dorme, gli schizzi d'acqua di chi fa il bagno (come in GardenWindow.swift). */
function drawInteractionEffects(ctx: CanvasRenderingContext2D, laid: Entity[], camera: Camera, light: GardenLight): void {
  if (life.reduceMotion) return;
  const tileW = worldView(camera).tileW, tileH = tileW / 2;
  for (const walker of life.walkers.values()) {
    const scene = walker.scene;
    if (!scene || scene.interaction.effect === "none") continue;
    const shown = laid.find((e) => e.placement?.id === scene.placement);
    if (!shown) continue;
    const r = shown.rect, time = life.time - scene.started;
    if (scene.interaction.effect === "sleep") {
      const ox = r.x + r.w / 2 + r.w * 0.12, oy = r.y + r.h * 0.25;
      for (let i = 0; i < 2; i++) {
        const d = drift(i + 3, time, 3.2);
        glyph(ctx, "z", ox + d.x * tileW * 0.12, oy - d.progress * tileH, 11 + d.progress * 6, litColor(110, 130, 190, d.alpha * 0.9, light), Math.sin(d.spin) * 0.25);
      }
    } else {
      for (let i = 0; i < 4; i++) {
        const d = drift(i + 11, time, 0.9);
        // un piccolo arco: sale e ricade, di lato
        ctx.fillStyle = litColor(150, 200, 238, d.alpha * 0.85, light);
        ctx.beginPath();
        ctx.ellipse(r.x + r.w / 2 + d.x * r.w * 0.45, r.y + r.h * 0.35 - Math.sin(d.progress * Math.PI) * tileH * 0.5, 1.5, 2, 0, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }
}

function drawCornerEffects(ctx: CanvasRenderingContext2D, laid: Entity[], data: GardenData, camera: Camera, light: GardenLight): void {
  const shown = data.islands.find((i) => i.id === data.shown);
  if (life.reduceMotion || !shown) return;
  const formed = formedCorners(shown.placements);
  if (formed.size === 0) return;
  const time = life.time;
  const tileW = worldView(camera).tileW, tileH = tileW / 2;
  const member = (corner: string, item: string): Entity | undefined => {
    const ids = formed.get(corner);
    return ids ? laid.find((e) => e.placement && e.island === shown.id && ids.includes(e.placement.id) && e.placement.item === item) : undefined;
  };
  const center = (corner: string): { x: number; y: number } | null => {
    const ids = formed.get(corner);
    const feet = ids ? laid.filter((e) => e.placement && e.island === shown.id && ids.includes(e.placement.id)).map((e) => e.feet) : [];
    return feet.length === 0 ? null : { x: feet.reduce((s, f) => s + f.x, 0) / feet.length, y: feet.reduce((s, f) => s + f.y, 0) / feet.length };
  };
  const rect = (e: Entity) => e.rect;
  // il tè: un filo di vapore dal tavolino
  const table = member("te", "tavolino");
  if (table) {
    const r = rect(table), ox = r.x + r.w / 2 - r.w * 0.06, oy = r.y + r.h * 0.30, k = tileW / 185;
    for (let i = 0; i < 4; i++) {
      const puff = smoke(i * 2, time, 0.15);
      const a = puff.alpha * 0.9;
      if (a <= 0.01) continue;
      radial(ctx, ox + puff.dx * k, oy + puff.dy * k, puff.radius * 2.1 * k,
        [litColor(188, 196, 214, Math.min(a * 1.5, 0.85), light), litColor(188, 196, 214, a * 0.7, light), litColor(188, 196, 214, 0, light)]);
    }
  }
  // l'orto: le gocce dell'annaffiatoio
  const can = member("orto", "annaffiatoio");
  if (can) {
    const r = rect(can), ox = r.x + r.w * 0.12, oy = r.y + r.h * 0.42;
    for (let i = 0; i < 3; i++) {
      const d = drift(i, time, 1.1);
      ctx.fillStyle = litColor(150, 200, 238, d.alpha * 0.9, light);
      ctx.beginPath();
      ctx.ellipse(ox + d.x * tileW * 0.05, oy + d.progress * tileH * 1.1, 1.6, 2.8, 0, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  // il gatto dorme, il porcellino è contento, gli uccelli cantano
  for (const [corner, item, text, c, period] of [["gatto", "casetta-gatto", "z", [110, 130, 190], 3.2], ["porcellino", "casetta-porcellino", "♥", [238, 118, 150], 3.6],
    ["uccelli", "casetta-uccelli", "♪", [96, 150, 205], 3.0]] as const) {
    const house = member(corner, item);
    if (!house) continue;
    const r = rect(house), ox = r.x + r.w / 2 + r.w * 0.06, oy = r.y + r.h * 0.30;
    for (let i = 0; i < 2; i++) {
      const d = drift(i + 3, time, period);
      glyph(ctx, text, ox + d.x * tileW * 0.12, oy - d.progress * tileH, 11 + d.progress * 6, litColor(c[0], c[1], c[2], d.alpha * 0.9, light), Math.sin(d.spin) * 0.25);
    }
  }
  // il prato fiorito: le farfalle (non d'inverno)
  const meadow = center("prato-fiorito");
  if (data.season !== "winter" && meadow) {
    const colors = [[240, 150, 60], [120, 170, 232], [240, 140, 186]];
    for (let i = 0; i < 3; i++) {
      const b = butterfly(i, time);
      const x = meadow.x + b.x * tileW * 0.95, y = meadow.y - tileH * 1.1 + b.y * tileH * 0.9;
      const wing = tileW * 0.06, spread = 0.25 + b.flap * 0.75, c = colors[i]!;
      ctx.fillStyle = litColor(c[0]!, c[1]!, c[2]!, 1, light);
      ctx.beginPath();
      ctx.ellipse(x - wing * 0.95 * spread, y - wing * 0.2, wing * 0.95 * spread, wing * 0.8, 0, 0, Math.PI * 2);
      ctx.ellipse(x + wing * 0.95 * spread, y - wing * 0.2, wing * 0.95 * spread, wing * 0.8, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = litColor(70, 52, 44, 1, light);
      ctx.beginPath();
      ctx.ellipse(x, y + wing * 0.05, 0.7, wing * 0.95, 0, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  // il bosco: la nebbia di giorno, le lucciole la sera (non d'inverno)
  const wood = center("bosco");
  if (wood) {
    const lamp = lampAmount(light);
    if (lamp < 0.5) {
      const shift = Math.sin(time * 0.12) * tileW * 0.3;
      for (let layer = 0; layer < 2; layer++) {
        const a = (0.17 + 0.05 * Math.sin(time * 0.3 + layer)) * (1 - lamp * 2);
        radial(ctx, wood.x + shift * (layer === 0 ? 1 : -0.7), wood.y - tileH * (0.25 + layer * 0.3), tileW * 1.4,
          [litColor(255, 255, 255, a, light), litColor(255, 255, 255, 0, light)], 1, 0.38);
      }
    }
    const evening = smoothstep(light.darkness, 0.2, 0.45);
    if (data.season !== "winter" && evening > 0.01) {
      ctx.save();
      ctx.globalCompositeOperation = "lighter";
      for (let i = 0; i < 6; i++) {
        const f = cornerFirefly(i, time);
        const a = f.glow * evening;
        if (a <= 0.02) continue;
        const x = wood.x + f.x * tileW, y = wood.y - tileH * 0.9 + f.y * tileH * 1.1;
        radial(ctx, x, y, 10, [rgba(255, 238, 140, 0.85 * a), rgba(255, 238, 140, 0)]);
        ctx.fillStyle = rgba(255, 252, 210, Math.min(1, a * 1.3));
        ctx.beginPath();
        ctx.ellipse(x, y, 1.4, 1.4, 0, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
    }
  }
  // la festa: i coriandoli che cadono dalle bandierine
  const flags = member("festa", "bandierine");
  if (flags) {
    const colors = [[240, 128, 160], [250, 205, 80], [110, 170, 235], [130, 200, 140], [242, 160, 80], [170, 130, 220]];
    const r = rect(flags), ox = r.x + r.w / 2, oy = r.y + r.h * 0.22;
    for (let i = 0; i < 6; i++) {
      const d = drift(i + 10, time, 3), c = colors[i]!;
      ctx.save();
      ctx.translate(ox + d.x * r.w * 0.45, oy + d.progress * tileH * 1.7);
      ctx.rotate(d.spin);
      ctx.fillStyle = litColor(c[0]!, c[1]!, c[2]!, d.alpha, light);
      ctx.fillRect(-2, -3.2, 4, 6.4);
      ctx.restore();
    }
  }
  // l'arco delle rose: i petali che cadono e, di sera, una luce rosata
  const arch = member("rose", "arco-rose");
  if (arch) {
    const r = rect(arch), ox = r.x + r.w / 2, oy = r.y + r.h * 0.20;
    for (let i = 0; i < 5; i++) {
      const d = drift(i + 20, time, 4.2);
      ctx.save();
      ctx.translate(ox + d.x * r.w * 0.32, oy + d.progress * r.h * 0.8);
      ctx.rotate(d.spin);
      ctx.fillStyle = litColor(246, 150, 178, d.alpha * 0.95, light);
      ctx.beginPath();
      ctx.ellipse(0, 0, 3.2, 2.1, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
    const glow = lampAmount(light);
    if (glow > 0.02) {
      ctx.save();
      ctx.globalCompositeOperation = "lighter";
      radial(ctx, r.x + r.w / 2, r.y + r.h * 0.45, tileW * 0.95, [rgba(255, 150, 186, 0.26 * glow), rgba(255, 150, 186, 0)]);
      ctx.restore();
    }
  }
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

/** Gli effetti del momento: i ponti che si stanno costruendo (da quanto, in secondi) e le stelline (dove e a che punto). */
export interface Effects {
  building: { ids: string[]; elapsed: number } | null;
  bursts: Array<{ x: number; y: number; progress: number }>;
  reduceMotion: boolean;
}

/** La cerimonia: dopo che la telecamera è arrivata, i pezzi dei ponti compaiono uno dopo l'altro, scendendo al loro posto. */
export const CEREMONY = { glide: 1.2, pieceGap: 0.38, pieceFade: 0.5, hold: 0.6 } as const;

function drawBuilding(ctx: CanvasRenderingContext2D, data: GardenData, camera: Camera, building: NonNullable<Effects["building"]>, tint: Tint, dpr: number): void {
  const tileW = worldView(camera).tileW;
  let index = 0;
  for (const bridge of BRIDGES) {
    if (!building.ids.includes(bridgeId(bridge))) continue;
    for (const piece of bridgePieces(bridge, data, camera)) {
      const appear = (building.elapsed - CEREMONY.glide - index * CEREMONY.pieceGap) / CEREMONY.pieceFade;
      index += 1;
      if (appear <= 0) continue;
      const shown = Math.min(appear, 1);
      const key = `giardino/ponte_${bridge.alongColumns ? "colonna" : "riga"}_${piece.variant}`;
      const s = ready(key);
      if (!s) continue;
      const sx = tileW / 122, sy = tileW / 150, width = s.src.w * sx, height = s.src.h * sy;
      const anchorX = (bridge.alongColumns ? 119.5 : s.width - 119.5) - s.src.x, anchorY = 127 - s.src.y;
      ctx.save();
      ctx.globalAlpha = shown;
      ctx.drawImage(scaled(s, key, width * dpr, height * dpr, tint), piece.x - anchorX * sx, piece.y - anchorY * sy - (1 - shown) * (1 - shown) * tileW * 0.5, width, height);
      ctx.restore();
    }
  }
}

function starPath(ctx: CanvasRenderingContext2D, x: number, y: number, outer: number, angle: number): void {
  ctx.beginPath();
  for (let point = 0; point < 10; point++) {
    const radius = point % 2 === 0 ? outer : outer * 0.45;
    const a = angle - Math.PI / 2 + point * Math.PI / 5;
    const px = x + Math.cos(a) * radius, py = y + Math.sin(a) * radius;
    if (point === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
  }
  ctx.closePath();
}

/** Le stelline che escono da un punto (uno sblocco, un regalo), a `progress` della festa. */
function drawBurst(ctx: CanvasRenderingContext2D, x: number, y: number, progress: number, tileW: number, envelope: number, reduceMotion: boolean): void {
  if (!reduceMotion && progress < 1) {
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    const pulse = Math.sin(progress * Math.PI);
    radial(ctx, x, y, tileW * 1.1, [rgba(255, 240, 170, 0.55 * pulse), rgba(255, 240, 170, 0)]);
    ctx.restore();
  }
  for (let index = 0; index < BURST_STAR_COUNT; index++) {
    const star = burstStar(index, progress);
    const alpha = star.alpha * (reduceMotion ? envelope : 1);
    if (alpha <= 0.01) continue;
    starPath(ctx, x + star.dx, y + star.dy, star.size, star.angle);
    ctx.fillStyle = index % 3 === 0 ? rgba(255, 240, 170, alpha) : rgba(255, 208, 70, alpha);
    ctx.fill();
    ctx.strokeStyle = rgba(226, 140, 28, alpha * 0.9);
    ctx.lineWidth = 0.9;
    ctx.stroke();
  }
}

export function drawGarden(ctx: CanvasRenderingContext2D, layers: SceneLayers, data: GardenData, camera: Camera, dpr: number, version: number,
  carrying: Carrying | null = null, effects: Effects = { building: null, bursts: [], reduceMotion: false }): void {
  const light = lightOf(data);
  const building = effects.building?.ids ?? [];
  const key = JSON.stringify([camera, data.season, data.islands.map((i) => [i.id, i.size, i.open]), data.bridges, Math.round(light.darkness * 40),
    tintOf(lightMultiplier(light)), dpr, version, carrying !== null, building]);
  if (layers.still === null || layers.stillKey !== key) {
    const still = layers.still ?? makeCanvas(SCENE_W * dpr, SCENE_H * dpr);
    still.width = Math.round(SCENE_W * dpr);
    still.height = Math.round(SCENE_H * dpr);
    const s = still.getContext("2d")!;
    s.setTransform(dpr, 0, 0, dpr, 0, 0);
    s.imageSmoothingQuality = "high";
    drawStaticScene(s, data, camera, light, dpr, version, carrying !== null, building);
    drawOverlay(s, data.season, light);
    layers.still = still;
    layers.stillKey = key;
  }
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.drawImage(layers.still!, 0, 0);
  ctx.restore();
  const tint = tintOf(lightMultiplier(light));
  if (effects.building) drawBuilding(ctx, data, camera, effects.building, tint, dpr);
  drawChimneySmoke(ctx, data, camera);
  const island = carrying ? data.islands.find((i) => i.id === carrying.island) : undefined;
  const iso = island ? isoOf(island, camera) : null;
  if (carrying && iso) drawHighlight(ctx, iso, carrying.tiles, carrying.valid);
  const laid = entities(data, camera, light, carrying?.skip ?? null);
  const tileWidth = worldView(camera).tileW;
  for (const e of laid) {
    drawEntity(ctx, e, data.season, tint, dpr, tileWidth);
    if (e.water) drawWater(ctx, e, light);
  }
  if (carrying?.ghost && iso) {
    const g = carrying.ghost;
    const made = makeEntity(g.key, g.height, g.feet, g.shadowWidth, g.turned, 0, iso);
    if (made) {
      ctx.save();
      ctx.globalAlpha = g.alpha;
      drawEntity(ctx, { ...made, rect: { ...made.rect, y: made.rect.y - 6 }, kind: "placed", alpha: 1, sway: 0, seed: 0, tile: { col: 0, row: 0 }, water: null,
        placement: null, item: null, island: carrying.island }, data.season, tint, dpr);
      ctx.restore();
    }
  }
  drawVisitorHint(ctx, laid);
  drawCornerEffects(ctx, laid, data, camera, light);
  drawInteractionEffects(ctx, laid, camera, light);
  drawWeather(ctx, data.season, light);
  drawLampGlows(ctx, laid, data, camera, light);
  drawCottageWindows(ctx, data, camera, light);
  drawLandmarkLights(ctx, data, camera, light);
  drawFireflies(ctx, data.season, light);
  const tileW = worldView(camera).tileW;
  for (const burst of effects.bursts) drawBurst(ctx, burst.x, burst.y, effects.reduceMotion ? 0.55 : burst.progress, tileW, Math.min(burst.progress * 8, (1 - burst.progress) * 3, 1), effects.reduceMotion);
}

/** Dove sta a schermo il disegno di una copia (per far uscire le stelline dal regalo), o il centro dell'isola se non c'è. */
export function placementCenter(data: GardenData, camera: Camera, island: string, placement: string | null | readonly string[], visitor = false): { x: number; y: number } | null {
  const laid = entities(data, camera, lightOf(data));
  const ids = placement === null ? [] : typeof placement === "string" ? [placement] : placement;
  const found = laid.filter((e) => (e.placement && ids.includes(e.placement.id)) || (visitor && e.kind === "visitor"));
  if (found.length > 0) {
    return { x: found.reduce((sum, e) => sum + e.rect.x + e.rect.w / 2, 0) / found.length, y: found.reduce((sum, e) => sum + e.rect.y + e.rect.h / 2, 0) / found.length };
  }
  const target = data.islands.find((i) => i.id === island);
  const iso = target && isoOf(target, camera);
  return iso ? iso.point(iso.size / 2, iso.size / 2) : null;
}

/** La vista che inquadra le isole dette. */
export function framingCamera(data: GardenData, ids: readonly string[]): Camera {
  const base = worldView({ zoom: 1, panX: 0, panY: 0 });
  let left = Infinity, right = -Infinity, top = Infinity, bottom = -Infinity;
  for (const id of ids) {
    const island = data.islands.find((i) => i.id === id), corner = islandCorner(id);
    if (!island || !corner) continue;
    for (const [dc, dr] of [[0, 0], [island.size, 0], [0, island.size], [island.size, island.size]] as const) {
      const col = corner.col + dc, row = corner.row + dr;
      const x = (col - row) * base.tileW / 2, y = (col + row) * base.tileW / 4;
      left = Math.min(left, x); right = Math.max(right, x); top = Math.min(top, y); bottom = Math.max(bottom, y);
    }
  }
  if (!(left < right)) {
    const shown = data.islands.find((i) => i.id === data.shown);
    return shown ? islandCamera(shown) : { zoom: 1, panX: 0, panY: 0 };
  }
  top -= base.tileW * 1.6;
  bottom += base.tileW * 0.6;
  const zoom = Math.min(Math.max(Math.min((SCENE_W - 90) / (right - left), (SCENE_H - 170) / (bottom - top)), ZOOM_MIN), ZOOM_MAX);
  const box = { x: base.ox + (left + right) / 2, y: base.oy + (top + bottom) / 2 };
  return { zoom, panX: SCENE_W / 2 - CENTER.x - (box.x - CENTER.x) * zoom, panY: SCENE_H / 2 + 14 - CENTER.y - (box.y - CENTER.y) * zoom };
}

/** Per i cartellini: il centro di ogni isola, il suo angolo davanti (sotto il bordo di terra) e quanto è larga una tessera. */
export function islandMarks(data: GardenData, camera: Camera): Array<{ island: GardenIslandData; center: { x: number; y: number }; front: { x: number; y: number }; tileW: number }> {
  return worldIslands(data, camera).map(({ island, iso }) => {
    const front = iso.point(iso.size, iso.size);
    return { island, center: iso.point(iso.size / 2, iso.size / 2), front: { x: front.x, y: front.y + iso.edge + 6 }, tileW: iso.tileW };
  });
}

// ---- per il mouse: cosa c'è sotto un punto, e dove ci sta una cosa

export type Hit = { kind: "placed"; id: string; island: string; feet: { x: number; y: number } }
  | { kind: "companion"; pet: string; island: string; feet: { x: number; y: number }; rect: { x: number; y: number; w: number; h: number } }
  | { kind: "visitor"; island: string };

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
    if (e.kind === "visitor") return { kind: "visitor", island: e.island };
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
