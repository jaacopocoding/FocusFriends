// Il motore del timer: una fase di focus, poi una pausa (Pomodoro.swift senza finestre). Non disegna niente e non
// suona niente: tiene il conto, scrive nel registro e dice cosa succede con degli eventi. Chi lo usa lo «fa battere»
// ogni 0,2 secondi con `tick()`. Il tempo passa sempre dall'orologio (`now`), così le prove lo comandano a piacere.

import type { SessionLog, StudySession } from "./log.ts";
import { BreakCycle, LONG_BREAK_MINUTES } from "./rules.ts";
import { cleanFocusNote, cleanSubject, FOCUS_NOTES_COUNT } from "./text.ts";
import { partsOf, wallOf } from "./time.ts";

export type Phase = "focus" | "rest";

/** Quanti minuti aggiunge il pulsante «+5 minuti». */
export const EXTENSION_MINUTES = 5;
/** Allo scadere del focus: per quanti secondi resta il pulsante prima che parta la pausa. */
export const GRACE_SECONDS = 10;
/** Fra due battiti (ogni 0,2 s) non passa mai tanto: se è successo il computer ha dormito (o l'app è rimasta ferma) e quel tempo non è studio. */
export const SLEEP_GAP_SECONDS = 10;
/** Per quanto l'orologio resta visibile dall'inizio di ogni fase. */
export const INTRO_MINUTES = 2;
/** Quando mancano meno di tanti minuti l'orologio resta sempre visibile. */
export const ALWAYS_VISIBLE_MINUTES = 5;
/** Quanto resta visibile dopo che il mouse esce dal personaggio, in secondi. */
export const HOVER_LINGER_SECONDS = 1;

export type PomodoroEvent =
  | { type: "say"; text: string }
  /** Il fumetto va tolto subito. */
  | { type: "dismissSpeech" }
  /** Il suono di fine focus (o di fine pausa). */
  | { type: "sound" }
  /** Comincia o finisce un focus (compresi i secondi del «+5 minuti» e la pausa a timer fermo): per il suono ambiente. */
  | { type: "focusActive"; active: boolean }
  /** Un focus è finito davvero (non fermato): il porcellino mangia la carota. */
  | { type: "focusCompleted" }
  /** La sessione appena salvata, per «com'è andata?»; `todoId` è la voce di «Da fare» da cui era partito il focus (null se non partiva da una). */
  | { type: "focusRecorded"; session: StudySession; todoId: string | null }
  /** Il timer si ferma o ne parte uno nuovo: la scheda «com'è andata?» non serve più. */
  | { type: "reset" }
  | { type: "graceBegan"; seconds: number }
  | { type: "graceEnded" };

export interface PomodoroDeps {
  log: SessionLog;
  /** L'istante, in millisecondi. */
  now: () => number;
  random?: () => number;
  cycle?: BreakCycle;
  /** La pausa lunga è accesa? */
  longBreakEnabled: () => boolean;
  /** Il compagno scelto adesso (resta registrato nella sessione). */
  petId: () => string;
  /** Il fuso per scrivere gli orari («09:00 – 09:50»); senza, quello del computer. */
  zone?: string;
  /** Cosa è successo nel giardino con questo focus: nella prima uscita per Windows non c'è (stringa vuota). */
  gardenLine?: (recorded: StudySession) => string;
}

/** Com'è il timer in questo momento: tutto quello che serve per disegnarlo. */
export interface PomodoroSnapshot {
  phase: Phase | null;
  /** «FOCUS», «PAUSA», «FERMO». */
  label: string;
  /** «MM:SS», arrotondato per eccesso: parte da 30:00 e finisce a 00:01. */
  remainingText: string;
  isPaused: boolean;
  /** Quanta parte della fase è passata (0…1). */
  progress: number;
  /** Per la crescita del compagno: quanta parte del focus è passata, o 1 dopo un «+5 minuti»; null se non c'è un focus. */
  growthProgress: number | null;
  /** I secondi di fase già passati e quelli che mancano (per decidere quando mostrare l'orologio). */
  elapsedSeconds: number;
  remainingSeconds: number;
  /** «09:00 – 09:50». */
  rangeText: string;
  focusMinutes: number;
  breakMinutes: number;
  subject: string | null;
  notes: string[];
  lastFocus: { minutes: number; subject: string | null; sessionId: string | null } | null;
  isLongBreak: boolean;
  /** Quanti focus del ciclo sono fatti (0…4), per «focus 2 di 4»; null se la pausa lunga è spenta. */
  cycleDone: number | null;
  /** Se il pulsante «+5 minuti» è sullo schermo: quanti secondi restano (e la barretta si svuota). */
  graceSecondsLeft: number | null;
}

/** L'orologio va mostrato: nei primi minuti di ogni fase, negli ultimi, e finché il mouse sta sul personaggio. */
export function clockWanted(snapshot: Pick<PomodoroSnapshot, "phase" | "elapsedSeconds" | "remainingSeconds">, hoverActive: boolean): boolean {
  if (snapshot.phase === null) return false;
  return snapshot.elapsedSeconds < INTRO_MINUTES * 60 || snapshot.remainingSeconds <= ALWAYS_VISIBLE_MINUTES * 60 || hoverActive;
}

export function formatRemaining(seconds: number): string {
  const total = Math.max(0, Math.ceil(seconds));
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}

/** «Hai studiato Anatomia per 50 minuti. Che bel lavoro!», con qualche variante. `garden` è la riga sul giardino (vuota nella prima uscita). */
export function focusFinishedMessage(
  options: { subject: string | null; studiedMinutes: number; breakMinutes: number; garden: string; longBreak: boolean },
  random: () => number = Math.random,
): string {
  const { subject, studiedMinutes, breakMinutes, longBreak } = options;
  const pick = (variants: string[]): string => variants[Math.floor(random() * variants.length)] ?? variants[0]!;
  // La riga sul giardino, se c'è, sta tra due frasi (niente doppi spazi se manca).
  const garden = options.garden === "" ? "" : ` ${options.garden}`;
  if (longBreak) {
    const about = subject === null ? "" : ` su ${subject}`;
    return pick([
      `Quattro focus di fila${about}: che costanza!${garden} Ti sei guadagnato una pausa lunga, ${breakMinutes} minuti.`,
      `Il quarto focus${about} è andato!${garden} Pausa lunga: ${breakMinutes} minuti per respirare davvero.`,
    ]);
  }
  if (subject === null) return `Focus finito!${garden} Ti sei meritato ${breakMinutes} minuti di pausa.`;
  return pick([
    `Hai studiato ${subject} per ${studiedMinutes} minuti. Che bel lavoro!${garden} Ora ${breakMinutes} minuti di pausa.`,
    `${subject}: ${studiedMinutes} minuti di concentrazione. Ottimo lavoro.${garden} Ora ${breakMinutes} minuti di pausa.`,
    `Ben fatto! ${studiedMinutes} minuti su ${subject}.${garden} Respira: ${breakMinutes} minuti di pausa.`,
  ]);
}

export class PomodoroEngine {
  private readonly deps: PomodoroDeps;
  private readonly cycle: BreakCycle;
  private readonly listeners: Array<(event: PomodoroEvent) => void> = [];

  private _phase: Phase | null = null;
  private phaseStart = 0;
  private endDate = 0;
  private lastTick = 0;
  private _isPaused = false;
  /** Quanto è rimasto fermo il focus in corso (ms): va tolto dal tempo trascorso (`endDate` si sposta insieme). */
  private pausedTotal = 0;
  private graceUntil: number | null = null;
  private extensions = 0;
  private plannedFocusMinutes = 0;
  private focusPet: string | null = null;
  private discarding = false;
  private _isLongBreak = false;
  private _subject: string | null = null;
  /** La voce di «Da fare» da cui è partito il focus in corso (solo in memoria: se l'app si chiude si perde). */
  private _todoId: string | null = null;
  private _notes: string[] = [];
  private _breakMinutes = 5;
  private _lastFocus: PomodoroSnapshot["lastFocus"] = null;

  constructor(deps: PomodoroDeps) {
    this.deps = deps;
    this.cycle = deps.cycle ?? new BreakCycle();
  }

  onEvent(listener: (event: PomodoroEvent) => void): void {
    this.listeners.push(listener);
  }

  private emit(event: PomodoroEvent): void {
    this.listeners.forEach((listener) => listener(event));
  }

  private say(text: string): void {
    this.emit({ type: "say", text });
  }

  private random(): number {
    return (this.deps.random ?? Math.random)();
  }

  get phase(): Phase | null { return this._phase; }
  get isRunning(): boolean { return this._phase !== null; }
  get isFocusPaused(): boolean { return this._isPaused; }
  get breakMinutes(): number { return this._breakMinutes; }

  private setPhase(next: Phase | null): void {
    const was = this._phase === "focus", now = next === "focus";
    this._phase = next;
    if (was !== now) this.emit({ type: "focusActive", active: now });
  }

  /** Il tempo davvero passato in questa fase, senza i momenti in cui è stata ferma (ms). */
  private activeElapsed(): number { return this.deps.now() - this.phaseStart - this.pausedTotal; }
  /** La durata della fase (prevista più i minuti aggiunti), senza i momenti in cui è stata ferma (ms). */
  private activeTotal(): number { return this.endDate - this.phaseStart - this.pausedTotal; }

  // ---- com'è adesso

  snapshot(): PomodoroSnapshot {
    const now = this.deps.now();
    const phase = this._phase;
    const remaining = phase === null ? 0 : Math.max(0, (this.endDate - now) / 1000);
    const total = this.activeTotal();
    const progress = phase !== null && total > 0 ? Math.min(Math.max(this.activeElapsed() / total, 0), 1) : 0;
    let growthProgress: number | null = null;
    if (phase === "focus") growthProgress = total > 0 && this.extensions === 0 ? this.activeElapsed() / total : 1;
    const enabled = this.deps.longBreakEnabled();
    return {
      phase,
      label: phase === null ? "" : this._isPaused ? "FERMO" : phase === "focus" ? "FOCUS" : "PAUSA",
      remainingText: formatRemaining(remaining),
      isPaused: this._isPaused,
      progress, growthProgress,
      elapsedSeconds: phase === null ? 0 : Math.max(0, this.activeElapsed() / 1000),
      remainingSeconds: remaining,
      rangeText: phase === null ? "" : `${this.clock(this.phaseStart)} – ${this.clock(this.endDate)}`,
      focusMinutes: this.plannedFocusMinutes,
      breakMinutes: this._breakMinutes,
      subject: this._subject,
      notes: [...this._notes],
      lastFocus: this._lastFocus ? { ...this._lastFocus } : null,
      isLongBreak: this._isLongBreak,
      cycleDone: !enabled ? null : this._isLongBreak ? 4 : this.cycle.done(now),
      graceSecondsLeft: this.graceUntil === null ? null : Math.max(0, (this.graceUntil - now) / 1000),
    };
  }

  private clock(instantMs: number): string {
    const p = partsOf(wallOf(instantMs, this.deps.zone));
    return `${String(p.hour).padStart(2, "0")}:${String(p.minute).padStart(2, "0")}`;
  }

  // ---- comandi

  startFocus(minutes: number, subject: string | null = null, todoId: string | null = null): void {
    this.emit({ type: "reset" });
    this.recordFocus(false);       // se ce n'era uno in corso, finisce qui
    this.endGrace();
    this.extensions = 0;
    this._lastFocus = null;
    this._notes = [];
    this._subject = cleanSubject(subject);
    this._todoId = todoId;
    this.plannedFocusMinutes = minutes;
    this.focusPet = this.deps.petId();
    this.begin("focus", minutes);
    this.deps.log.beginInProgress({
      start: this.phaseStart, plannedMinutes: minutes, subject: this._subject, pet: this.focusPet,
    });
    this.say(this._subject !== null ? `Focus di ${minutes} minuti su ${this._subject}: si parte!` : `Focus di ${minutes} minuti: si parte!`);
  }

  /** Avvia subito una pausa e ricorda la durata per quelle automatiche dopo il focus. */
  startBreak(minutes: number): void {
    this.recordFocus(false);
    this.endGrace();
    this.extensions = 0;
    this._lastFocus = null;
    this._subject = null;
    this._todoId = null;
    this._breakMinutes = minutes;
    this.begin("rest", minutes);
    this.say(`Pausa di ${minutes} minuti: stacca un attimo.`);
  }

  /** Se un focus è in corso lo mette nel registro (completo o interrotto) e toglie il segno «in corso». Ritorna la sessione salvata, se era lunga abbastanza da contare. */
  private recordFocus(completed: boolean): StudySession | null {
    if (this._phase !== "focus") return null;
    if (this.discarding) {
      this.deps.log.finishInProgress();
      return null;
    }
    // Se il tempo era già scaduto (il pulsante «+5 minuti» era sullo schermo) il focus è completo.
    const isComplete = completed || this.graceUntil !== null;
    const planned = this.plannedFocusMinutes;
    const seconds = isComplete ? Math.trunc(this.activeTotal() / 1000) : Math.min(Math.trunc(this.activeElapsed() / 1000), planned * 60);
    const session = this.deps.log.add({
      start: this.phaseStart, seconds, plannedMinutes: planned, completed: isComplete,
      subject: this._subject, pet: this.focusPet, notes: this._notes,
    });
    this.deps.log.finishInProgress();
    return session;
  }

  /** Per la chiusura dell'app: un focus ancora in corso viene salvato come interrotto. */
  recordInterruptedFocusOnQuit(): void {
    this.recordFocus(false);
  }

  stop(): void {
    this.emit({ type: "reset" });
    this.recordFocus(false);
    this.endGrace();
    this.extensions = 0;
    this._lastFocus = null;
    this._isPaused = false;
    this._isLongBreak = false;
    this.pausedTotal = 0;
    this._notes = [];
    this._subject = null;
    this._todoId = null;
    this.setPhase(null);
  }

  private begin(phase: Phase, minutes: number): void {
    const wasPaused = this._isPaused;
    this._isPaused = false;
    this.pausedTotal = 0;
    this._isLongBreak = false;
    this.setPhase(phase);
    if (wasPaused && phase === "focus") this.emit({ type: "focusActive", active: true });
    this.phaseStart = this.deps.now();
    this.lastTick = this.phaseStart;          // il primo battito non deve vedere come «salto» il tempo passato da un'altra fase
    this.endDate = this.phaseStart + minutes * 60_000;
  }

  /** Un battito (ogni 0,2 secondi). */
  tick(): void {
    const now = this.deps.now();
    if (this._phase === null) return;
    const gap = now - this.lastTick;
    if (this._isPaused) {
      // Il tempo non scorre: la fine si sposta in avanti insieme all'orologio.
      this.endDate += gap;
      this.pausedTotal += gap;
    } else if (this._phase === "focus" && this.graceUntil === null && gap > SLEEP_GAP_SECONDS * 1000) {
      // Il computer ha dormito durante il focus: come se fosse stato fermo. Altrimenti, al risveglio, il tempo risulterebbe
      // scaduto e le ore di sonno finirebbero nel registro come studio completato.
      this.endDate += gap;
      this.pausedTotal += gap;
      this.deps.log.updateInProgressPause(Math.trunc(this.pausedTotal / 1000), null);
    }
    this.lastTick = now;
    if (this.endDate - now <= 0) {
      // Il focus è scaduto: qualche secondo per aggiungere minuti, poi finisce e parte la pausa.
      if (this._phase === "focus") {
        if (this.graceUntil === null) {
          this.beginGrace();
          return;
        }
        if (now >= this.graceUntil) this.finish();
        return;
      }
      this.finish();
      return;
    }
    if (this._phase === "focus") this.deps.log.heartbeat(now);
  }

  /** Aggiunge `minutes` alla fase in corso: al focus (anche prima che scada) o alla pausa. */
  addMinutes(minutes: number = EXTENSION_MINUTES): void {
    if (this._phase === "focus") {
      if (this.graceUntil !== null) {
        this.extendFocus();
        return;
      }
      this.extensions += 1;
      this.plannedFocusMinutes += minutes;
      this.endDate += minutes * 60_000;
      this.deps.log.beginInProgress({
        start: this.phaseStart, plannedMinutes: this.plannedFocusMinutes, subject: this._subject, pet: this.focusPet, notes: this._notes,
      });
    } else if (this._phase === "rest") {
      this.endDate += minutes * 60_000;
    }
  }

  /** «Ferma» / «Riprendi»: il conto alla rovescia si ferma e il focus resta aperto. Se il tempo è già scaduto non c'è niente da fermare: il focus si chiude. */
  toggleFocusPause(): void {
    if (this._phase !== "focus") return;
    const now = this.deps.now();
    if (this._isPaused) {
      const gap = now - this.lastTick;
      this.endDate += gap;
      this.pausedTotal += gap;
      this.lastTick = now;
      this._isPaused = false;
      this.deps.log.updateInProgressPause(Math.trunc(this.pausedTotal / 1000), null);
      this.emit({ type: "focusActive", active: true });
      this.say("Si riparte!");
    } else if (this.graceUntil !== null) {
      this.stop();
    } else {
      this.lastTick = now;
      this._isPaused = true;
      this.deps.log.updateInProgressPause(Math.trunc(this.pausedTotal / 1000), this.lastTick);
      this.emit({ type: "focusActive", active: false });
      this.say("Timer fermo. Riprendi quando sei pronto.");
    }
  }

  /** Una nota scritta durante il focus (si salva subito, così non si perde). */
  addNote(text: string): void {
    if (this._phase !== "focus") return;
    const clean = cleanFocusNote(text);
    if (clean === null || this._notes.length >= FOCUS_NOTES_COUNT) return;
    this._notes.push(clean);
    this.deps.log.updateInProgressNotes(this._notes);
  }

  /** Elimina il focus in corso: non viene registrato. */
  discardFocus(): void {
    if (this._phase !== "focus") return;
    this.discarding = true;
    this.stop();
    this.discarding = false;
    this.say("Focus eliminato: non resta traccia.");
  }

  // ---- «+5 minuti»

  /** Il tempo è scaduto: suona, e per qualche secondo c'è il pulsante per aggiungere minuti. */
  private beginGrace(): void {
    this.graceUntil = this.deps.now() + GRACE_SECONDS * 1000;
    this.emit({ type: "sound" });
    this.emit({ type: "dismissSpeech" });
    this.emit({ type: "graceBegan", seconds: GRACE_SECONDS });
  }

  private endGrace(): void {
    if (this.graceUntil === null) return;
    this.graceUntil = null;
    this.emit({ type: "graceEnded" });
  }

  /** Il pulsante: altri minuti a partire da adesso, e il focus continua. */
  extendFocus(): void {
    if (this._phase !== "focus" || this.graceUntil === null) return;
    this.extensions += 1;
    this.plannedFocusMinutes += EXTENSION_MINUTES;
    this.endDate = this.deps.now() + EXTENSION_MINUTES * 60_000;
    this.endGrace();
    this.deps.log.beginInProgress({
      start: this.phaseStart, plannedMinutes: this.plannedFocusMinutes, subject: this._subject, pet: this.focusPet, notes: this._notes,
    });
    const variants = [
      `Altri ${EXTENSION_MINUTES} minuti: finisci con calma l'esercizio.`,
      `Va bene, ${EXTENSION_MINUTES} minuti in più. Io resto qui.`,
      `Ancora ${EXTENSION_MINUTES} minuti: ce la fai.`,
    ];
    this.say(variants[Math.floor(this.random() * variants.length)] ?? variants[0]!);
  }

  private finish(): void {
    const finished = this._phase;
    if (finished === null) return;
    // Se è finito il tempo del focus il suono è già partito (all'inizio dei secondi di attesa).
    if (this.graceUntil === null) this.emit({ type: "sound" });
    this.endGrace();

    if (finished === "focus") {
      const enabled = this.deps.longBreakEnabled();
      const now = this.deps.now();
      const longBreak = enabled && this.cycle.focusCompleted(now);
      if (!enabled) this.cycle.reset();
      const breakLength = longBreak ? Math.max(LONG_BREAK_MINUTES, this._breakMinutes) : this._breakMinutes;
      const studied = this.plannedFocusMinutes;
      const finishedSubject = this._subject;
      const finishedTodo = this._todoId;
      const recorded = this.recordFocus(true);
      this._lastFocus = { minutes: studied, subject: finishedSubject, sessionId: recorded?.id ?? null };
      this._notes = [];
      this._subject = null;
      this._todoId = null;
      const garden = recorded !== null && this.deps.gardenLine ? this.deps.gardenLine(recorded) : "";
      this.begin("rest", breakLength);
      this._isLongBreak = longBreak;
      this.say(focusFinishedMessage({ subject: finishedSubject, studiedMinutes: studied, breakMinutes: breakLength, garden, longBreak },
        () => this.random()));
      this.emit({ type: "focusCompleted" });
      if (recorded !== null) this.emit({ type: "focusRecorded", session: recorded, todoId: finishedTodo });
    } else {
      this.stop();
      this.say("Pausa finita! Pronto per un altro giro?");
    }
  }
}
