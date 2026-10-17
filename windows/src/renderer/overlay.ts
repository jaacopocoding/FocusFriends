// La pagina trasparente a tutto schermo (area di lavoro): dentro ci sono il compagno, il fumetto, l'orologio e il «+5 minuti».
// Qui si tiene insieme tutto: caricamento del compagno, camminata, trascinamento, parole, timer, clic che passano.

import { PETS, finalStage, focusGrowthStage, growsWithTimer, petInfo, restImageIndex, stageForProgress } from "../core/pets.ts";
import type { PetData } from "../core/pets.ts";
import { reflectionReply } from "../core/reflection.ts";
import { clockWanted } from "../core/pomodoro.ts";
import type { PomodoroEvent, PomodoroSnapshot } from "../core/pomodoro.ts";
import { chattinessInterval } from "../core/rules.ts";
import { Walker } from "../core/walker.ts";
import type { WalkerAction } from "../core/walker.ts";
import type { FocusFriendsApi, SettingsSnapshot } from "../shared/api.ts";
import { AmbientPlayer } from "./audio/ambient.ts";
import { MusicPlayer } from "./audio/music.ts";
import { MenuCard } from "./card/card.ts";
import { openIntroCard } from "./dialogs/introCard.ts";
import { ModalHost } from "./dialogs/modal.ts";
import { openNameDialog } from "./dialogs/nameDialog.ts";
import { ReflectionCard } from "./dialogs/reflectionCard.ts";
import { openSubjectPrompt } from "./dialogs/subjectPrompt.ts";
import { ClockView, CLOCK_SIZE } from "./clockView.ts";
import { ExtendPrompt, PROMPT_SIZE } from "./extendPrompt.ts";
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
/** Quanto resta visibile l'orologio dopo che il mouse esce dal personaggio. */
const HOVER_LINGER_MS = 1000;
const RAISE_MS = 220;

const api = window.focusfriends;
const stage = document.getElementById("stage")!;
const urlOf = (path: string): string => `ff://app/assets/${path.split("/").map(encodeURIComponent).join("/")}`;

let settings: SettingsSnapshot;
let view: PetView;
let walker: Walker;
let clock: ClockView;
let prompt: ExtendPrompt;
let card: MenuCard;
let modals: ModalHost;
let reflection: ReflectionCard;
let ambient: AmbientPlayer;
let music: MusicPlayer;
let visible = true;
let interactive = false;
let timerState: PomodoroSnapshot | null = null;
let timerAt = 0;
let timer: number | undefined;
let lastMouse: { x: number; y: number } | null = null;
let hoverUntil = 0;
/** Durante un focus il compagno mostra le immagini di crescita (Ciccio nel nido, il porcellino con la carota) e sta fermo. */
let showingFocusGrowth = false;
/** Quanto ho dovuto alzare il compagno per fare spazio all'orologio sotto di lui. */
let shiftedUp = 0;
let raise: { from: number; to: number; start: number } | null = null;
const finishSound = new Audio("ff://app/resources/fine-focus.wav");

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
  interval: () => (visible ? chattinessInterval(settings.phraseFrequency, timerState?.phase === "focus") : null),
});

// ---- il compagno

/** L'altezza dei piedi, dall'alto della scena. Se è sollevato (le mani) i piedi penzolano: è il bordo basso. */
function feetY(): number {
  const { top } = view.position, { height } = view.size;
  return view.isPickedUp ? top + height : top + height - view.feetHeight;
}

/** Mette il compagno con i piedi sulla linea di terra (il bordo basso della scena). */
function placeOnGround(left: number): void {
  const { height } = sceneSize();
  view.setPosition(left, height - view.size.height + view.feetHeight);
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
  if (card) card.currentPetId = id;
  showingFocusGrowth = false;
  stage.insertBefore(view.canvas, stage.firstChild);
  if (anchor) view.setPosition(anchor.x - pet.size.width / 2, anchor.bottom - pet.size.height);
  else placeOnGround(sceneSize().width - pet.size.width - START_MARGIN);
  walker = new Walker(performance.now());
  view.render(performance.now());
  updateStage();
}

/** La scena è cambiata (barra delle applicazioni, risoluzione): il compagno resta alla stessa altezza da terra e dentro lo schermo. */
function onResize(): void {
  if (!view) return;
  const { width, height } = sceneSize();
  const above = (view.position.top + view.size.height - view.feetHeight) - height;
  const { left } = view.position;
  view.setPosition(Math.min(Math.max(left, 0), Math.max(width - view.size.width, 0)), height - view.size.height + view.feetHeight + above);
}

// ---- crescita durante il focus

/** Per i personaggi che crescono: durante il focus lo stadio avanza con il tempo, in tutti gli altri momenti sta allo stadio finale. */
function updateStage(): void {
  if (!view) return;
  const pet = view.pet;
  const focusing = timerState?.phase === "focus";
  // Chi ha le immagini di crescita del focus: durante il focus prendono il suo posto.
  if (pet.focusGrowthImages.length > 0 && view.hasFocusGrowthImages) {
    if (focusing) {
      if (!showingFocusGrowth) widenForFocusGrowth();
      showingFocusGrowth = true;
      view.showFocusGrowth(focusGrowthStage(pet, timerState?.growthProgress ?? 1));
    } else if (showingFocusGrowth) {
      showingFocusGrowth = false;
      view.endFocusGrowth();
      restoreSizeAfterFocusGrowth();
    }
    return;
  }
  if (!growsWithTimer(pet)) return;
  view.setGrowth(focusing ? stageForProgress(pet, timerState?.growthProgress ?? 1) : finalStage(pet), true);
}

/** Le immagini di crescita possono essere più larghe del personaggio (il porcellino con la carota accanto): la scatola si allarga attorno ai suoi piedi, poi torna com'era. */
function widenForFocusGrowth(): void {
  const needed = Math.ceil(view.focusGrowthWidth) + 8;
  if (needed <= view.size.width + 1 || view.isPickedUp) return;
  const { left, top } = view.position;
  const middle = left + view.size.width / 2;
  const scene = sceneSize();
  const newLeft = Math.min(Math.max(middle - needed / 2, 2), scene.width - needed - 2);
  view.setBoxSize({ width: needed, height: view.size.height });
  view.setPosition(newLeft, top);
}

function restoreSizeAfterFocusGrowth(): void {
  const pet = view.pet;
  if (view.isPickedUp || Math.abs(view.size.width - pet.size.width) <= 1) return;
  const { left, top } = view.position;
  const middle = left + view.size.width / 2;
  view.setBoxSize({ width: pet.size.width, height: view.size.height });
  view.setPosition(middle - pet.size.width / 2, top);
}

// ---- spazio sotto il compagno

/** L'orologio sta un po' più in basso quando si vedono le immagini di crescita, così non copre le zampe e le ombre. */
const clockDrop = (): number => (showingFocusGrowth ? 12 : 0);

/** Se sotto il compagno non c'è posto (sta sul fondo, sopra la barra delle applicazioni) lo alzo, e lo riabbasso a fine sessione. */
function ensureRoomBelowPet(): void {
  if (view.isPickedUp) return;       // mentre lo trascini la posizione la decide il mouse
  const needed = CLOCK_SIZE.height - 4 + clockDrop();
  // Se si sta già alzando, conta dove arriverà.
  const pending = raise ? raise.to - view.position.top : 0;
  const room = sceneSize().height - (feetY() + pending);
  if (room >= needed) return;
  const delta = needed - room;
  shiftedUp += delta;
  startRaise((raise ? raise.to : view.position.top) - delta);
}

function restorePetHeight(): void {
  if (shiftedUp <= 0) return;
  const { height } = sceneSize();
  const floor = height - view.size.height + view.feetHeight;
  const target = Math.min(view.position.top + shiftedUp, floor);
  shiftedUp = 0;
  startRaise(target);
}

function startRaise(to: number): void {
  raise = { from: view.position.top, to, start: performance.now() };
}

function stepRaise(now: number): void {
  if (!raise) return;
  const p = Math.min((now - raise.start) / RAISE_MS, 1);
  const eased = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
  view.setPosition(view.position.left, raise.from + (raise.to - raise.from) * eased);
  if (p >= 1) raise = null;
}

// ---- l'orologio e il «+5 minuti»

function inArtFrame(point: { x: number; y: number }): boolean {
  const { left, top } = view.position, { width, height } = view.size;
  const artTop = Math.max(view.artTop, 1);
  return point.x >= left && point.x < left + width && point.y >= top + height - artTop && point.y < top + height;
}

function updateClock(now: number): void {
  const s = timerState;
  if (!s || s.phase === null) {
    clock.setShown(false, now);
    return;
  }
  clock.setText(s.label, s.remainingText);
  // Quanto è passato dall'ultimo messaggio del timer (il conto a rovescia continua da solo tra un secondo e l'altro).
  const delta = s.isPaused ? 0 : (now - timerAt) / 1000;
  if (visible && lastMouse && inArtFrame(lastMouse)) hoverUntil = now + HOVER_LINGER_MS;
  const wanted = clockWanted(
    { phase: s.phase, elapsedSeconds: s.elapsedSeconds + delta, remainingSeconds: Math.max(0, s.remainingSeconds - delta) },
    now < hoverUntil,
  );
  if (wanted && visible && !clock.isShown) ensureRoomBelowPet();
  clock.setShown(wanted && visible, now);

  // Centrato appena sotto i piedi del compagno.
  const { left, width } = { left: view.position.left, width: view.size.width };
  const scene = sceneSize();
  const x = Math.min(Math.max(left + width / 2 - CLOCK_SIZE.width / 2, 4), scene.width - CLOCK_SIZE.width - 4);
  clock.setPosition(x, feetY() - 4 + clockDrop());
}

function updatePrompt(now: number): void {
  if (!prompt.isShowing) return;
  prompt.update(now);
  // Sopra la testa del compagno (tutto ciò che si vede), o di fianco se sopra non c'è posto.
  const { left, top } = view.position, { width, height } = view.size;
  const scene = sceneSize();
  let x = Math.min(Math.max(left + width / 2 - PROMPT_SIZE.width / 2, 6), scene.width - PROMPT_SIZE.width - 6);
  const y = top + height - (view.visibleTop + 4) - PROMPT_SIZE.height;
  if (y >= 4) {
    prompt.move(x, y);
    return;
  }
  const onLeft = left + width / 2 > scene.width / 2;
  x = Math.min(Math.max(onLeft ? left - PROMPT_SIZE.width - 2 : left + width + 2, 6), scene.width - PROMPT_SIZE.width - 6);
  prompt.move(x, 4);
}

// ---- il timer

function onTimerState(next: PomodoroSnapshot): void {
  const before = timerState;
  timerState = next;
  timerAt = performance.now();
  if (!view) return;
  if ((before?.phase === "focus") !== (next.phase === "focus")) speaker.reschedule();
  if ((before?.phase ?? null) !== next.phase) {
    if (next.phase !== null) ensureRoomBelowPet(); else restorePetHeight();
  }
  updateStage();
  updateClock(performance.now());
  card.onTimerState(next);
}

function onTimerEvent(event: PomodoroEvent): void {
  switch (event.type) {
    case "say": speaker.say(event.text); break;
    case "dismissSpeech": speaker.dismissNow(); break;
    case "sound":
      finishSound.currentTime = 0;
      void finishSound.play().catch(() => undefined);
      break;
    case "focusCompleted":
      walker.eatNow({ now: performance.now(), pet: view.pet, visible, dragging: drag !== null }, view.hasFocusGrowthImages);
      break;
    case "graceBegan": prompt.show(event.seconds, performance.now()); break;
    case "graceEnded": prompt.hide(); refreshHover(); break;
    case "focusActive":
      // Il suono ambiente e la musica accompagnano il focus (non la pausa, né il focus fermo).
      ambient.setFocusActive(event.active);
      music.setFocusActive(event.active);
      break;
    case "focusRecorded":
      // A fine focus: «com'è andata?» (se non l'hai spenta dal menu). Sparisce da sola quando il timer riparte o si ferma.
      if (settings.askHowItWent) reflection.ask(event.session);
      break;
    case "reset": reflection.dismiss(); break;
  }
}

// ---- il ciclo di animazione

function applyAction(action: WalkerAction, pet: PetData, now: number): void {
  if (action.facingRight !== undefined) view.setMirrored(!action.facingRight && pet.facesRight);
  if (action.pose !== undefined) view.setPose(action.pose);
  if (action.sleepMarks !== undefined) view.setSleepMarks(action.sleepMarks, now);
  if (action.x !== undefined) view.setPosition(action.x, view.position.top);
}

function tick(): void {
  const now = performance.now();
  const pet = view.pet;
  const scene = sceneSize();
  stepRaise(now);
  applyAction(walker.tick({
    now, pet, visible, movementEnabled: settings.movement,
    dragging: drag !== null, speaking: speaker.isSpeaking, showingFocusGrowth,
    x: view.position.left, width: view.size.width, screenMinX: 0, screenMaxX: scene.width,
  }), pet, now);
  speaker.follow(now);
  if (card.isOpen) card.reposition();
  updateClock(now);
  updatePrompt(now);
  if (visible && view.needsRender(now)) view.render(now);
  if (clock.needsRender()) clock.render(now);
  timer = window.setTimeout(tick, walker.intervalMs(pet, visible, settings.movement));
}

// ---- il mouse: clic che passano, trascinamento

/** Cosa serve alla finestra adesso: tutti i clic (una scheda o una finestra di dialogo è aperta) e/o la tastiera (si sta scrivendo). */
const needs = { card: false, modal: false, keyboard: false };
function syncInput(): void {
  api.setInputMode({ interactive: needs.card || needs.modal || interactive, keyboard: needs.card || needs.modal || needs.keyboard });
}

/** I clic passano alle altre finestre, tranne dove c'è qualcosa di nostro (un pixel del compagno, il «+5 minuti», «Com'è andata?»). */
function setInteractive(on: boolean): void {
  if (needs.card || needs.modal) return;
  if (on === interactive) return;
  interactive = on;
  syncInput();
}

/** Qualcosa è sparito (una scheda, il «+5 minuti»): se il mouse non è più sopra niente di nostro, i clic tornano a passare. */
function refreshHover(): void {
  if (needs.card || needs.modal) return;
  const m = lastMouse;
  if (!m || !view || !visible) { setInteractive(false); return; }
  setInteractive(view.hitTest(m.x - view.position.left, m.y - view.position.top) || prompt.contains(m.x, m.y) || reflection.contains(m.x, m.y));
}

function localPoint(event: MouseEvent): { x: number; y: number } {
  const { left, top } = view.position;
  return { x: event.clientX - left, y: event.clientY - top };
}

/** Il punto è sopra qualcosa che deve ricevere i clic: un pixel del compagno o il pulsante «+5 minuti». */
function isOverSomething(event: MouseEvent): boolean {
  if (!visible) return false;
  const point = localPoint(event);
  return view.hitTest(point.x, point.y) || prompt.contains(event.clientX, event.clientY) || reflection.contains(event.clientX, event.clientY);
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
  lastMouse = { x: event.clientX, y: event.clientY };
  if (card.isOpen || modals.isOpen) return;
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
  setInteractive(isOverSomething(event));
}

function onMouseDown(event: MouseEvent): void {
  if (!view || event.button !== 0 || drag || card.isOpen || modals.isOpen) return;
  const point = localPoint(event);
  if (!visible || !view.hitTest(point.x, point.y)) return;
  raise = null;
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
  setInteractive(isOverSomething(event));
}

/** Comincia a sollevarlo: mostra il disegno «sollevato» e ridimensiona la scatola. */
function beginPick(): void {
  if (!drag || !view.pet.picked) return;
  drag.picked = true;
  view.setPicked(true);
  view.setBoxSize(view.pet.picked.size);
  clock.snap(clock.isShown);
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
  clock.snap(clock.isShown);
}

// ---- «Cosa studi adesso?» e benvenuto

/** Prima di avviare un focus si chiede la materia (e si ricorda l'ultima nota). */
async function askFocus(minutes: number): Promise<void> {
  const data = await api.getCardData();
  openSubjectPrompt(modals, {
    minutes, recent: data.recentSubjects, lastNote: data.lastNote,
    onChoice: (choice) => {
      if (choice.kind === "start") api.cardCommand({ name: "startFocus", minutes, subject: choice.subject });
      else if (choice.kind === "back") card.reopen();
    },
  });
}

/** La prima volta: come ti chiami e chi ti fa compagnia. Mentre c'è la scheda, niente frase a sorpresa. */
function showIntro(): void {
  speaker.stop();
  openIntroCard(modals, {
    currentPetId: settings.pet, urlOf,
    onDone: (name, petId) => {
      api.cardCommand({ name: "finishIntro", userName: name, petId });
      speaker.reschedule();
    },
  });
}

/** «Il tuo nome…»: dal menu dell'area di notifica. */
async function askName(): Promise<void> {
  const data = await api.getCardData();
  openNameDialog(modals, { current: data.userName, onSave: (name) => api.cardCommand({ name: "setName", userName: name }) });
}

// ---- avvio

async function loadPaper(): Promise<ImageBitmap | null> {
  try {
    const response = await fetch(urlOf("bubble.png"));
    return await createImageBitmap(await response.blob());
  } catch {
    return null;
  }
}

async function start(): Promise<void> {
  settings = await api.getSettings();
  timerState = await api.getTimerState();
  timerAt = performance.now();
  clock = new ClockView(await loadPaper());
  clock.canvas.classList.add("clock");
  stage.append(clock.canvas);
  prompt = new ExtendPrompt(stage);
  prompt.onClick = () => api.extendFocus();
  modals = new ModalHost(stage, (open) => { needs.modal = open; syncInput(); if (!open) refreshHover(); });
  reflection = new ReflectionCard({
    container: stage, petBox: () => ({ ...view.position, ...view.size }), scene: sceneSize,
    onKeyboard: (needed) => { needs.keyboard = needed; syncInput(); },
    onClosed: refreshHover,
    onSave: (sessionId, rating, note) => api.cardCommand({ name: "saveReflection", sessionId, rating, note }),
    onRated: (rating) => speaker.say(reflectionReply(rating)),
  });
  card = new MenuCard({
    api, container: stage, timer: () => timerState, scene: sceneSize, urlOf,
    petBox: () => ({ ...view.position, ...view.size }),
    onOpenChange: (open) => { needs.card = open; syncInput(); if (!open) refreshHover(); },
    askFocus: (minutes) => { void askFocus(minutes); },
  });
  card.currentPetId = settings.pet;
  await loadPet(settings.pet);
  ambient = new AmbientPlayer({
    workletUrl: "ff://app/noise-worklet.js", sound: settings.ambientSound, volume: settings.ambientVolume, analyser: api.selfTest,
    onStartFailure: () => speaker.say("Non riesco ad avviare l'audio: il suono ambiente non si sente."),
  });
  music = new MusicPlayer({ api, source: settings.musicSource, volume: settings.musicVolume });

  api.onSettingsChanged((next) => {
    const previous = settings;
    settings = next;
    if (next.pet !== previous.pet) void loadPet(next.pet);
    card.currentPetId = next.pet;
    if (card.isOpen) card.scheduleRefresh();
    // Un solo sottofondo alla volta: lo decide il processo principale; qui si segue (con qualche secondo di anteprima fuori dal focus).
    if (next.ambientSound !== previous.ambientSound) ambient.setSound(next.ambientSound, true);
    if (next.ambientVolume !== previous.ambientVolume) ambient.setVolume(next.ambientVolume, true);
    if (next.musicSource !== previous.musicSource) music.setSource(next.musicSource, true);
    else if (next.musicFolder !== previous.musicFolder) music.folderChanged();
    if (next.musicVolume !== previous.musicVolume) music.setVolume(next.musicVolume, true);
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
  api.onTimerState(onTimerState);
  api.onTimerEvent(onTimerEvent);
  api.onSpeakNow(() => { void speaker.sayRandom(); });
  api.onCardToggle((request) => card.toggle(request));
  api.onAskSubject((minutes) => { void askFocus(minutes); });
  api.onShowIntro(showIntro);
  api.onAskName(() => { void askName(); });
  api.onCardReopen(() => card.reopen());

  document.addEventListener("mousemove", onMouseMove);
  document.addEventListener("mousedown", onMouseDown);
  window.addEventListener("mouseup", onMouseUp);
  document.documentElement.addEventListener("mouseleave", () => { lastMouse = null; });
  // Tasto destro sul compagno: la scheda, di fianco a lui.
  document.addEventListener("contextmenu", (event) => {
    event.preventDefault();
    if (!view || card.isOpen || modals.isOpen || !visible) return;
    const point = localPoint(event);
    if (view.hitTest(point.x, point.y)) card.toggle({ anchor: null, toggle: true });
  });
  window.addEventListener("resize", onResize);

  if (api.selfTest) {
    window.__ff = {
      say: ((text?: string) => { if (text) speaker.say(text); else void speaker.sayRandom(); }) as () => void,
      pets: (() => PETS.map((p) => p.id)) as () => string[],
      state: (() => ({
        pet: view.pet.id, ...view.position, ...view.size, picked: view.isPickedUp, mirrored: view.isMirrored, drag: drag !== null,
        scene: sceneSize(), speaking: speaker.isSpeaking, growth: showingFocusGrowth, shiftedUp,
        clock: { shown: clock.isShown }, prompt: prompt.isShowing, timer: timerState,
      })) as () => unknown,
      hit: ((x: number, y: number) => view.hitTest(x - view.position.left, y - view.position.top)) as () => boolean,
      restImage: (() => restImageIndex(view.pet)) as () => number,
      askFocus: ((minutes: number) => { void askFocus(minutes); }) as () => void,
      showIntro: (() => showIntro()) as () => void,
      askName: (() => { void askName(); }) as () => void,
      askReflection: ((session: object) => reflection.ask(session as never)) as () => void,
      modalOpen: (() => modals.isOpen) as () => boolean,
      reflectionOpen: (() => reflection.isShowing) as () => boolean,
      openCard: ((page?: "timers") => card.toggle({ anchor: null, toggle: false, ...(page ? { page } : {}) })) as () => void,
      closeCard: (() => card.close()) as () => void,
      cardOpen: (() => card.isOpen) as () => boolean,
      breakAudio: (() => { (ambient as unknown as { options: { workletUrl: string } }).options.workletUrl = "ff://app/non-esiste.js"; }) as () => void,
      skipMusic: (() => music.seekNearEnd()) as () => void,
      audio: (() => ({
        ambient: { state: ambient.state, level: ambient.level(), sound: ambient.sound, volume: ambient.volume, focusActive: ambient.focusActive },
        music: { playing: music.playing, title: music.currentTitle, source: music.source, volume: music.volume },
      })) as () => unknown,
    };
  }
  speaker.start();
  tick();
  api.ready();
}

void start();
