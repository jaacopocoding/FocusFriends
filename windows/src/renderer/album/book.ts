// Il disegno dell'album (AlbumView in AlbumWindow.swift): il prato dietro, la copertina in pelle con la targa, il libro aperto con i titoli, le sei
// figurine per pagina (le trovate incollate un po' storte), i numeri di pagina, il sigillo «completa» e i comandi sotto il libro. Le misure sono
// quelle della vista del Mac (980 × 730 punti). Qui c'è solo il disegno: le regole sono in `core/gardenCatalog.ts`.

import { albumSpreads, CATEGORY_TITLES, GARDEN_CATEGORIES, itemNumber, itemWithId } from "../../core/gardenCatalog.ts";
import type { AlbumPage, AlbumSpread, GardenItem } from "../../core/gardenCatalog.ts";
import { hash } from "../../core/gardenDrops.ts";
import { interactionImage, sceneId, sceneSpreads, scenesOf, GARDEN_INTERACTIONS } from "../../core/gardenInteractions.ts";
import type { GardenInteraction } from "../../core/gardenInteractions.ts";
import type { Season } from "../../core/gardenSky.ts";
import type { AlbumData } from "../../shared/albumApi.ts";
import { makeCanvas, picture, ready } from "../garden/sprites.ts";
import type { Sprite } from "../garden/sprites.ts";
import { drawSticker } from "../garden/sticker.ts";
import type { StickerLook } from "../garden/sticker.ts";

export const SIZE = { width: 980, height: 730 } as const;
export const SPREADS: readonly AlbumSpread[] = albumSpreads();
/** Dopo le figurine, la sezione «Scene»: le cose che i compagni usano nel giardino, un compagno per pagina (come in AlbumWindow.swift). */
export const SCENE_SPREADS = sceneSpreads();
export const SPREAD_COUNT = SPREADS.length + SCENE_SPREADS.length;
/** Se la doppia pagina `index` è una della sezione «Scene», quale. */
export const sceneSpreadAt = (index: number): { left: string; right: string | null } | null => (index >= SPREADS.length ? SCENE_SPREADS[index - SPREADS.length] ?? null : null);

/** Le linguette sotto il libro: le tre sezioni delle figurine e le scene. */
export type Tab = AlbumPage["category"] | "scenes";
export const TABS: readonly Tab[] = [...GARDEN_CATEGORIES, "scenes"];
export const tabTitle = (tab: Tab): string => (tab === "scenes" ? "Scene" : CATEGORY_TITLES[tab]);

export type Mode = "cover" | "opening" | "open";

export interface Rect { x: number; y: number; w: number; h: number }

const INK = "rgb(41, 26, 15)", INK_LIGHT = "rgb(102, 77, 51)";
const LEATHER_DARK = [74, 41, 20] as const;
const PAPER_LIGHT = "rgb(255, 249, 227)";
const UI = 'system-ui, "Segoe UI", sans-serif';
/** I titoli: Amatic SC (incluso nell'app, come sul Mac); i numeri di pagina col pennarello. */
const TITLE = '"Amatic SC Album", "Amatic SC", cursive';
const MARKER = '"Chewy", "Segoe Print", cursive';

const rgba = (c: readonly number[], a: number): string => `rgba(${c[0]}, ${c[1]}, ${c[2]}, ${a})`;

// ---- la geometria

/** Dove sta la copertina disegnata (la proporzione dell'immagine, alta 628). */
export function coverRect(): Rect {
  const image = picture("album/copertina");
  const h = 628, w = image ? h * image.width / image.height : 497;
  return { x: (SIZE.width - w) / 2, y: 28, w, h };
}

/** Dove sta il libro aperto disegnato (largo 920). */
export function spreadRect(): Rect {
  const image = picture("album/doppia_pagina");
  const w = 920, h = image ? w * image.height / image.width : 625;
  return { x: (SIZE.width - w) / 2, y: 40, w, h };
}

const onSpread = (u: number, v: number): { x: number; y: number } => { const r = spreadRect(); return { x: r.x + r.w * u, y: r.y + r.h * v }; };
const PAGE_CENTER_U = { left: 0.291, right: 0.707 }, BAND_CENTER_V = 0.18, PAGE_NUMBER_V = 0.838, SLOTS_TOP_V = 0.285;

export const closedShadow = (c: Rect): Rect => ({ x: c.x + 8 + 5, y: c.y + 6 + 9, w: c.w - 14, h: c.h * 0.95 - 8 });
export const openShadow = (s: Rect): Rect => ({ x: s.x + s.w * 0.03 + 4, y: s.y + s.h * 0.05 + 9, w: s.w * 0.94, h: s.h * 0.89 });

/** Le sei caselle di una pagina (3 colonne per 2 righe). */
export function slots(isLeft: boolean): Rect[] {
  const w = 98, h = 132, gapX = 9, gapY = 36;
  const center = onSpread(isLeft ? PAGE_CENTER_U.left : PAGE_CENTER_U.right, 0).x, top = onSpread(0, SLOTS_TOP_V).y;
  const originX = center - (w * 3 + gapX * 2) / 2;
  return Array.from({ length: 6 }, (_, i) => ({ x: originX + (i % 3) * (w + gapX), y: top + Math.floor(i / 3) * (h + gapY), w, h }));
}

export interface Controls { previous: Rect; next: Rect; tabs: Array<{ tab: Tab; rect: Rect }> }

const TAB_FONT = `600 12.5px ${UI}`;

export function controls(ctx: CanvasRenderingContext2D): Controls {
  const s = spreadRect();
  const y = s.y + s.h + 7;
  ctx.font = TAB_FONT;
  const widths = TABS.map((t) => Math.ceil(ctx.measureText(tabTitle(t)).width) + 26);
  let x = (SIZE.width - (widths.reduce((a, b) => a + b, 0) + (widths.length - 1) * 8)) / 2;
  const tabs = TABS.map((tab, i) => { const rect = { x, y, w: widths[i]!, h: 28 }; x += widths[i]! + 8; return { tab, rect }; });
  return { previous: { x: s.x, y: y - 2, w: 38, h: 32 }, next: { x: s.x + s.w - 38, y: y - 2, w: 38, h: 32 }, tabs };
}

/** Le quattro caselle delle scene di una pagina (2 per 2), dove ci sarebbero le sei figurine. */
export function sceneSlots(isLeft: boolean): Rect[] {
  const six = slots(isLeft);
  const x0 = Math.min(...six.map((r) => r.x)), y0 = Math.min(...six.map((r) => r.y));
  const x1 = Math.max(...six.map((r) => r.x + r.w)), y1 = Math.max(...six.map((r) => r.y + r.h));
  const gapX = 14, gapY = 18, w = (x1 - x0 - gapX) / 2, h = (y1 - y0 - gapY) / 2;
  return Array.from({ length: 4 }, (_, i) => ({ x: x0 + (i % 2) * (w + gapX), y: y0 + Math.floor(i / 2) * (h + gapY), w, h }));
}

export const inside = (r: Rect, x: number, y: number): boolean => x >= r.x && y >= r.y && x <= r.x + r.w && y <= r.y + r.h;

// ---- il testo, come NSString.draw(in:) del Mac: in alto nel rettangolo, troncato con «…»

function text(ctx: CanvasRenderingContext2D, value: string, r: Rect, font: string, color: string, align: CanvasTextAlign = "center"): void {
  ctx.font = font;
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.textBaseline = "alphabetic";
  const ascent = ctx.measureText("Hg").fontBoundingBoxAscent;
  let shown = value;
  while (shown.length > 1 && ctx.measureText(shown).width > r.w) shown = shown.slice(0, -2) + "…";
  ctx.fillText(shown, align === "center" ? r.x + r.w / 2 : align === "right" ? r.x + r.w : r.x, r.y + ascent);
}

function roundRect(ctx: CanvasRenderingContext2D, r: Rect, radius: number): void {
  ctx.beginPath();
  ctx.roundRect(r.x, r.y, r.w, r.h, radius);
}

// ---- il prato dietro il libro

const frozen = (season: Season): boolean => season === "winter" && picture("giardino/sfondo_inverno") !== null;

function drawBackdrop(ctx: CanvasRenderingContext2D, season: Season): void {
  ctx.fillStyle = "rgb(158, 191, 140)";
  ctx.fillRect(0, 0, SIZE.width, SIZE.height);
  const image = picture(frozen(season) ? "giardino/sfondo_inverno" : "giardino/sfondo");
  if (image) {
    // a misura della finestra, preso al 40 % da sinistra e appoggiato in basso
    const scale = Math.max(SIZE.width / image.width, SIZE.height / image.height);
    const w = image.width * scale, h = image.height * scale;
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(image, -(w - SIZE.width) * 0.40, SIZE.height - h, w, h);
  }
  ctx.fillStyle = frozen(season) ? "rgba(224, 237, 255, 0.20)" : "rgba(255, 245, 219, 0.16)";
  ctx.fillRect(0, 0, SIZE.width, SIZE.height);
  // i bordi scuriti: verdi sul prato, azzurri sul ghiaccio
  const edge = frozen(season) ? [36, 48, 71, 0.26] : [38, 51, 26, 0.30];
  const radius = Math.hypot(SIZE.width / 2, SIZE.height / 2);
  const gradient = ctx.createRadialGradient(SIZE.width / 2, SIZE.height / 2, 0, SIZE.width / 2, SIZE.height / 2, radius);
  gradient.addColorStop(0, rgba(edge, 0));
  gradient.addColorStop(1, rgba(edge, edge[3]!));
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, SIZE.width, SIZE.height);
}

// ---- la copertina e le pagine

export interface BookState {
  mode: Mode;
  spread: number;
  /** Quanto si vedono titoli, figurine e comandi (0 appena il libro si è aperto, poi sale a 1). */
  contentAlpha: number;
  /** Solo il libro (per le fotografie delle animazioni): niente prato, ombra, comandi, messaggi. */
  capturing: boolean;
  /** Con titoli e figurine, o solo il disegno. */
  content: boolean;
  message: string | null;
  /** Le figurine nuove, finché il libro resta aperto. */
  newOnes: ReadonlySet<string>;
}

function drawCover(ctx: CanvasRenderingContext2D, data: AlbumData, state: BookState): void {
  const image = picture("album/copertina");
  if (!image) return;
  const r = coverRect();
  if (!state.capturing) {
    ctx.fillStyle = "rgba(0, 0, 0, 0.32)";
    roundRect(ctx, closedShadow(r), 12);
    ctx.fill();
  }
  ctx.drawImage(image, r.x, r.y, r.w, r.h);
  // il titolo sulla targa e il conto sulla fascia di pergamena (nell'immagine sono vuote), come nella copertina disegnata da Gemini
  const plateX = r.x + r.w * 0.533, bandX = r.x + r.w * 0.551;
  const ink = [77, 46, 23] as const;
  text(ctx, "L'album", { x: plateX - 140, y: r.y + r.h * 0.19 - 18, w: 280, h: 80 }, `58px ${TITLE}`, rgba(ink, 1));
  text(ctx, data.owner === null ? "delle figurine" : `di ${data.owner}`, { x: plateX - 140, y: r.y + r.h * 0.285 - 4, w: 280, h: 42 }, `29px ${TITLE}`, rgba(ink, 0.8));
  text(ctx, `${data.has.length} su ${SPREADS.flatMap((s) => [...s.left.items, ...(s.right?.items ?? [])]).length} figurine`,
    { x: bandX - 150, y: r.y + r.h * 0.741 - 12, w: 300, h: 24 }, `600 17px ${UI}`, rgba(ink, 1));
  if (data.unseen.length > 0) {
    text(ctx, data.unseen.length === 1 ? "C'è una figurina nuova!" : `Ci sono ${data.unseen.length} figurine nuove!`,
      { x: bandX - 150, y: r.y + r.h * 0.8, w: 300, h: 22 }, `600 14px ${UI}`, "rgb(255, 237, 191)");
  }
  // sotto il libro, con due frecce a mano (non fa parte della copertina che si apre)
  if (!state.capturing) drawOpenHint(ctx, r.x + r.w * 0.52, r.y + r.h + 14, rgba(LEATHER_DARK, 1));
}

/** «Tocca per aprirlo», sotto il libro chiuso, con un ghirigoro a sinistra e una freccia che sale verso il libro a destra (AlbumView.drawOpenHint). */
function drawOpenHint(ctx: CanvasRenderingContext2D, cx: number, y: number, ink: string): void {
  const font = `500 15px ${UI}`;
  const label = "Tocca per aprirlo";
  ctx.font = font;
  const width = Math.ceil(ctx.measureText(label).width);
  text(ctx, label, { x: cx - width / 2 - 4, y, w: width + 8, h: 20 }, font, ink);
  const left = cx - width / 2 - 14, right = cx + width / 2 + 12, mid = y + 10;
  ctx.save();
  ctx.strokeStyle = ink;
  ctx.globalAlpha = 0.85;
  ctx.lineWidth = 1.4;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.beginPath();
  for (const dy of [-4, 4]) {
    ctx.moveTo(left - 26, mid + dy);
    ctx.bezierCurveTo(left - 18, mid + dy - 5, left - 8, mid + dy + 5, left, mid + dy);
  }
  ctx.moveTo(right, mid + 4);
  ctx.bezierCurveTo(right + 20, mid + 4, right + 32, mid - 6, right + 34, mid - 20);
  ctx.moveTo(right + 27, mid - 15);
  ctx.lineTo(right + 34, mid - 20);
  ctx.lineTo(right + 36, mid - 11);
  ctx.stroke();
  ctx.restore();
}

function placing(item: GardenItem, data: AlbumData): StickerLook["placing"] {
  if (item.island === null) return { everywhere: true };
  const owner = data.islands.find((i) => i.id === item.island);
  return { island: item.island, name: owner?.open ? owner.name : "???" };
}

function drawPage(ctx: CanvasRenderingContext2D, page: AlbumPage, isLeft: boolean, data: AlbumData, state: BookState): void {
  const first = itemNumber(page.items[0]?.id ?? "") ?? 0, last = itemNumber(page.items[page.items.length - 1]?.id ?? "") ?? 0;
  // nella fascia del titolo, che nell'immagine è vuota
  const cx = onSpread(isLeft ? PAGE_CENTER_U.left : PAGE_CENTER_U.right, 0).x, mid = onSpread(0, BAND_CENTER_V).y;
  text(ctx, CATEGORY_TITLES[page.category], { x: cx - 160, y: mid - (isLeft ? 36 : 31), w: 320, h: 48 }, `${isLeft ? 42 : 33}px ${TITLE}`, isLeft ? INK : INK_LIGHT);
  text(ctx, `n. ${first} – ${last}`, { x: cx - 100, y: mid + 11, w: 200, h: 16 }, `500 11.5px ${UI}`, INK_LIGHT);
  const has = new Set(data.has);
  page.items.forEach((item, i) => {
    const slot = slots(isLeft)[i]!;
    const look: StickerLook = { item, number: itemNumber(item.id) ?? 0, found: has.has(item.id), isNew: state.newOnes.has(item.id), placing: placing(item, data) };
    if (look.found) {
      // incollata un po' storta, sempre nello stesso modo
      const tilt = ((hash(item.id) % 9) - 4) * 0.45 * Math.PI / 180;
      ctx.save();
      ctx.translate(slot.x + slot.w / 2, slot.y + slot.h / 2);
      ctx.rotate(tilt);
      ctx.translate(-(slot.x + slot.w / 2), -(slot.y + slot.h / 2));
      ctx.fillStyle = "rgba(0, 0, 0, 0.18)";
      roundRect(ctx, { ...slot, x: slot.x + 1.5, y: slot.y + 2.5 }, 11);
      ctx.fill();
      drawSticker(ctx, look, slot.x, slot.y, slot.w, slot.h);
      ctx.restore();
    } else {
      drawSticker(ctx, look, slot.x, slot.y, slot.w, slot.h);
    }
  });
  // il numero di pagina, dentro la macchia in basso
  const number = state.spread * 2 + (isLeft ? 1 : 2);
  text(ctx, String(number), { x: cx - 30, y: onSpread(0, PAGE_NUMBER_V).y - 9, w: 60, h: 18 }, `15px ${MARKER}`, "rgba(102, 77, 51, 0.85)");
}

/** Una pagina della sezione «Scene»: il nome del compagno (o «???»), quante scene ha visto, e le sue quattro scene (come `drawScenePage` sul Mac). */
function drawScenePage(ctx: CanvasRenderingContext2D, pet: string, isLeft: boolean, data: AlbumData, state: BookState): void {
  const island = data.islands.find((i) => i.id === pet);
  const open = island?.open ?? false;
  const scenes = scenesOf(pet);
  const seen = scenes.filter((scene) => data.scenes.includes(sceneId(scene))).length;
  const cx = onSpread(isLeft ? PAGE_CENTER_U.left : PAGE_CENTER_U.right, 0).x, mid = onSpread(0, BAND_CENTER_V).y;
  text(ctx, open ? island!.name : "???", { x: cx - 160, y: mid - (isLeft ? 36 : 31), w: 320, h: 48 }, `${isLeft ? 42 : 33}px ${TITLE}`, isLeft ? INK : INK_LIGHT);
  text(ctx, `${seen} su ${scenes.length} scene`, { x: cx - 100, y: mid + 11, w: 200, h: 16 }, `500 11.5px ${UI}`, INK_LIGHT);
  scenes.forEach((scene, i) => drawSceneCard(ctx, scene, sceneSlots(isLeft)[i]!, data.scenes.includes(sceneId(scene)), open));
  const number = state.spread * 2 + (isLeft ? 1 : 2);
  text(ctx, String(number), { x: cx - 30, y: onSpread(0, PAGE_NUMBER_V).y - 9, w: 60, h: 18 }, `15px ${MARKER}`, "rgba(102, 77, 51, 0.85)");
}

const sceneSilhouettes = new Map<string, HTMLCanvasElement>();

/** La sagoma di una scena: dove è disegnata, tutta di un colore (si riconosce la forma, non chi c'è dentro). */
function sceneSilhouette(s: Sprite, key: string): HTMLCanvasElement {
  const known = sceneSilhouettes.get(key);
  if (known) return known;
  const made = makeCanvas(s.src.w, s.src.h);
  const c = made.getContext("2d")!;
  c.drawImage(s.image, s.src.x, s.src.y, s.src.w, s.src.h, 0, 0, s.src.w, s.src.h);
  c.globalCompositeOperation = "source-in";
  c.fillStyle = "rgba(140, 102, 64, 0.45)";
  c.fillRect(0, 0, made.width, made.height);
  sceneSilhouettes.set(key, made);
  return made;
}

/** Una scena: vista, una fotografia incollata un po' storta con la didascalia; da vedere, la sua sagoma e cosa serve. */
function drawSceneCard(ctx: CanvasRenderingContext2D, scene: GardenInteraction, slot: Rect, seen: boolean, petOpen: boolean): void {
  ctx.save();
  const inset = { x: slot.x + 0.75, y: slot.y + 0.75, w: slot.w - 1.5, h: slot.h - 1.5 };
  if (seen) {
    const tilt = ((hash(sceneId(scene)) % 9) - 4) * 0.5 * Math.PI / 180;
    ctx.translate(slot.x + slot.w / 2, slot.y + slot.h / 2);
    ctx.rotate(tilt);
    ctx.translate(-(slot.x + slot.w / 2), -(slot.y + slot.h / 2));
    ctx.fillStyle = "rgba(0, 0, 0, 0.18)";
    roundRect(ctx, { ...slot, x: slot.x + 1.5, y: slot.y + 2.5 }, 10);
    ctx.fill();
    roundRect(ctx, inset, 10);
    ctx.fillStyle = "rgb(255, 252, 240)";
    ctx.fill();
    ctx.strokeStyle = "rgba(140, 102, 64, 0.45)";
    ctx.lineWidth = 1.2;
    ctx.stroke();
  } else {
    roundRect(ctx, inset, 10);
    ctx.fillStyle = "rgba(140, 102, 64, 0.13)";
    ctx.fill();
    ctx.setLineDash([4, 3]);
    ctx.strokeStyle = "rgba(140, 102, 64, 0.32)";
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.setLineDash([]);
  }
  const box = { x: slot.x + 8, y: slot.y + 8, w: slot.w - 16, h: slot.h - 8 - 26 };
  const s = ready(interactionImage(scene));
  if (s) {
    const k = Math.min(box.w / Math.max(s.src.w, 1), box.h / Math.max(s.src.h, 1));
    const w = s.src.w * k, h = s.src.h * k, x = box.x + (box.w - w) / 2, y = box.y + (box.h - h) / 2;
    ctx.imageSmoothingQuality = "high";
    if (seen) {
      ctx.drawImage(s.image, s.src.x, s.src.y, s.src.w, s.src.h, x, y, w, h);
    } else {
      ctx.globalAlpha *= 0.45;
      ctx.drawImage(sceneSilhouette(s, sceneId(scene)), x, y, w, h);
      ctx.globalAlpha /= 0.45;
    }
  }
  const caption = { x: slot.x + 6, y: slot.y + slot.h - 23, w: slot.w - 12, h: 16 };
  if (seen) text(ctx, scene.caption, caption, `600 11.5px ${UI}`, INK);
  else text(ctx, petOpen ? `??? · ${itemWithId(scene.item)?.name ?? scene.item}` : "???", caption, `600 11px ${UI}`, INK_LIGHT);
  ctx.restore();
}

/** Il sigillo d'oro quando la doppia pagina è completa. */
function drawSeal(ctx: CanvasRenderingContext2D, spread: AlbumSpread, data: AlbumData): void {
  const items = [...spread.left.items, ...(spread.right?.items ?? [])];
  const has = new Set(data.has);
  if (items.length === 0 || !items.every((x) => has.has(x.id))) return;
  drawSealMark(ctx);
}

/** Il sigillo d'oro «completa», al centro in alto. */
function drawSealMark(ctx: CanvasRenderingContext2D): void {
  const c = onSpread(0.498, 0.185);
  ctx.fillStyle = "rgba(0, 0, 0, 0.25)";
  ctx.beginPath();
  ctx.ellipse(c.x, c.y + 2, 30, 30, 0, 0, Math.PI * 2);
  ctx.fill();
  const gradient = ctx.createLinearGradient(c.x - 15, c.y + 26, c.x + 15, c.y - 26);
  gradient.addColorStop(0, "rgb(247, 212, 107)");
  gradient.addColorStop(1, "rgb(199, 148, 41)");
  ctx.beginPath();
  ctx.ellipse(c.x, c.y - 1, 29, 29, 0, 0, Math.PI * 2);
  ctx.fillStyle = gradient;
  ctx.fill();
  ctx.strokeStyle = rgba(LEATHER_DARK, 0.6);
  ctx.lineWidth = 1.2;
  ctx.stroke();
  ctx.beginPath();
  for (let i = 0; i < 10; i++) {
    const angle = i * Math.PI / 5 - Math.PI / 2, r = i % 2 === 0 ? 15 : 7;
    const x = c.x + Math.cos(angle) * r, y = c.y - 1 + Math.sin(angle) * r;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.fillStyle = rgba(LEATHER_DARK, 0.75);
  ctx.fill();
  text(ctx, "completa", { x: c.x - 40, y: c.y + 32, w: 80, h: 14 }, `bold 10.5px ${UI}`, INK);
}

function drawControls(ctx: CanvasRenderingContext2D, data: AlbumData, state: BookState): void {
  const c = controls(ctx);
  const ink = (a: number): string => rgba(LEATHER_DARK, a);
  for (const [pointsLeft, r, enabled] of [[true, c.previous, state.spread > 0], [false, c.next, state.spread < SPREAD_COUNT - 1]] as const) {
    ctx.fillStyle = ink(enabled ? 0.18 : 0.06);
    roundRect(ctx, r, 10);
    ctx.fill();
    const cx = r.x + r.w / 2, cy = r.y + r.h / 2, d = pointsLeft ? -1 : 1;
    ctx.beginPath();
    ctx.moveTo(cx - d * 4, cy - 8);
    ctx.lineTo(cx + d * 4, cy);
    ctx.lineTo(cx - d * 4, cy + 8);
    ctx.strokeStyle = ink(enabled ? 1 : 0.35);
    ctx.lineWidth = 2.4;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.stroke();
  }
  const current: Tab = sceneSpreadAt(state.spread) ? "scenes" : SPREADS[state.spread]!.left.category;
  for (const tab of c.tabs) {
    const selected = tab.tab === current;
    roundRect(ctx, tab.rect, 14);
    if (selected) { ctx.fillStyle = ink(1); ctx.fill(); }
    else { ctx.strokeStyle = ink(0.55); ctx.lineWidth = 1.2; ctx.stroke(); }
    text(ctx, tabTitle(tab.tab), { x: tab.rect.x, y: tab.rect.y + 6, w: tab.rect.w, h: 16 }, TAB_FONT, selected ? PAPER_LIGHT : ink(0.85));
  }
  const total = SPREADS.flatMap((s) => [...s.left.items, ...(s.right?.items ?? [])]).length;
  const counter = sceneSpreadAt(state.spread) ? `${data.scenes.length} su ${GARDEN_INTERACTIONS.length} scene` : `${data.has.length} su ${total}`;
  text(ctx, counter, { x: c.previous.x + c.previous.w + 10, y: c.previous.y + 8, w: 140, h: 16 }, `500 12.5px ${UI}`, ink(0.8), "left");
}

function drawSpread(ctx: CanvasRenderingContext2D, data: AlbumData, state: BookState): void {
  const image = picture("album/doppia_pagina");
  const r = spreadRect();
  if (image) {
    if (!state.capturing) {
      ctx.fillStyle = "rgba(0, 0, 0, 0.30)";
      roundRect(ctx, openShadow(r), 14);
      ctx.fill();
    }
    ctx.drawImage(image, r.x, r.y, r.w, r.h);
  }
  if (!state.content) return;
  ctx.save();
  ctx.globalAlpha = state.contentAlpha;
  const pets = sceneSpreadAt(state.spread);
  if (pets) {
    drawScenePage(ctx, pets.left, true, data, state);
    if (pets.right) drawScenePage(ctx, pets.right, false, data, state);
    const all = [...scenesOf(pets.left), ...(pets.right ? scenesOf(pets.right) : [])];
    if (all.length > 0 && all.every((scene) => data.scenes.includes(sceneId(scene)))) drawSealMark(ctx);
  } else {
    const current = SPREADS[state.spread]!;
    drawPage(ctx, current.left, true, data, state);
    if (current.right) drawPage(ctx, current.right, false, data, state);
    drawSeal(ctx, current, data);
  }
  if (!state.capturing) drawControls(ctx, data, state);
  ctx.restore();
  if (state.message !== null && !state.capturing) {
    text(ctx, state.message, { x: 60, y: SIZE.height - 24, w: SIZE.width - 120, h: 18 }, `500 13px ${UI}`, rgba(LEATHER_DARK, 1));
  }
}

export function drawBook(ctx: CanvasRenderingContext2D, data: AlbumData, state: BookState): void {
  if (!state.capturing) drawBackdrop(ctx, data.season);
  if (state.mode === "cover") drawCover(ctx, data, state);
  else if (state.mode === "open") drawSpread(ctx, data, state);
}

/** Le immagini che servono: il libro, il prato e le figurine. */
export function wantedImages(): string[] {
  return ["album/copertina", "album/doppia_pagina", "giardino/sfondo", "giardino/sfondo_inverno",
    ...SPREADS.flatMap((s) => [...s.left.items, ...(s.right?.items ?? [])]).map((x) => "giardino/" + x.id), ...GARDEN_INTERACTIONS.map(interactionImage)];
}
