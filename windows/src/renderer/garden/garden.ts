// La pagina del giardino: riceve la fotografia del giardino dal processo principale e la disegna (scene.ts) su un <canvas> grande quanto la
// finestra, con le misure della scena del Mac (1000 × 600). Sopra, in HTML, i comandi (come in GardenView): «‹ Menu», il nome dell'isola, le
// figurine, lo zoom, la cassetta «Da mettere». Dalla cassetta si trascinano le cose sull'isola (le tessere si fanno verdi o rosse), si spostano,
// si girano (R, due tocchi o il tasto destro) e, trascinandole in basso a sinistra, si tolgono. Ci si sposta trascinando lo sfondo; la rotellina
// del mouse ingrandisce, due dita sul touchpad spostano e il pizzico ingrandisce; «+», «−», «0» e «M» come sul Mac.

import { companionHeight, GARDEN_ITEMS, gardenImage, itemWithId, joinedImage, rarityOf, wrongIslandLine } from "../../core/gardenCatalog.ts";
import type { GardenItem } from "../../core/gardenCatalog.ts";
import { applyTurn } from "../../core/gardenCatalog.ts";
import { linkArms, tileKey } from "../../core/gardenGrid.ts";
import type { GardenTile } from "../../core/gardenGrid.ts";
import { petInfo } from "../../core/pets.ts";
import type { GardenApi, GardenArrival, GardenData, GardenIslandData } from "../../shared/gardenApi.ts";
import { h, icon } from "../card/dom.ts";
import {
  canPlaceOn, canStandOn, CEREMONY, clampCamera, drawGarden, FEET_OFFSET, life, feetOf, focusedIsland, framingCamera, hitAt, islandAt, islandCamera, islandMarks, isoOf,
  pieceCount, placementCenter, SCENE_H, SCENE_W, wantedImages, worldCamera, zoomCamera, ZOOM_MAX, ZOOM_MIN,
} from "./scene.ts";
import type { Camera, Carrying, Effects, SceneLayers } from "./scene.ts";
import { sprite, whenSpritesLoad } from "./sprites.ts";
import { advanceLife, greetVisitor, placeCompanion, resetVisitors, setSceneNotifier, showInteraction } from "./life.ts";
import { cornerWithId, formedCorners } from "../../core/gardenCorners.ts";
import { reasonText } from "../../core/gardenVisitors.ts";

declare global {
  interface Window {
    focusfriendsGarden: GardenApi;
    /** Per le prove dal vivo: lo stato e la telecamera. */
    __garden?: unknown;
  }
}

const api = window.focusfriendsGarden;
const canvas = document.getElementById("scene") as HTMLCanvasElement;
const ctx = canvas.getContext("2d")!;
const hud = document.getElementById("hud") as HTMLDivElement;
const labels = document.getElementById("labels") as HTMLDivElement;
const effectsLayer = document.getElementById("effects") as HTMLDivElement;

let data: GardenData | null = null;
let camera: Camera = { zoom: 1, panX: 0, panY: 0 };
let version = 0;
let frames = 0;
let scheduled = false;
const layers: SceneLayers = { still: null, stillKey: "" };

/** Quanti punti dello schermo per un punto della scena, e quanti pixel veri. */
const sceneScale = (): number => canvas.clientWidth / SCENE_W;
const pixelRatio = (): number => sceneScale() * window.devicePixelRatio;
const shownIsland = (): GardenIslandData | undefined => data?.islands.find((island) => island.id === data!.shown);

// ---- quello che si trascina

type CarryKind = { kind: "placed"; id: string } | { kind: "companion"; pet: string } | { kind: "fresh"; item: string };
interface Carry {
  what: CarryKind;
  /** Dove sono i piedi adesso, e la distanza fra i piedi e il punto preso. */
  feet: { x: number; y: number };
  grab: { x: number; y: number };
  start: { x: number; y: number };
  pointer: { x: number; y: number };
  moved: boolean;
  turned: boolean;
}
let carry: Carry | null = null;
let panning: { x: number; y: number } | null = null;
/** Come stava girata l'ultima cosa che si ripete (la staccionata): la prossima parte così. */
let repeatTurned = false;
let trayOpen = false;

// La prima volta nel giardino, accanto alla pillola, come si mettono le cose; sparisce per sempre appena si apre la cassetta (come sul Mac).
const TRAY_HINT = "Trascina le cose da «Da mettere» sull'isola.";
const TRAY_HINT_KEY = "gardenTrayHintSeen";
function trayHintSeen(): boolean {
  try { return localStorage.getItem(TRAY_HINT_KEY) === "1"; } catch { return true; }
}
function markTrayHintSeen(): void {
  try { localStorage.setItem(TRAY_HINT_KEY, "1"); } catch { /* senza memoria il suggerimento torna: va bene */ }
}
let message: string | null = null;
let messageTimer = 0;
let bubble: { pet: string; text: string } | null = null;
let bubbleTimer = 0;

// ---- l'arrivo di un compagno e le feste (le stelline con la scritta in alto)

/** «Riduci movimento» del sistema: niente telecamera che scivola né stelline che volano. */
const reduceMotion = (): boolean => window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const seconds = (): number => performance.now() / 1000;
interface Ceremony { arrival: GardenArrival; from: Camera; to: Camera; start: number; pieces: number; gliding: boolean }
let ceremony: Ceremony | null = null;
interface Celebration { caption: string; title: string; island: string; placement: string | string[] | null; visitor?: boolean; start: number | null }
const celebrations: Celebration[] = [];
const CELEBRATION_LENGTH = 4.6, BURST_LENGTH = 2.8;
let receivedAt = 0;

const carryItem = (c: Carry): GardenItem | undefined => {
  if (c.what.kind === "fresh") return itemWithId(c.what.item);
  if (c.what.kind === "placed") {
    const id = c.what.id;
    return itemWithId(data?.islands.flatMap((i) => i.placements).find((p) => p.id === id)?.item ?? "");
  }
  return undefined;
};

/** Le tessere con una cosa che si unisce alle uguali (la staccionata), senza quella che si sta spostando. */
function linkedOn(island: GardenIslandData, item: string, skip: string | null): Set<string> {
  return new Set(island.placements.filter((p) => p.item === item && p.id !== skip).map((p) => tileKey(p)));
}

/** Dove cadrebbe quello che si trascina (l'angolo in fondo e le tessere), e se ci sta. */
function carryTarget(c: Carry): { origin: GardenTile; tiles: GardenTile[]; valid: boolean } | null {
  const island = shownIsland();
  const iso = island && isoOf(island, camera);
  if (!island || !iso || !c.moved) return null;
  const g = iso.grid(c.feet.x, c.feet.y - iso.tileH * FEET_OFFSET);
  if (c.what.kind === "companion") {
    const t = { col: Math.floor(g.col), row: Math.floor(g.row) };
    return { origin: t, tiles: [t], valid: canStandOn(island, t) };
  }
  const item = carryItem(c);
  if (!item) return null;
  const footprint = applyTurn(item.footprint, c.turned);
  const origin = { col: Math.round(g.col - footprint.cols / 2), row: Math.round(g.row - footprint.rows / 2) };
  const tiles: GardenTile[] = [];
  for (let dc = 0; dc < footprint.cols; dc++) for (let dr = 0; dr < footprint.rows; dr++) tiles.push({ col: origin.col + dc, row: origin.row + dr });
  return { origin, tiles, valid: canPlaceOn(island, item.id, origin, c.turned, c.what.kind === "placed" ? c.what.id : null) };
}

function carrying(): Carrying | null {
  const island = shownIsland();
  const iso = island && isoOf(island, camera);
  if (!carry || !carry.moved || !island || !iso) return null;
  const target = carryTarget(carry);
  const skip = carry.what.kind === "placed" ? carry.what.id : carry.what.kind === "companion" ? `compagno:${carry.what.pet}` : null;
  let ghost: Carrying["ghost"] = null;
  if (carry.what.kind === "companion") {
    const pet = petInfo(carry.what.pet);
    const feet = target?.valid ? (() => { const c = iso.center(target.origin); return { x: c.x, y: c.y + iso.tileH * FEET_OFFSET }; })() : carry.feet;
    ghost = { key: pet.iconImage.replace(/\.png$/, ""), height: companionHeight(pet.id), feet, shadowWidth: iso.tileW * 0.5, turned: false, alpha: target?.valid ? 0.95 : 0.6 };
  } else {
    const item = carryItem(carry);
    if (item) {
      const footprint = applyTurn(item.footprint, carry.turned);
      let key = "giardino/" + gardenImage(item), turned = carry.turned;
      // una staccionata che si sta mettendo si vede già unita ai vicini della tessera dove cadrebbe
      if (item.joins) {
        const at = target?.valid ? target.origin : { col: -9, row: -9 };
        key = "giardino/" + joinedImage(item, linkArms(at, linkedOn(island, item.id, skip), carry.turned));
        turned = false;
      }
      void sprite(key);
      ghost = {
        key, height: item.height, feet: target?.valid ? feetOf(iso, item, target.origin, carry.turned) : carry.feet, turned,
        shadowWidth: item.castsShadow ? Math.min(iso.tileW * 0.62 * Math.max(footprint.cols, footprint.rows), iso.tileW * 1.3) : null,
        alpha: target?.valid ? 0.95 : 0.6,
      };
    }
  }
  return { skip, tiles: target?.tiles ?? [], valid: target?.valid ?? false, island: island.id, ghost };
}

// ---- il disegno

function resize(): void {
  const width = Math.round(window.innerWidth * window.devicePixelRatio), height = Math.round(window.innerHeight * window.devicePixelRatio);
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
    layers.still = null;
  }
  for (const layer of [hud, labels, effectsLayer]) layer.style.transform = `scale(${window.innerWidth / SCENE_W})`;
  redraw();
}

function redraw(): void {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    if (!data) return;
    const dpr = pixelRatio();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.imageSmoothingQuality = "high";
    drawGarden(ctx, layers, data, camera, dpr, version, carrying(), effects());
    renderHud();
    renderEffects();
    frames += 1;
  });
}

whenSpritesLoad(() => {
  version += 1;
  redraw();
});

function flash(text: string, seconds = 4): void {
  message = text;
  window.clearTimeout(messageTimer);
  messageTimer = window.setTimeout(() => { message = null; redraw(); }, seconds * 1000);
  redraw();
}

function resetCamera(): void {
  const shown = shownIsland();
  if (shown) camera = islandCamera(shown);
  redraw();
}

function isFitted(): boolean {
  const shown = shownIsland();
  if (!shown) return true;
  const fitted = islandCamera(shown);
  return Math.abs(camera.zoom - fitted.zoom) < 0.002 && Math.abs(camera.panX - fitted.panX) < 0.5 && Math.abs(camera.panY - fitted.panY) < 0.5;
}

/** Porta in primo piano un'isola aperta: da ora è lei quella viva. */
function focus(id: string): void {
  if (!data || id === data.shown || !data.islands.find((i) => i.id === id)?.open) return;
  data = { ...data, shown: id };
  bubble = null;
  // l'ospite se ne va; i compagni dell'altra isola restano dove sono
  resetVisitors();
  api.showIsland(id);
}

function moveCamera(next: Camera): void {
  // se chi guarda sposta la vista, la telecamera della cerimonia smette di scivolare
  if (ceremony) ceremony.gliding = false;
  camera = clampCamera(next);
  if (data && carry === null) focus(focusedIsland(data, camera));
  redraw();
}

function toggleWorldView(): void {
  carry = null;
  const all = worldCamera();
  const close = Math.abs(camera.zoom - all.zoom) < 0.02 && Math.abs(camera.panX - all.panX) < 3 && Math.abs(camera.panY - all.panY) < 3;
  if (close) resetCamera(); else moveCamera(all);
}

function receive(next: GardenData): void {
  const first = data === null;
  // l'isola viva la decide la pagina finché è aperta (il processo principale la segue)
  data = first || next.reset ? next : { ...next, shown: data!.shown };
  document.title = next.title;
  for (const key of wantedImages(next)) void sprite(key);
  for (const id of next.has) void sprite("giardino/" + id);
  receivedAt = performance.now();
  // gli angoli appena sbloccati: le stelline escono dalle loro cose, e in alto «Hai sbloccato…»
  for (const id of next.newCorners) {
    const corner = cornerWithId(id);
    const island = next.islands.find((i) => formedCorners(i.placements).has(id));
    if (corner && island) celebrations.push({ caption: "Hai sbloccato", title: corner.name, island: island.id, placement: formedCorners(island.placements).get(id) ?? null, start: null });
  }
  if (first || next.reset) {
    trayOpen = false;
    ceremony = null;
    resetVisitors();
    resetCamera();
    if (next.arrival) beginArrival(next.arrival);
  } else redraw();
}

const islandName = (id: string): string => data?.islands.find((i) => i.id === id)?.name ?? id;

/** La prima entrata dopo uno sblocco: la telecamera inquadra le isole, i pezzi dei ponti compaiono uno dopo l'altro, poi si salva tutto e arriva il regalo. */
function beginArrival(arrival: GardenArrival): void {
  if (!data) return;
  const involved = [...new Set([...arrival.bridges.flatMap((id) => id.split("-")), ...arrival.welcomed])];
  const single = involved.length === 1 ? data.islands.find((i) => i.id === involved[0]) : undefined;
  const to = single ? islandCamera(single) : framingCamera(data, involved);
  if (reduceMotion()) {
    camera = clampCamera(to);
    void finishArrival(arrival);
    return;
  }
  ceremony = { arrival, from: camera, to, start: seconds(), pieces: pieceCount(data, arrival.bridges), gliding: true };
  animate();
}

async function finishArrival(arrival: GardenArrival): Promise<void> {
  ceremony = null;
  const welcomes = await api.finishArrival(arrival);
  const first = arrival.welcomed[0];
  if (first) focus(first);
  for (const welcome of welcomes) {
    // con un ponte che arriva a quell'isola è «Nuovo ponte», senza è «Nuova isola»
    const kind = arrival.bridges.some((id) => id.split("-").includes(welcome.island)) ? "Nuovo ponte" : "Nuova isola";
    celebrations.push({ caption: `${kind}: un regalo per ${islandName(welcome.island)}`, title: itemWithId(welcome.item)?.name ?? welcome.item,
      island: welcome.island, placement: welcome.placement, start: null });
  }
  if (welcomes.length === 0 && arrival.bridges[0]) {
    const [a, b] = arrival.bridges[0].split("-");
    celebrations.push({ caption: "Nuovo ponte", title: `${islandName(a!)} e ${islandName(b!)}`, island: a!, placement: null, start: null });
  }
  animate();
}

/** L'ora che si vede adesso: quella ricevuta, che avanza con l'orologio (se non è forzata per provarla). */
function currentHour(): number {
  if (!data) return 12;
  return data.hourForced ? data.hour : (data.hour + (performance.now() - receivedAt) / 3_600_000) % 24;
}

/** Il ciclo della vita: a ogni fotogramma la cerimonia, le feste, i compagni e l'ospite. Si ridisegna a 30 al secondo se qualcosa cammina (o c'è una
 *  festa), a 15 se si muove solo l'aria (il vento, il fumo, la neve), e con «Riduci movimento» solo quando qualcosa cambia. Il ritmo si conta in tempo, non
 *  in fotogrammi dello schermo: a 120 o 144 Hz non si disegna più spesso che a 60 (con 4 ms di tolleranza, così a 60 Hz cade sempre sullo stesso fotogramma). */
let lastTick = 0, lastDraw = 0, lastMinute = -1;
const DRAW_SLACK = 0.004;
function tick(): void {
  requestAnimationFrame(tick);
  const now = seconds();
  const dt = Math.min(lastTick === 0 ? 0 : now - lastTick, 0.2);
  lastTick = now;
  if (!data || document.hidden) return;
  life.time = now;
  life.reduceMotion = reduceMotion();
  let busy = false;
  if (ceremony) {
    busy = true;
    const elapsed = now - ceremony.start;
    if (ceremony.gliding) {
      const t = Math.min(Math.max(elapsed / CEREMONY.glide, 0), 1);
      const eased = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      const { from, to } = ceremony;
      camera = clampCamera({ zoom: from.zoom + (to.zoom - from.zoom) * eased, panX: from.panX + (to.panX - from.panX) * eased, panY: from.panY + (to.panY - from.panY) * eased });
      if (t >= 1) ceremony.gliding = false;
    }
    if (elapsed >= CEREMONY.glide + Math.max(ceremony.pieces - 1, 0) * CEREMONY.pieceGap + CEREMONY.pieceFade + CEREMONY.hold) void finishArrival(ceremony.arrival);
  }
  const current = celebrations[0];
  if (current) {
    busy = true;
    current.start ??= now;
    if (now - current.start >= CELEBRATION_LENGTH) celebrations.shift();
  }
  const carried = carry?.moved && carry.what.kind === "companion" ? carry.what.pet : null;
  if (advanceLife(data, dt, currentHour(), carried)) busy = true;
  // la luce cambia piano (sta calando la sera): una volta al minuto si aggiorna l'ora
  const minute = Math.floor(currentHour() * 60);
  const lightChanged = minute !== lastMinute;
  if (lightChanged) {
    lastMinute = minute;
    if (!data.hourForced) { data = { ...data, hour: currentHour() }; receivedAt = performance.now(); }
  }
  const interval = busy ? 1 / 30 : life.reduceMotion ? Infinity : 1 / 15;
  if (lightChanged || now - lastDraw >= interval - DRAW_SLACK) {
    lastDraw = now;
    redraw();
  }
}

/** Le feste e la cerimonia hanno il loro ritmo nel ciclo della vita: qui basta ridisegnare. */
function animate(): void {
  redraw();
}

function effects(): Effects {
  const result: Effects = { building: null, bursts: [], reduceMotion: reduceMotion() };
  if (ceremony) result.building = { ids: ceremony.arrival.bridges, elapsed: seconds() - ceremony.start };
  const current = celebrations[0];
  if (current && current.start !== null && data) {
    const middle = placementCenter(data, camera, current.island, current.placement, current.visitor === true);
    if (middle) result.bursts.push({ ...middle, progress: Math.min((seconds() - current.start) / BURST_LENGTH, 1) });
  }
  return result;
}

/** La scritta della festa, in alto fra «Menu» e le pastiglie; i cartellini delle isole (i nomi rimpicciolendo, e i lucchetti di quelle chiuse). */
function renderEffects(): void {
  const children: HTMLElement[] = [];
  const current = celebrations[0];
  if (current && current.start !== null) {
    const elapsed = seconds() - current.start;
    const enter = Math.min(Math.max(elapsed / 0.35, 0), 1), leave = Math.min(Math.max((CELEBRATION_LENGTH - elapsed) / 0.6, 0), 1);
    const top = document.querySelector(".top-right") as HTMLElement | null;
    const freeRight = (top ? top.offsetLeft : SCENE_W - 16) - 12;
    const chip = h("div", { class: "celebration" }, icon("star", 17),
      h("div", { class: "celebration-text" }, h("span", { class: "caption" }, current.caption), h("span", { class: "title" }, current.title)));
    chip.style.opacity = String(Math.min(enter, leave));
    chip.style.left = `${(150 + freeRight) / 2}px`;
    chip.style.top = `${10 - (1 - enter) * 14}px`;
    children.push(chip);
  }
  effectsLayer.replaceChildren(...children);

  const marks: HTMLElement[] = [];
  if (data) {
    const showNames = camera.zoom < 0.8;
    for (const mark of islandMarks(data, camera)) {
      const { island } = mark;
      if (mark.center.x < -200 || mark.center.y < -200 || mark.center.x > SCENE_W + 200 || mark.center.y > SCENE_H + 200) continue;
      if (!island.open) {
        const size = Math.min(Math.max(mark.tileW * 0.55, 16), 34);
        const lock = h("div", { class: "lock" }, icon("lock", Math.round(size)));
        lock.style.left = `${mark.center.x - size / 2}px`;
        lock.style.top = `${mark.center.y - size / 2}px`;
        marks.push(lock);
      }
      if (!(showNames || !island.open) || !(island.open || mark.tileW > 18)) continue;
      const label = h("div", { class: `island-label${island.open ? "" : " closed"}${island.id === data.shown ? " shown" : ""}` },
        h("span", { class: "name" }, island.open ? island.name : "???"),
        island.open ? null : h("span", { class: "subtitle" }, `si sblocca a ${island.need} focus`));
      label.style.left = `${mark.front.x}px`;
      label.style.top = `${mark.front.y}px`;
      marks.push(label);
    }
  }
  labels.replaceChildren(...marks);
}

// ---- i comandi in HTML (in unità della scena: il contenitore si scala con la finestra)

const trayItems = (): GardenItem[] => {
  const island = shownIsland();
  if (!data || !island) return [];
  const has = new Set(data.has);
  return GARDEN_ITEMS.filter((x) => (x.island === null || x.island === island.id) && has.has(x.id));
};
const trayVisible = (): boolean => trayOpen && trayItems().length > 0;
const isCarryingPlaced = (): boolean => carry?.moved === true && carry.what.kind === "placed";
const REMOVE_ZONE = { x: 16, y: SCENE_H - 64, w: 236, h: 46 };
const inRemoveZone = (p: { x: number; y: number }): boolean => p.x >= REMOVE_ZONE.x && p.x <= REMOVE_ZONE.x + REMOVE_ZONE.w && p.y >= REMOVE_ZONE.y && p.y <= REMOVE_ZONE.y + REMOVE_ZONE.h;

/** Gli stili si danno con il CSSOM: il CSP della pagina non permette gli attributi `style`. */
function styled<T extends HTMLElement>(element: T, styles: Partial<Record<"width" | "bottom" | "left", string>>): T {
  Object.assign(element.style, styles);
  return element;
}

function chip(className: string, title: string, ...children: Array<Node | string>): HTMLElement {
  return h("div", { class: `chip ${className}`, title }, ...children);
}

let trayKey = "";
const trayElement = h("div", { class: "tray" });
const trayCells = h("div", { class: "tray-cells" });
trayCells.addEventListener("wheel", (event) => {
  event.preventDefault();
  event.stopPropagation();
  trayCells.scrollLeft += Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
}, { passive: false });
trayElement.append(h("div", { class: "tray-title" }, "Da mettere"), h("div", { class: "tray-subtitle" }, "trascina sull'isola"), trayCells);
// un tocco sul resto della fascia la richiude
trayElement.addEventListener("mousedown", (event) => {
  if ((event.target as Element).closest(".tray-cell")) return;
  trayOpen = false;
  redraw();
});

function renderTrayCells(items: GardenItem[]): void {
  const key = items.map((x) => x.id).join(",");
  if (key === trayKey) return;
  trayKey = key;
  trayCells.replaceChildren(...items.map((x) => {
    const cell = h("div", { class: `tray-cell ${rarityOf(x)}`, title: x.name, role: "button", "aria-label": `Metti ${x.name}` },
      h("img", { src: `ff://app/assets/giardino/${x.id}.png`, alt: "", draggable: "false" }),
      h("span", { class: x.name.length > 15 ? "small" : "" }, x.name));
    cell.addEventListener("mousedown", (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      const p = scenePoint(event);
      carry = { what: { kind: "fresh", item: x.id }, feet: p, grab: { x: 0, y: 0 }, start: p, pointer: p, moved: false, turned: x.joins && repeatTurned };
    });
    return cell;
  }));
}

let hudKey = "";

function renderHud(): void {
  if (!data) return;
  const island = shownIsland();
  // si rifà solo se cambia qualcosa che si vede (un pulsante rifatto fra la pressione e il rilascio perderebbe il clic)
  const key = JSON.stringify([data.shown, data.found, data.total, data.minutesToNextGift, data.nextGiftProgress, data.streakDays, data.streakFrozen, data.has.length,
    camera.zoom, isFitted(), trayOpen, carry?.moved ?? false, carry?.what.kind ?? null, carry && inRemoveZone(carry.pointer), message, bubble,
    bubble ? companionRect(bubble.pet) : null, island?.placements.length]);
  if (key === hudKey) return;
  hudKey = key;
  const children: HTMLElement[] = [];
  const back = h("button", { type: "button", class: "chip button back", title: "Torna al menu" }, icon("back", 15), "Menu");
  back.addEventListener("click", () => api.back());
  const caption = h("button", { type: "button", class: "chip button caption", title: "Tocca per vedere tutte le isole, e di nuovo per tornare a questa. Si ingrandisce e ci si sposta da un'isola all'altra anche con lo zoom e trascinando." },
    icon("map", 13), `Isola di ${island?.name ?? ""}`);
  caption.addEventListener("click", toggleWorldView);
  children.push(back, caption);

  // in alto a destra: quanto manca alla prossima figurina, la serie di giorni, quante figurine
  const top = h("div", { class: "top-right" });
  if (data.minutesToNextGift !== null) {
    const left = data.minutesToNextGift;
    const gift = chip("gift", left === 0 ? "La prossima figurina è già pronta: arriva alla fine del prossimo focus."
      : `Ancora ${left} ${left === 1 ? "minuto" : "minuti"} di studio (focus completati, da 20 minuti in su) e trovi una figurina.`,
    styled(h("span", { class: "fill" }), { width: `${Math.round((data.nextGiftProgress ?? 0) * 100)}%` }), icon("gift", 13),
    h("span", { class: "label" }, left === 0 ? "pronta al prossimo focus" : `ancora ${left} min`));
    top.append(gift);
  }
  if (data.streakFrozen || data.streakDays >= 2) {
    const days = data.streakDays;
    const tip = `Serie di ${days} ${days === 1 ? "giorno" : "giorni"}` + (data.streakFrozen ? ". Ieri non hai studiato: la serie è ghiacciata, studia oggi per non perderla."
      : ": con la serie le figurine rare sono più probabili.");
    top.append(chip(data.streakFrozen ? "streak frozen" : "streak", tip, icon(data.streakFrozen ? "snowflake" : "flame", 13),
      h("span", { class: "label" }, data.streakFrozen ? "ghiacciata" : `serie di ${days}`)));
  }
  top.append(chip("album", `L'album: ${data.found} figurine su ${data.total}. Le trovi studiando: ogni focus completato di almeno 20 minuti conta, e ogni tanto (60 minuti la prima, un po' di più a ogni figurina) ne arriva una. Con più giorni di fila e con i focus lunghi le figurine rare sono più probabili.`,
    h("span", { class: "number" }, `${data.found}/${data.total}`), h("span", { class: "label" }, "figurine")));
  const albumButton = h("button", { type: "button", class: "chip button album-button", title: "Apri l'album delle figurine" }, icon("book", 14), "Album");
  albumButton.addEventListener("click", () => api.showAlbum());
  top.append(albumButton);
  children.push(top);

  // lo zoom
  const zoom = styled(h("div", { class: "chip zoom" }), { bottom: `${16 + (trayVisible() ? 96 : 0)}px` });
  const zoomButton = (name: "minus" | "fit" | "plus", title: string, enabled: boolean, action: () => void): HTMLButtonElement => {
    const b = h("button", { type: "button", title, "aria-label": title, disabled: !enabled }, icon(name, 14));
    b.addEventListener("click", action);
    return b;
  };
  zoom.append(
    zoomButton("minus", "Rimpicciolisci", camera.zoom > ZOOM_MIN + 0.001, () => moveCamera(zoomCamera(camera, 1 / 1.3))),
    zoomButton("fit", "Tutta l'isola", !isFitted(), resetCamera),
    zoomButton("plus", "Ingrandisci", camera.zoom < ZOOM_MAX - 0.001, () => moveCamera(zoomCamera(camera, 1.3))));
  children.push(zoom);

  // la cassetta, o la pillola che la apre
  const items = trayItems();
  if (trayVisible()) {
    renderTrayCells(items);
    children.push(trayElement);
  } else if (items.length > 0 && !(carry?.moved)) {
    const pill = h("button", { type: "button", class: "chip button tray-pill", title: "Le figurine che hai trovato: trascinale sull'isola" }, icon("inbox", 14), "Da mettere");
    pill.addEventListener("click", () => { trayOpen = true; markTrayHintSeen(); redraw(); });
    children.push(pill);
    if (carry === null && !trayHintSeen()) children.push(h("div", { class: "tray-hint" }, TRAY_HINT));
  }
  if (isCarryingPlaced()) {
    children.push(h("div", { class: `remove-zone${carry && inRemoveZone(carry.pointer) ? " hover" : ""}` }, "Rilascia qui per toglierla"));
  }

  // una riga in basso
  const hintBottom = 16 + 34 + (trayVisible() ? 96 : 0) - 34;
  let hint: string | null = message;
  let narrow = false;
  if (hint === null && carry?.moved && carry.what.kind !== "companion") { hint = "R per girarla"; narrow = true; }
  if (hint === null && carry === null && (island?.placements.length ?? 0) === 0) hint = "Trova le figurine a fine focus: si mettono qui da sole.";
  if (hint !== null) children.push(styled(h("div", { class: `hint${narrow ? " narrow" : ""}` }, hint), { bottom: `${hintBottom}px` }));

  // il fumetto del compagno toccato
  if (bubble) {
    const hit = companionRect(bubble.pet);
    if (hit) {
      const width = 254;
      const x = Math.min(Math.max(hit.x + hit.w / 2 - width / 2, 8), SCENE_W - width - 8);
      const element = styled(h("div", { class: "bubble" }, bubble.text), { left: `${x}px`, bottom: `${SCENE_H - Math.max(hit.y - 12, 56)}px`, width: `${width}px` });
      children.push(element);
    }
  }
  hud.replaceChildren(...children);
}

/** Dove sta disegnato il compagno di un'isola (per il fumetto). */
function companionRect(pet: string): { x: number; y: number; w: number; h: number } | null {
  if (!data) return null;
  const island = data.islands.find((i) => i.id === pet);
  const iso = island && isoOf(island, camera);
  if (!island?.companion || !iso) return null;
  const c = iso.center(island.companion);
  const height = companionHeight(pet) * iso.scale;
  return { x: c.x - height / 2, y: c.y + iso.tileH * FEET_OFFSET - height, w: height, h: height };
}

// ---- il mouse e la tastiera

/** Un punto della finestra nelle coordinate della scena. */
function scenePoint(event: MouseEvent): { x: number; y: number } {
  const box = canvas.getBoundingClientRect();
  return { x: (event.clientX - box.left) / sceneScale(), y: (event.clientY - box.top) / sceneScale() };
}

async function turn(id: string): Promise<void> {
  const island = shownIsland();
  const placement = island?.placements.find((p) => p.id === id);
  const done = await api.command({ name: "rotate", id });
  if (!done) { flash("Girata non ci sta: c'è qualcosa accanto."); return; }
  // una staccionata con dei vicini segue la fila: da sola non cambia
  const x = placement && itemWithId(placement.item);
  if (island && placement && x?.joins) {
    const among = linkedOn(island, x.id, placement.id);
    if (linkArms(placement, among, false) === linkArms(placement, among, true)) flash("La staccionata segue quelle accanto.");
  }
}

async function speak(pet: string): Promise<void> {
  const text = await api.phrase(pet);
  if (!text) return;
  bubble = { pet, text };
  window.clearTimeout(bubbleTimer);
  bubbleTimer = window.setTimeout(() => { bubble = null; redraw(); }, 5000);
  redraw();
}

/** Un tocco sull'ospite: lo saluti. La prima volta di una specie entra nel diario e lascia un regalo (stelline e una riga); le altre ti saluta e basta. */
async function greet(): Promise<void> {
  const guest = greetVisitor();
  if (!guest || !data) return;
  if (!guest.first) { flash(`${guest.name} ti saluta.`); return; }
  const welcome = await api.greetGuest(guest.id, reasonText(guest.item, guest.corner));
  if (!welcome.isFirst) { flash(`${guest.name} ti saluta.`); return; }
  celebrations.push({ caption: "Nuovo ospite", title: guest.name, island: data.shown, placement: null, visitor: true, start: null });
  flash(welcome.gift ? `${guest.name} è ${guest.came} a trovarti! Ti ha lasciato: ${welcome.gift}.` : `${guest.name} è ${guest.came} a trovarti!`);
}

canvas.addEventListener("mousedown", (event) => {
  if (event.button !== 0 || !data) return;
  const p = scenePoint(event);
  bubble = null;
  // un tocco su un'altra isola (o su una sua cosa) la porta in primo piano; su una chiusa non succede niente
  const hit = hitAt(data, camera, p.x, p.y);
  if (hit && hit.island !== data.shown) { focus(hit.island); redraw(); return; }
  const under = islandAt(data, camera, p.x, p.y);
  const underIsland = under === null ? undefined : data.islands.find((i) => i.id === under);
  if (!hit && underIsland && under !== data.shown) {
    if (underIsland.open) focus(underIsland.id);
    else flash(`Questa isola è chiusa: si sblocca a ${underIsland.need} focus pieni di studio (ne hai ${Math.min(data.focuses, underIsland.need)}).`);
    redraw();
    return;
  }
  if (!hit) {
    // sullo sfondo: due tocchi ingrandiscono (o, già ingrandita, rimettono tutta l'isola), trascinando ci si sposta
    if (event.detail === 2) {
      const shown = shownIsland();
      if (shown && !isFitted() && camera.zoom > islandCamera(shown).zoom * 1.05) resetCamera(); else moveCamera(zoomCamera(camera, 1.8, p));
    } else {
      panning = p;
      canvas.classList.add("panning");
    }
    return;
  }
  if (hit.kind === "visitor") { void greet(); return; }
  if (hit.kind === "placed") {
    if (event.detail === 2) { void turn(hit.id); return; }
    const placement = shownIsland()?.placements.find((x) => x.id === hit.id);
    carry = { what: { kind: "placed", id: hit.id }, feet: hit.feet, grab: { x: hit.feet.x - p.x, y: hit.feet.y - p.y }, start: p, pointer: p, moved: false, turned: placement?.turned ?? false };
  } else {
    carry = { what: { kind: "companion", pet: hit.pet }, feet: hit.feet, grab: { x: hit.feet.x - p.x, y: hit.feet.y - p.y }, start: p, pointer: p, moved: false, turned: false };
  }
});

window.addEventListener("mousemove", (event) => {
  if (panning) {
    const q = scenePoint(event);
    moveCamera({ ...camera, panX: camera.panX + q.x - panning.x, panY: camera.panY + q.y - panning.y });
    panning = q;
    return;
  }
  if (!carry || !data) return;
  const p = scenePoint(event);
  carry.pointer = p;
  if (!carry.moved && Math.hypot(p.x - carry.start.x, p.y - carry.start.y) > 4) {
    carry.moved = true;
    canvas.classList.add("carrying");
    // presa una copia, la cassetta si toglie di mezzo: il davanti dell'isola è libero
    if (carry.what.kind === "fresh") trayOpen = false;
  }
  if (carry.moved) {
    carry.feet = { x: p.x + carry.grab.x, y: p.y + carry.grab.y };
    // passando sopra un'altra isola aperta, diventa lei quella viva (non mentre si va verso la zona per toglierla, o sopra la cassetta)
    const overBottom = inRemoveZone(p) || (trayVisible() && p.y > SCENE_H - 96);
    if (carry.what.kind !== "companion" && !overBottom) {
      const under = islandAt(data, camera, p.x, p.y);
      if (under && under !== data.shown && data.islands.find((i) => i.id === under)?.open) focus(under);
    }
    redraw();
  }
});

window.addEventListener("mouseup", (event) => {
  if (panning) {
    panning = null;
    canvas.classList.remove("panning");
    return;
  }
  if (!carry || !data) return;
  const current = carry;
  const p = scenePoint(event);
  const target = carryTarget(current);
  const island = shownIsland();
  carry = null;
  canvas.classList.remove("carrying");
  const insideScene = p.x >= 0 && p.y >= 0 && p.x <= SCENE_W && p.y <= SCENE_H;
  const wrongIsland = (item: GardenItem | undefined): string | null =>
    item && island && item.island !== null && item.island !== island.id ? wrongIslandLine(item, data!.islands.find((i) => i.id === item.island)?.name ?? item.island) : null;
  const notHere = "Lì non ci sta: serve una tessera libera, fuori dal sentiero.";
  switch (current.what.kind) {
    case "placed": {
      if (!current.moved || !island) break;
      const id = current.what.id;
      if (inRemoveZone(p)) void api.command({ name: "remove", id });
      else if (target?.valid) void api.command({ name: "move", id, col: target.origin.col, row: target.origin.row, turned: current.turned, island: island.id });
      else if (insideScene) flash(wrongIsland(carryItem(current)) ?? notHere);
      break;
    }
    case "companion": {
      if (!current.moved) { void speak(current.what.pet); break; }
      if (!inRemoveZone(p) && target?.valid) {
        void api.command({ name: "companion", pet: current.what.pet, col: target.origin.col, row: target.origin.row });
        placeCompanion(current.what.pet, target.origin);
      }
      break;
    }
    case "fresh": {
      if (!island) break;
      const item = itemWithId(current.what.item);
      if (!current.moved) {
        const line = wrongIsland(item);
        if (line) flash(line);
        else void api.command({ name: "placeSomewhere", item: current.what.item, island: island.id }).then((done) => {
          if (!done) flash("Non c'è più posto sull'isola: togli qualcosa, o completa una doppia pagina dell'album per allargarla.");
        });
      } else if (target?.valid) {
        void api.command({ name: "place", item: current.what.item, col: target.origin.col, row: target.origin.row, turned: current.turned, island: island.id });
        // ogni cosa si ripete: la cassetta resta a portata (la staccionata, la prossima parte girata come questa)
        if (item?.joins) repeatTurned = current.turned;
        trayOpen = true;
      } else if (insideScene) {
        flash(wrongIsland(item) ?? notHere);
      }
      break;
    }
  }
  redraw();
});

canvas.addEventListener("contextmenu", (event) => {
  event.preventDefault();
  if (!data || carry) return;
  const p = scenePoint(event);
  const hit = hitAt(data, camera, p.x, p.y);
  if (hit?.kind === "placed" && hit.island === data.shown) api.contextMenu(hit.id);
});

canvas.addEventListener("wheel", (event) => {
  event.preventDefault();
  const p = scenePoint(event);
  // il pizzico sul touchpad arriva con ctrl; la rotellina del mouse va a scatti (righe intere); due dita sul touchpad spostano
  if (event.ctrlKey) moveCamera(zoomCamera(camera, Math.exp(-event.deltaY * 0.01), p));
  else if (event.deltaMode !== 0 || (event.deltaX === 0 && Math.abs(event.deltaY) >= 50 && Number.isInteger(event.deltaY))) {
    moveCamera(zoomCamera(camera, Math.exp(-Math.sign(event.deltaY) * Math.min(Math.abs(event.deltaMode === 0 ? event.deltaY : event.deltaY * 33), 200) * 0.0022), p));
  } else {
    moveCamera({ ...camera, panX: camera.panX - event.deltaX / sceneScale(), panY: camera.panY - event.deltaY / sceneScale() });
  }
}, { passive: false });

window.addEventListener("keydown", (event) => {
  if (event.ctrlKey || event.metaKey || event.altKey) return;
  // R: gira quello che si sta trascinando
  if ((event.key === "r" || event.key === "R") && carry?.moved && carry.what.kind !== "companion") {
    carry.turned = !carry.turned;
    redraw();
    event.preventDefault();
    return;
  }
  if (carry) {
    if (event.key === "Escape") { carry = null; canvas.classList.remove("carrying"); redraw(); event.preventDefault(); }
    return;
  }
  switch (event.key) {
    case "+": case "=": moveCamera(zoomCamera(camera, 1.3)); break;
    case "-": moveCamera(zoomCamera(camera, 1 / 1.3)); break;
    case "0": resetCamera(); break;
    case "m": case "M": toggleWorldView(); break;
    case "Escape": if (trayOpen) { trayOpen = false; redraw(); } else api.back(); break;
    default: return;
  }
  event.preventDefault();
});

window.addEventListener("resize", resize);

window.__garden = {
  get data() { return data; },
  get camera() { return camera; },
  get frames() { return frames; },
  get trayOpen() { return trayOpen; },
  get carry() { return carry === null ? null : { ...carry, target: carryTarget(carry) }; },
  get message() { return message; },
  get ceremony() { return ceremony === null ? null : { ...ceremony.arrival, gliding: ceremony.gliding }; },
  get celebrations() { return celebrations.map((c) => `${c.caption} · ${c.title}`); },
  get life() { return { walkers: [...life.walkers].map(([pet, w]) => ({ pet, ...w })), visitor: life.visitor }; },
  greet,
  /** Per le prove: il compagno sta già usando la prima copia di `item` (la scena di GardenInteractions). */
  showInteraction(pet: string, item: string) { if (data) showInteraction(data, pet, item); redraw(); },
  setCamera(next: Camera) { moveCamera(next); },
  resetCamera,
  worldView() { moveCamera(worldCamera()); },
  /** Dove cade a schermo (in pixel della finestra) il centro di una tessera dell'isola mostrata. */
  tileOnScreen(col: number, row: number) {
    const island = shownIsland();
    const iso = island && isoOf(island, camera);
    if (!iso) return null;
    const c = iso.center({ col, row });
    return { x: c.x * sceneScale(), y: c.y * sceneScale() };
  },
};

// la prima volta che vedi un compagno usare una cosa, la scena entra nell'album: le stelline escono dalla cosa
setSceneNotifier((pet, seen) => {
  void api.noteScene(pet, seen.interaction.item).then((first) => {
    if (first) celebrations.push({ caption: "Nuova scena nell'album", title: seen.interaction.caption, island: pet, placement: seen.placement.id, start: null });
  });
});
api.onData(receive);
api.onMessage((text) => flash(text));
void api.getData().then((next) => { if (next) receive({ ...next, reset: true }); });
void document.fonts.load("20px Chewy").then(() => redraw());
requestAnimationFrame(tick);
resize();
