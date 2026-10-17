// Dà vita ai personaggi che camminano: passeggiate in orizzontale con pause, ogni tanto uno spuntino o un pisolino, i
// saltelli, e il mangiare a fine focus. Muove solo la posizione orizzontale: se lo trascini in alto, cammina a quell'altezza.
// È il Walker.swift del Mac senza la finestra: ogni passo (`tick`) riceve com'è la situazione e dice cosa cambiare.

import type { PetData } from "./pets.ts";
import { restStage } from "./pets.ts";

type State =
  | { kind: "resting"; until: number }
  | { kind: "walking"; until: number; direction: 1 | -1 }
  | { kind: "eating"; until: number }
  | { kind: "sleeping"; start: number; until: number }
  | { kind: "popcorning"; until: number };

// Camminata
/** Punti al secondo. */
export const SPEED = 42;
/** Tolleranza (in secondi) sul cambio di fotogramma: con un passo di esattamente due tick del timer il cambio cadrebbe sul bordo. */
const STEP_SLACK = 0.005;
export const EDGE_MARGIN = 6;
const WALK_DURATION = [3, 8] as const;
const REST_DURATION = [4, 10] as const;

// Momenti casuali: dopo una pausa può mangiare, dormire, saltellare, oppure ripartire.
const EAT_CHANCE = 0.3;
const SLEEP_CHANCE = 0.15;
const POPCORN_CHANCE = 0.12;
const POPCORN_DURATION = [3, 6] as const;
const EAT_DURATION = [6, 12] as const;
const SLEEP_DURATION = [12, 30] as const;
const CHEW_INTERVAL = 0.28;
const BREATH_INTERVAL = 0.9;
/** Assopito, prima e dopo il sonno. */
const DROWSY_SECONDS = 1.5;
const AFTER_ACTIVITY_PAUSE = 1.5;

/** Ritmo normale (fluido) e ritmo a riposo, quando non c'è niente da animare (nascosto, o fermo dal menu), in millisecondi. */
export const ACTIVE_INTERVAL_MS = 1000 / 30;
export const IDLE_INTERVAL_MS = 1000;

export interface WalkerInput {
  /** L'istante, in millisecondi. */
  now: number;
  pet: PetData;
  /** Il personaggio è visibile (non nascosto dall'area di notifica). */
  visible: boolean;
  /** L'utente può fermare la passeggiata dal menu (In movimento / Fermo). */
  movementEnabled: boolean;
  /** Lo si sta sollevando o trascinando col mouse. */
  dragging: boolean;
  /** Sta dicendo una frase. */
  speaking: boolean;
  /** Durante un focus «cresce» sul posto (Ciccio nel nido): niente passi. */
  showingFocusGrowth: boolean;
  /** Dov'è adesso il lato sinistro della finestra, in punti. */
  x: number;
  /** Larghezza della finestra. */
  width: number;
  /** I bordi dell'area di lavoro dello schermo dov'è. */
  screenMinX: number;
  screenMaxX: number;
}

/** Cosa cambiare: quello che manca non va toccato. */
export interface WalkerAction {
  pose?: number;
  facingRight?: boolean;
  x?: number;
  sleepMarks?: boolean;
}

const roundHalfAway = (value: number): number => (value < 0 ? -Math.round(-value) : Math.round(value));

export class Walker {
  private state: State;
  private lastTick: number;
  private stepClock = 0;
  /** Appena finito di mangiare o dormire: la prossima scelta è per forza una camminata. */
  private justRested = false;
  /** Posizione orizzontale «esatta»: la finestra sta su punti interi, e sommando passi di 1,4 punti la velocità reale verrebbe falsata. */
  private exactX: number | null = null;
  private appliedX = 0;
  private readonly random: () => number;

  constructor(now: number, random: () => number = Math.random) {
    this.random = random;
    this.state = { kind: "resting", until: now + 2000 };
    this.lastTick = now;
  }

  private between(range: readonly [number, number]): number {
    return range[0] + this.random() * (range[1] - range[0]);
  }

  /** Ogni quanto serve chiamare `tick`: spesso mentre si muove, una volta al secondo se non c'è niente da animare. */
  intervalMs(pet: PetData, visible: boolean, movementEnabled: boolean): number {
    return pet.walks && visible && movementEnabled ? ACTIVE_INTERVAL_MS : IDLE_INTERVAL_MS;
  }

  private get isEatingOrSleeping(): boolean {
    return this.state.kind === "eating" || this.state.kind === "sleeping" || this.state.kind === "popcorning";
  }

  /** A fine focus: se il personaggio mangia (il porcellino), mangia subito la carota cresciuta. */
  eatNow(input: Pick<WalkerInput, "now" | "pet" | "visible" | "dragging">, hasFocusGrowthArt: boolean): void {
    const { pet } = input;
    if (!pet.eatsWhenFocusCompletes || pet.eatFrames.length === 0 || !hasFocusGrowthArt || !input.visible || input.dragging) return;
    this.stepClock = 0;
    this.state = { kind: "eating", until: input.now + this.between([7, 10]) * 1000 };
  }

  /** Un passo del ciclo. */
  tick(input: WalkerInput): WalkerAction {
    const { now, pet } = input;
    const dt = Math.min((now - this.lastTick) / 1000, 0.1);       // dopo uno stop (sleep) non faccio salti
    this.lastTick = now;

    // Non cammina o è nascosto: non c'è niente da animare.
    if (!pet.walks || !input.visible) return { sleepMarks: false };
    // Durante un focus il personaggio «cresce» sul posto: niente passi.
    if (input.showingFocusGrowth) {
      this.delay(dt);
      return { sleepMarks: false };
    }
    // Mentre lo trascini: posa a riposo, e le fasi in corso restano in attesa.
    if (input.dragging) {
      this.delay(dt);
      return { pose: restStage(pet), sleepMarks: false };
    }
    // «Fermo» dal menu: resta nella posa a riposo (e quando riparte aspetta un attimo).
    if (!input.movementEnabled) {
      this.state = { kind: "resting", until: now + AFTER_ACTIVITY_PAUSE * 1000 };
      return { pose: restStage(pet), sleepMarks: false };
    }
    // Sta fermo mentre parla, ma se mangia, dorme o salta resta nella sua posa.
    if (input.speaking && !this.isEatingOrSleeping) {
      this.delay(dt);
      return { pose: pet.talkFrame ?? restStage(pet) };
    }

    const state = this.state;
    switch (state.kind) {
      case "resting": {
        const action: WalkerAction = { pose: restStage(pet), sleepMarks: false };
        if (now >= state.until) Object.assign(action, this.chooseNext(input));
        return action;
      }
      case "walking":
        return this.walk(input, dt, state.until, state.direction);
      case "eating": {
        // Resta dov'è e cicla i fotogrammi della carota.
        this.stepClock += dt;
        const frames = pet.eatFrames;
        const action: WalkerAction = { pose: frames[Math.floor(this.stepClock / CHEW_INTERVAL) % frames.length]! };
        if (now >= state.until) Object.assign(action, this.finishActivity(pet, now));
        return action;
      }
      case "popcorning": {
        // Saltelli di gioia: resta dov'è e ripete il salto.
        this.stepClock += dt;
        const frames = pet.popcornFrames;
        const action: WalkerAction = { pose: frames[Math.floor((this.stepClock + STEP_SLACK) / pet.popcornInterval) % frames.length]! };
        if (now >= state.until) Object.assign(action, this.finishActivity(pet, now));
        return action;
      }
      case "sleeping": {
        // Assopito, poi respira piano (con gli «Zzz»), poi di nuovo assopito prima di svegliarsi.
        const t = (now - state.start) / 1000;
        const remaining = (state.until - now) / 1000;
        const action: WalkerAction = {};
        if (pet.sleepIntroFrame !== null && (t < DROWSY_SECONDS || remaining < DROWSY_SECONDS)) {
          action.pose = pet.sleepIntroFrame;
          action.sleepMarks = false;
        } else {
          const frames = pet.sleepFrames;
          action.pose = frames[Math.floor((t - DROWSY_SECONDS) / BREATH_INTERVAL) % frames.length]!;
          action.sleepMarks = true;
        }
        if (now >= state.until) Object.assign(action, this.finishActivity(pet, now));
        return action;
      }
    }
  }

  /** Sposta in avanti il termine della fase attuale (mentre parla o lo trascini non «consuma» tempo). */
  private delay(dt: number): void {
    const ms = dt * 1000;
    const state = this.state;
    if (state.kind === "sleeping") this.state = { ...state, start: state.start + ms, until: state.until + ms };
    else this.state = { ...state, until: state.until + ms };
  }

  /** Finita una pausa: a sorte mangia, dorme, fa il popcorning o riparte. Dopo una di queste soste riparte per forza a camminare. */
  private chooseNext(input: WalkerInput): WalkerAction {
    const { now, pet } = input;
    let roll = this.random();
    const canRest = !this.justRested;
    let choice = "walk";
    const options: Array<[string, number, boolean]> = [
      ["eat", EAT_CHANCE, pet.eatFrames.length > 0],
      ["sleep", SLEEP_CHANCE, pet.sleepFrames.length > 0],
      ["popcorn", POPCORN_CHANCE, pet.popcornFrames.length > 0],
    ];
    for (const [name, chance, available] of options) {
      if (!canRest || !available) continue;
      if (roll < chance) { choice = name; break; }
      roll -= chance;
    }
    switch (choice) {
      case "eat":
        this.state = { kind: "eating", until: now + this.between(EAT_DURATION) * 1000 };
        this.stepClock = 0;
        return {};
      case "sleep":
        this.state = { kind: "sleeping", start: now, until: now + this.between(SLEEP_DURATION) * 1000 };
        return {};
      case "popcorn":
        this.state = { kind: "popcorning", until: now + this.between(POPCORN_DURATION) * 1000 };
        this.stepClock = 0;
        return {};
      default: {
        this.justRested = false;
        const direction = this.chooseDirection(input);
        this.state = { kind: "walking", until: now + this.between(WALK_DURATION) * 1000, direction };
        this.stepClock = 0;
        return { facingRight: direction > 0 };
      }
    }
  }

  private finishActivity(pet: PetData, now: number): WalkerAction {
    this.state = { kind: "resting", until: now + AFTER_ACTIVITY_PAUSE * 1000 };
    this.justRested = true;
    return { pose: restStage(pet), sleepMarks: false };
  }

  private walk(input: WalkerInput, dt: number, until: number, startDirection: 1 | -1): WalkerAction {
    const { now, pet } = input;
    let direction = startDirection;
    const minX = input.screenMinX + EDGE_MARGIN;
    const maxX = input.screenMaxX - input.width - EDGE_MARGIN;

    // Se qualcun altro ha spostato la finestra (l'utente col mouse), riparto da lì.
    if (this.exactX === null || Math.abs(input.x - this.appliedX) > 1.5) this.exactX = input.x;

    let x = this.exactX + direction * SPEED * dt;
    if (x <= minX) { x = minX; direction = 1; }
    if (x >= maxX) { x = maxX; direction = -1; }
    this.exactX = x;
    const applied = roundHalfAway(x);
    this.appliedX = applied;

    // Passi: i fotogrammi del cammino si ripetono in ciclo.
    this.stepClock += dt;
    const frames = pet.walkFrames;
    let pose = frames[Math.floor((this.stepClock + STEP_SLACK) / pet.stepInterval) % frames.length]!;

    if (now >= until) {
      this.state = { kind: "resting", until: now + this.between(REST_DURATION) * 1000 };
      pose = restStage(pet);
    } else {
      this.state = { kind: "walking", until, direction };
    }
    return { sleepMarks: false, facingRight: direction > 0, x: applied, pose };
  }

  /** Direzione a caso, ma verso il centro se è vicino a un bordo. */
  private chooseDirection(input: WalkerInput): 1 | -1 {
    const room = input.screenMaxX - input.screenMinX - input.width;
    const position = (input.x - input.screenMinX) / Math.max(room, 1);     // 0 = a sinistra, 1 = a destra
    if (position < 0.15) return 1;
    if (position > 0.85) return -1;
    return this.random() < 0.5 ? 1 : -1;
  }
}
