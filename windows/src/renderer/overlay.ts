// La pagina trasparente a tutto schermo (area di lavoro): dentro ci sono il compagno, il fumetto e, più avanti, l'orologio.
// Qui si tiene insieme tutto: caricamento del compagno, camminata, trascinamento, parole, clic che passano.

import { PETS, petInfo } from "../core/pets.ts";
import type { PetData } from "../core/pets.ts";
import { chattinessInterval } from "../core/rules.ts";
import { Walker } from "../core/walker.ts";
import type { WalkerAction } from "../core/walker.ts";
import type { FocusFriendsApi, SettingsSnapshot } from "../shared/api.ts";
import { PetView } from "./petView.ts";
import { Speaker } from "./speaker.ts";

declare global {
  interface Window {
    focusfriends: FocusFriendsApi;
    /** Solo nelle prove automatiche. */
    __ff?: Record<string, (...args: never[]) => unknown>;
  }
}

/** Distanza dal bordo destro dell'area di lavoro quando compare. */
const START_MARGIN = 24;
/** Quanto bisogna muovere il mouse perché un clic diventi un sollevamento. */
const PICK_DISTANCE = 3;

const api = window.focusfriends;
const stage = document.getElementById("stage")!;
const urlOf = (path: string): string => `ff://app/assets/${path.split("/").map(encodeURIComponent).join("/")}`;

let settings: SettingsSnapshot;
let view: PetView;
let walker: Walker;
let visible = true;
let interactive = false;
/** Quanto sono in alto i piedi rispetto al bordo basso della scena: si mantiene se la scena cambia. */
let feetAbove = 0;
let timer: number | undefined;

interface Drag {
  startX: number;
  startY: number;
  /** Dove si teneva il compagno rispetto al cursore (se non c'è il disegno «sollevato»). */
  offsetX: number;
  offsetY: number;
  picked: boolean;
  /** Dimensione della scatola prima del sollevamento. */
  restWidth: number;
  restHeight: number;
}
let drag: Drag | null = null;

const sceneSize = (): { width: number; height: number } => ({ width: window.innerWidth, height: window.innerHeight });

const speaker = new Speaker({
  container: stage,
  box: () => ({ ...view.position, ...view.size }),
  visibleTop: () => view.visibleTop,
  stage: sceneSize,
  nextPhrase: () => api.nextPhrase(settings.pet),
  interval: () => (visible ? chattinessInterval(settings.phraseFrequency, false) : null),
});

// ---- il compagno

/** Mette il compagno con i piedi sulla linea di terra (il bordo basso della scena). */
function placeOnGround(left: number): void {
  const { height } = sceneSize();
  view.setPosition(left, height - view.size.height + view.feetHeight);
  feetAbove = 0;
}

async function loadPet(id: string): Promise<void> {
  const pet = petInfo(id);
  const next = await PetView.create(pet, urlOf);
  const previous = view as PetView | undefined;
  // Cambio di compagno: la scatola si ridimensiona tenendo ferme i piedi (centro del lato basso).
  let anchor: { x: number; bottom: number } | null = null;
  if (previous) {
    const p = previous.position, s = previous.size;
    anchor = { x: p.left + s.width / 2, bottom: p.top + s.height };
    previous.canvas.remove();
  }
  view = next;
  view.onArtChanged = () => undefined;
  stage.append(view.canvas);
  if (anchor) view.setPosition(anchor.x - pet.size.width / 2, anchor.bottom - pet.size.height);
  else placeOnGround(sceneSize().width - pet.size.width - START_MARGIN);
  walker = new Walker(performance.now());
  view.render(performance.now());
}

/** La scena è cambiata (barra delle applicazioni, risoluzione): il compagno resta alla stessa altezza da terra e dentro lo schermo. */
function onResize(): void {
  if (!view) return;
  const { width, height } = sceneSize();
  const { left } = view.position;
  view.setPosition(Math.min(Math.max(left, 0), Math.max(width - view.size.width, 0)), height - view.size.height + view.feetHeight - feetAbove);
}

// ---- il ciclo di animazione

function applyAction(action: WalkerAction, pet: PetData, now: number): void {
  if (action.facingRight !== undefined) view.setMirrored(!action.facingRight && pet.facesRight);
  if (action.pose !== undefined) view.setPose(action.pose);
  if (action.sleepMarks !== undefined) view.setSleepMarks(action.sleepMarks, now);
  if (action.x !== undefined) {
    view.setPosition(action.x, view.position.top);
  }
}

function tick(): void {
  const now = performance.now();
  const pet = view.pet;
  const scene = sceneSize();
  const input = {
    now, pet, visible, movementEnabled: settings.movement,
    dragging: drag !== null,
    speaking: speaker.isSpeaking, showingFocusGrowth: false,
    x: view.position.left, width: view.size.width, screenMinX: 0, screenMaxX: scene.width,
  };
  applyAction(walker.tick(input), pet, now);
  speaker.follow(now);
  if (visible && view.needsRender(now)) view.render(now);
  timer = window.setTimeout(tick, walker.intervalMs(pet, visible, settings.movement));
}

// ---- il mouse: clic che passano, trascinamento

function setInteractive(on: boolean): void {
  if (on === interactive) return;
  interactive = on;
  api.setInteractive(on);
}

function localPoint(event: MouseEvent): { x: number; y: number } {
  const { left, top } = view.position;
  return { x: event.clientX - left, y: event.clientY - top };
}

function clampPosition(left: number, top: number): { left: number; top: number } {
  const scene = sceneSize(), size = view.size;
  return {
    left: Math.min(Math.max(left, -size.width / 2), scene.width - size.width / 2),
    top: Math.min(Math.max(top, 0), scene.height - size.height / 2),
  };
}

function onMouseMove(event: MouseEvent): void {
  if (!view) return;
  if (drag) {
    const moved = Math.hypot(event.clientX - drag.startX, event.clientY - drag.startY);
    if (view.hasPickedImage) {
      if (!drag.picked) {
        if (moved <= PICK_DISTANCE) return;
        beginPick();
      }
      movePicked(event);
    } else {
      const next = clampPosition(event.clientX - drag.offsetX, event.clientY - drag.offsetY);
      view.setPosition(next.left, next.top);
    }
    return;
  }
  const point = localPoint(event);
  setInteractive(visible && view.hitTest(point.x, point.y));
}

function onMouseDown(event: MouseEvent): void {
  if (!view || event.button !== 0 || drag) return;
  const point = localPoint(event);
  if (!visible || !view.hitTest(point.x, point.y)) return;
  const { left, top } = view.position;
  drag = {
    startX: event.clientX, startY: event.clientY, offsetX: event.clientX - left, offsetY: event.clientY - top,
    picked: false, restWidth: view.size.width, restHeight: view.size.height,
  };
}

function onMouseUp(event: MouseEvent): void {
  if (!view || !drag) return;
  if (drag.picked) endPick();
  drag = null;
  // Finito il trascinamento, di nuovo: i clic passano dove il compagno non c'è.
  const point = localPoint(event);
  setInteractive(visible && view.hitTest(point.x, point.y));
  // Ricorda a che altezza da terra sta: se la scena cambia, ci resta.
  feetAbove = sceneSize().height - (view.position.top + view.size.height - view.feetHeight);
}

/** Comincia a sollevarlo: mostra il disegno «sollevato» e ridimensiona la scatola. */
function beginPick(): void {
  if (!drag || !view.pet.picked) return;
  drag.picked = true;
  view.setPicked(true);
  view.setBoxSize(view.pet.picked.size);
}

/** Tiene il cursore sul punto di presa del disegno. */
function movePicked(event: MouseEvent): void {
  const picked = view.pet.picked;
  if (!picked) return;
  const next = clampPosition(event.clientX - picked.grab.x * picked.size.width, event.clientY - (1 - picked.grab.y) * picked.size.height);
  view.setPosition(next.left, next.top);
}

/** Lo rimette giù: dimensione normale, con i piedi (centro del lato basso) dove si trova. */
function endPick(): void {
  if (!drag) return;
  const { left, top } = view.position, size = view.size;
  const anchorX = left + size.width / 2, anchorBottom = top + size.height;
  view.setPicked(false);
  view.setBoxSize({ width: drag.restWidth, height: drag.restHeight });
  view.setPosition(anchorX - drag.restWidth / 2, anchorBottom - drag.restHeight);
}

// ---- avvio

async function start(): Promise<void> {
  settings = await api.getSettings();
  await loadPet(settings.pet);

  api.onSettingsChanged((next) => {
    const previous = settings;
    settings = next;
    if (next.pet !== previous.pet) void loadPet(next.pet);
    if (next.phraseFrequency !== previous.phraseFrequency) {
      if (next.phraseFrequency === "never") speaker.dismissNow();
      speaker.reschedule();
    }
  });
  api.onVisibilityChanged((on) => {
    visible = on;
    if (!on) { speaker.dismissNow(); setInteractive(false); } else { speaker.reschedule(); }
    window.clearTimeout(timer);
    tick();
  });

  document.addEventListener("mousemove", onMouseMove);
  document.addEventListener("mousedown", onMouseDown);
  window.addEventListener("mouseup", onMouseUp);
  document.addEventListener("contextmenu", (event) => event.preventDefault());
  window.addEventListener("resize", onResize);

  if (api.selfTest) {
    window.__ff = {
      say: ((text?: string) => { if (text) speaker.say(text); else void speaker.sayRandom(); }) as () => void,
      pets: (() => PETS.map((p) => p.id)) as () => string[],
      state: (() => ({
        pet: view.pet.id, ...view.position, ...view.size, picked: view.isPickedUp, mirrored: view.isMirrored, drag: drag !== null,
        scene: sceneSize(), speaking: speaker.isSpeaking,
      })) as () => unknown,
      hit: ((x: number, y: number) => view.hitTest(x - view.position.left, y - view.position.top)) as () => boolean,
    };
  }
  speaker.start();
  tick();
}

void start();
