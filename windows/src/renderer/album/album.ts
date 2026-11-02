// La pagina dell'album: prima la copertina in pelle; un clic lo apre su due pagine con sei figurine ciascuna. Si sfoglia con le frecce, le
// linguette delle sezioni, la tastiera o la rotellina. Come sul Mac, le animazioni (la copertina che si apre, la pagina che gira) sono fotografie
// del libro (`book.ts` disegnato senza prato né comandi) su fogli che girano in 3D, che ci sono solo mentre durano.

import { CATEGORY_TITLES, islandRule, itemNumber, RARITY_TITLES, rarityOf } from "../../core/gardenCatalog.ts";
import type { GardenItem } from "../../core/gardenCatalog.ts";
import type { AlbumApi, AlbumData } from "../../shared/albumApi.ts";
import { h, icon } from "../card/dom.ts";
import { makeCanvas, sprite, whenSpritesLoad } from "../garden/sprites.ts";
import { closedShadow, controls, coverRect, drawBook, inside, openShadow, SIZE, slots, spreadRect, SPREADS, wantedImages } from "./book.ts";
import type { BookState, Mode, Rect } from "./book.ts";

declare global {
  interface Window {
    focusfriendsAlbum: AlbumApi;
    /** Per le prove dal vivo. */
    __album?: unknown;
  }
}

const api = window.focusfriendsAlbum;
const canvas = document.getElementById("book") as HTMLCanvasElement;
const ctx = canvas.getContext("2d")!;
const view = document.getElementById("view") as HTMLDivElement;

let data: AlbumData | null = null;
let mode: Mode = "cover";
let spread = 0;
let contentAlpha = 1;
let message: string | null = null;
let messageTimer = 0;
let newOnes = new Set<string>();
/** Il foglio delle animazioni, mentre c'è; e la doppia pagina chiesta mentre una pagina sta girando (parte appena finisce). */
let stage: HTMLDivElement | null = null;
let queued: number | null = null;
let scheduled = false;

const scale = (): number => window.innerWidth / SIZE.width;
const reduceMotion = (): boolean => window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const state = (overrides: Partial<BookState> = {}): BookState =>
  ({ mode, spread, contentAlpha, capturing: false, content: true, message, newOnes, ...overrides });

function resize(): void {
  const dpr = window.devicePixelRatio * scale();
  canvas.width = Math.round(SIZE.width * dpr);
  canvas.height = Math.round(SIZE.height * dpr);
  view.style.transform = `scale(${scale()})`;
  redraw();
}

function redraw(): void {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    if (!data) return;
    const dpr = canvas.width / SIZE.width;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    drawBook(ctx, data, state());
  });
}

whenSpritesLoad(redraw);

function flash(text: string): void {
  message = text;
  window.clearTimeout(messageTimer);
  messageTimer = window.setTimeout(() => { message = null; redraw(); }, 4000);
  redraw();
}

/** Alla riapertura il libro è chiuso; se ci sono figurine nuove si aprirà sulla loro pagina. */
function prepare(next: AlbumData): void {
  cancelAnimation();
  mode = "cover";
  newOnes = new Set(next.unseen);
  message = null;
  spread = Math.min(Math.max(next.spread, 0), SPREADS.length - 1);
}

function receive(next: AlbumData): void {
  const first = data === null;
  data = next;
  document.title = next.title;
  if (first || next.prepare) prepare(next);
  redraw();
}

// ---- le fotografie del libro, e i pezzi che ne servono

function snapshot(at: Mode, index: number, content: boolean): HTMLCanvasElement {
  const dpr = canvas.width / SIZE.width;
  const made = makeCanvas(SIZE.width * dpr, SIZE.height * dpr);
  const c = made.getContext("2d")!;
  c.setTransform(dpr, 0, 0, dpr, 0, 0);
  drawBook(c, data!, state({ mode: at, spread: index, contentAlpha: 1, capturing: true, content, message: null }));
  return made;
}

/** Un pezzo della fotografia, come elemento posizionato nella vista (`at`), grande `size` (di norma quanto il pezzo). */
function piece(shot: HTMLCanvasElement, from: Rect, at: Rect): HTMLCanvasElement {
  const dpr = shot.width / SIZE.width;
  const made = makeCanvas(from.w * dpr, from.h * dpr);
  made.getContext("2d")!.drawImage(shot, from.x * dpr, from.y * dpr, from.w * dpr, from.h * dpr, 0, 0, made.width, made.height);
  Object.assign(made.style, { position: "absolute", left: `${at.x}px`, top: `${at.y}px`, width: `${at.w}px`, height: `${at.h}px` });
  return made;
}

function box(r: Rect, className: string): HTMLDivElement {
  const made = h("div", { class: className });
  Object.assign(made.style, { left: `${r.x}px`, top: `${r.y}px`, width: `${r.w}px`, height: `${r.h}px` });
  return made;
}

/** Un foglio che gira: il davanti e il dietro (si vede solo il lato rivolto a noi), che si scuriscono a metà giro (solo il disegno, non i bordi
 *  trasparenti: un filtro sul pezzo invece di un velo nero sopra). `forward`: appeso al dorso sul lato destro e gira verso sinistra. Il foglio ha il
 *  lato del dorso in `hingeX` e il centro in altezza in `centerY`. */
function leaf(front: HTMLCanvasElement, back: HTMLCanvasElement, size: { w: number; h: number }, hingeX: number, centerY: number, forward: boolean) {
  const element = box({ x: forward ? hingeX : hingeX - size.w, y: centerY - size.h / 2, w: size.w, h: size.h }, "leaf");
  element.style.transformOrigin = forward ? "left center" : "right center";
  const face = (canvasPiece: HTMLCanvasElement, turned: boolean): HTMLCanvasElement => {
    const w = parseFloat(canvasPiece.style.width), hh = parseFloat(canvasPiece.style.height);
    const holder = box({ x: forward ? 0 : size.w - w, y: (size.h - hh) / 2, w, h: hh }, "face");
    if (turned) holder.style.transform = "rotateY(180deg)";
    Object.assign(canvasPiece.style, { left: "0", top: "0" });
    holder.append(canvasPiece);
    element.append(holder);
    return canvasPiece;
  };
  return { element, frontShade: face(front, false), backShade: face(back, true) };
}

function makeStage(): HTMLDivElement {
  stage?.remove();
  const made = h("div", { class: "stage" });
  view.append(made);
  stage = made;
  return made;
}

function cancelAnimation(): void {
  queued = null;
  stage?.getAnimations({ subtree: true }).forEach((a) => a.cancel());
  stage?.remove();
  stage = null;
  contentAlpha = 1;
}

const EASE = "ease-in-out", EASE_OUT = "ease-out", EASE_IN = "ease-in";
const animate = (element: Element, frames: Keyframe[], duration: number, delay = 0, easing = EASE): Animation =>
  element.animate(frames, { duration: duration * 1000, delay: delay * 1000, easing, fill: "both" });

// ---- la copertina che si apre

function open(): void {
  if (mode !== "cover" || stage || !data) return;
  // si apre sulla doppia pagina della prima figurina nuova, se c'è
  const target = SPREADS.findIndex((s) => [...s.left.items, ...(s.right?.items ?? [])].some((x) => newOnes.has(x.id)));
  const cover = reduceMotion() ? null : snapshot("cover", spread, false);
  if (target >= 0) spread = target;
  api.markSeen();
  api.setSpread(spread);
  if (cover && playOpening(cover, snapshot("open", spread, false))) return;
  mode = "open";
  redraw();
}

function playOpening(cover: HTMLCanvasElement, book: HTMLCanvasElement): boolean {
  const closed = coverRect(), opened = spreadRect();
  const spineWidth = closed.w * 0.10, hingeClosed = closed.x + spineWidth;
  const slide = { w: opened.x + opened.w / 2 - hingeClosed, h: opened.y + opened.h / 2 - (closed.y + closed.h / 2) };
  const half = opened.w / 2, midX = opened.x + half;
  const leftHalf = { x: opened.x, y: opened.y, w: half, h: opened.h }, rightHalf = { x: midX, y: opened.y, w: half, h: opened.h };
  const boardWidth = closed.x + closed.w - hingeClosed;
  mode = "opening";
  redraw();
  const root = makeStage();
  // l'ombra sul tavolo passa da quella del libro chiuso a quella del libro aperto
  const shadowTo = openShadow(opened), shadowFrom = closedShadow(closed);
  const shadow = box(shadowTo, "book-shadow");
  root.append(shadow);
  // il libro sta dove starà da aperto; all'inizio è spostato, così da combaciare con la copertina com'era
  const container = h("div", { class: "book3d" });
  root.append(container);
  const right = piece(book, rightHalf, rightHalf);
  const spine = piece(cover, { x: closed.x, y: closed.y, w: spineWidth, h: closed.h }, { x: midX - spineWidth, y: closed.y + slide.h, w: spineWidth, h: closed.h });
  const parts = leaf(piece(cover, { x: hingeClosed, y: closed.y, w: boardWidth, h: closed.h }, { x: 0, y: 0, w: boardWidth, h: closed.h }),
    piece(book, leftHalf, { x: 0, y: 0, w: half, h: opened.h }), { w: half, h: closed.h }, midX, closed.y + slide.h + closed.h / 2, true);
  container.append(right, spine, parts.element);
  // all'inizio la pagina destra si vede solo dove la copertina chiusa ha il suo corpo, poi si scopre tutta
  const cutBottom = Math.max(0, opened.y + opened.h - (closed.y + slide.h + closed.h * 0.95));
  const turn = 0.85, delay = 0.08;
  animate(container, [{ transform: `translate(${-slide.w}px, ${-slide.h}px)` }, { transform: "translate(0, 0)" }], 0.95, 0, EASE_OUT);
  animate(parts.element, [{ transform: "rotateY(0deg)" }, { transform: "rotateY(-180deg)" }], turn, delay);
  animate(parts.frontShade, [{ filter: "brightness(1)" }, { filter: "brightness(0.65)" }], turn, delay);
  animate(parts.backShade, [{ filter: "brightness(0.65)" }, { filter: "brightness(1)" }], turn, delay);
  animate(spine, [{ opacity: 1 }, { opacity: 0 }], 0.25, 0.35, "linear");
  animate(right, [{ clipPath: `inset(0px ${half - boardWidth}px ${cutBottom}px 0px)` }, { clipPath: "inset(0px 0px 0px 0px)" }], 0.3, 0.25, EASE_IN);
  const last = animate(shadow, [
    { left: `${shadowFrom.x}px`, top: `${shadowFrom.y}px`, width: `${shadowFrom.w}px`, height: `${shadowFrom.h}px` },
    { left: `${shadowTo.x}px`, top: `${shadowTo.y}px`, width: `${shadowTo.w}px`, height: `${shadowTo.h}px` },
  ], 0.95);
  void Promise.all([last.finished, ...container.getAnimations({ subtree: true }).map((a) => a.finished)]).then(finishOpening, () => undefined);
  return true;
}

function finishOpening(): void {
  if (!stage || mode !== "opening") return;
  // prima si disegna il libro aperto, poi si toglie il foglio: niente lampo in mezzo
  mode = "open";
  contentAlpha = 0;
  if (data) {
    const dpr = canvas.width / SIZE.width;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    drawBook(ctx, data, state());
  }
  stage.remove();
  stage = null;
  const start = performance.now();
  const fade = (): void => {
    contentAlpha = Math.min((performance.now() - start) / 300, 1);
    redraw();
    if (contentAlpha < 1) requestAnimationFrame(fade);
  };
  requestAnimationFrame(fade);
}

// ---- la pagina che gira

function goToSpread(index: number): void {
  const target = Math.min(Math.max(index, 0), SPREADS.length - 1);
  if (stage) {
    if (mode === "open") queued = target;
    return;
  }
  if (target === spread || !data) return;
  const from = spread;
  const pages = reduceMotion() ? null : [snapshot("open", from, true), snapshot("open", target, true)] as const;
  spread = target;
  api.setSpread(spread);
  message = null;
  redraw();
  if (pages) playTurn(pages[0], pages[1], target > from);
}

function playTurn(old: HTMLCanvasElement, next: HTMLCanvasElement, forward: boolean): void {
  const opened = spreadRect();
  const half = opened.w / 2, midX = opened.x + half;
  const leftHalf = { x: opened.x, y: opened.y, w: half, h: opened.h }, rightHalf = { x: midX, y: opened.y, w: half, h: opened.h };
  const local = { x: 0, y: 0, w: half, h: opened.h };
  const root = makeStage();
  const container = h("div", { class: "book3d" });
  root.append(container);
  // sotto: la pagina che resta ferma e quella che si scopre
  const lowerLeft = piece(forward ? old : next, leftHalf, leftHalf), lowerRight = piece(forward ? next : old, rightHalf, rightHalf);
  container.append(lowerLeft, lowerRight);
  // l'ombra che il foglio butta sulla pagina che copre
  const covered = forward ? rightHalf : leftHalf;
  const cast = box(covered, forward ? "cast forward" : "cast backward");
  container.append(cast);
  const parts = leaf(piece(old, forward ? rightHalf : leftHalf, local), piece(next, forward ? leftHalf : rightHalf, local),
    { w: half, h: opened.h }, midX, opened.y + opened.h / 2, forward);
  container.append(parts.element);
  const duration = 0.6;
  const turned = animate(parts.element, [{ transform: "rotateY(0deg)" }, { transform: `rotateY(${forward ? -180 : 180}deg)` }], duration);
  animate(parts.frontShade, [{ filter: "brightness(1)" }, { filter: "brightness(0.7)" }], duration);
  animate(parts.backShade, [{ filter: "brightness(0.7)" }, { filter: "brightness(1)" }], duration);
  animate(cast, [{ opacity: 0 }, { opacity: 1 }, { opacity: 0 }], duration);
  void turned.finished.then(finishTurn, () => undefined);
}

function finishTurn(): void {
  if (!stage || mode !== "open") return;
  stage.remove();
  stage = null;
  redraw();
  if (queued !== null) {
    const next = queued;
    queued = null;
    goToSpread(next);
  }
}

// ---- il mouse e la tastiera

const ownerName = (island: string): string => {
  const owner = data?.islands.find((i) => i.id === island);
  return owner?.open ? owner.name : "un nuovo compagno";
};

function describe(item: GardenItem): void {
  if (!data) return;
  const number = itemNumber(item.id) ?? 0;
  const rule = islandRule(item, item.island === null ? "" : ownerName(item.island));
  const rarity = RARITY_TITLES[rarityOf(item)];
  if (data.has.includes(item.id)) {
    const placed = data.counts[item.id] ?? 0;
    flash(`${item.name} · n. ${number} · ${rarity} · ${rule} · se ne mettono quante vuoi${placed > 0 ? `, ${placed} nel prato` : ""}`);
  } else if (item.island !== null && !data.islands.find((i) => i.id === item.island)?.open) {
    // le cose di un animale non sbloccato non escono ai regali: si aspetta il compagno
    flash(`n. ${number} · ${rarity} · ${rule}: ancora da trovare. Esce a fine focus quando sblocchi ${ownerName(item.island)}.`);
  } else {
    flash(`n. ${number} · ${rarity} · ${rule}: ancora da trovare. Esce a fine focus.`);
  }
}

canvas.addEventListener("mousedown", (event) => {
  if (event.button !== 0) return;
  const p = { x: event.offsetX / scale(), y: event.offsetY / scale() };
  if (mode === "cover") {
    if (inside(coverRect(), p.x, p.y)) open();
    return;
  }
  if (mode !== "open") return;
  const c = controls(ctx);
  if (inside(c.previous, p.x, p.y)) { goToSpread((queued ?? spread) - 1); return; }
  if (inside(c.next, p.x, p.y)) { goToSpread((queued ?? spread) + 1); return; }
  const tab = c.tabs.find((t) => inside(t.rect, p.x, p.y));
  if (tab) { goToSpread(SPREADS.findIndex((s) => s.left.category === tab.category)); return; }
  const current = SPREADS[spread]!;
  for (const [isLeft, items] of [[true, current.left.items], [false, current.right?.items ?? []]] as const) {
    const found = slots(isLeft).findIndex((slot, i) => i < items.length && inside(slot, p.x, p.y));
    if (found >= 0) { describe(items[found]!); return; }
  }
});

window.addEventListener("keydown", (event) => {
  switch (event.key) {
    case "ArrowLeft": if (mode === "open") goToSpread((queued ?? spread) - 1); break;
    case "ArrowRight": if (mode === "open") goToSpread((queued ?? spread) + 1); else open(); break;
    case "Enter": case " ": open(); break;
    case "Escape": api.back(); break;
    default: return;
  }
  event.preventDefault();
});

// la rotellina (o due dita sul touchpad): un giro di pagina per gesto
let lastWheel = 0;
canvas.addEventListener("wheel", (event) => {
  event.preventDefault();
  if (mode !== "open" || Math.max(Math.abs(event.deltaX), Math.abs(event.deltaY)) < 8) return;
  const now = performance.now();
  if (now - lastWheel < 450) { lastWheel = now; return; }
  lastWheel = now;
  goToSpread((queued ?? spread) + (event.deltaX + event.deltaY > 0 ? 1 : -1));
}, { passive: false });

const back = h("button", { type: "button", class: "back", title: "Torna al menu" }, icon("back", 15), "Menu");
back.addEventListener("click", () => api.back());
view.append(back);
window.addEventListener("resize", resize);

window.__album = {
  get mode() { return mode; },
  get spread() { return spread; },
  get message() { return message; },
  get animating() { return stage !== null; },
  open,
  goToSpread,
  categoryTitle: (index: number) => CATEGORY_TITLES[SPREADS[index]!.left.category],
};

for (const key of wantedImages()) void sprite(key);
api.onData(receive);
void Promise.all([document.fonts.load('42px "Amatic SC Album"'), document.fonts.load('15px "Chewy"')]).catch(() => undefined).then(() => redraw());
void api.getData().then((next) => { if (next) receive({ ...next, prepare: true }); });
resize();
