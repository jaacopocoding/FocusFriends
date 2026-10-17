// Il contratto tra il processo principale e l'interfaccia (la pagina non tocca file né sistema: chiede con questi messaggi).

import type { CardData } from "../core/card.ts";
import type { Rating } from "../core/log.ts";
import type { PomodoroEvent, PomodoroSnapshot } from "../core/pomodoro.ts";
import type { AddTimerResult, AmbientSound, BackgroundChoice, Chattiness, MusicSource, TimerKind } from "../core/rules.ts";

/** Le preferenze che l'interfaccia deve conoscere. */
export interface SettingsSnapshot {
  pet: string;
  movement: boolean;
  phraseFrequency: Chattiness;
  askHowItWent: boolean;
  ambientSound: AmbientSound;
  ambientVolume: number;
  musicSource: MusicSource;
  /** La cartella della musica dell'utente (serve solo per accorgersi che è cambiata). */
  musicFolder: string | null;
  musicVolume: number;
}

/** Un brano dell'elenco: il numero serve per chiederne il file. */
export interface MusicTrack { id: number; title: string }
/** L'elenco dei brani di una sorgente; `version` cambia a ogni elenco nuovo. */
export interface MusicList { version: number; tracks: MusicTrack[] }

/** Dove aprire la scheda: sotto/sopra un rettangolo (l'icona nell'area di notifica, nelle coordinate della finestra), o di fianco al compagno. */
export type CardAnchor = { x: number; y: number; width: number; height: number } | null;

/** Una richiesta di aprire (o chiudere, se è già aperta) la scheda, e su quale pagina. */
export interface CardOpenRequest {
  anchor: CardAnchor;
  /** Se è già aperta la chiude (clic sull'icona), a meno che si chieda una pagina precisa. */
  toggle: boolean;
  page?: "timers";
}

/** Quello che si può fare dalla scheda (le stesse azioni del menu). */
export type CardCommand =
  | { name: "startFocus"; minutes: number; subject: string | null }
  | { name: "startBreak"; minutes: number }
  | { name: "stopTimer" }
  | { name: "addMinutes" }
  | { name: "togglePause" }
  | { name: "addNote"; text: string }
  | { name: "discardFocus" }
  | { name: "selectPet"; id: string }
  | { name: "showStats" }
  | { name: "cycleChattiness" }
  | { name: "toggleMovement" }
  | { name: "toggleAsk" }
  | { name: "cycleAmbient" }
  | { name: "cycleMusic" }
  | { name: "setMusicVolume"; value: number }
  | { name: "setAmbientVolume"; value: number }
  | { name: "setBackground"; choice: BackgroundChoice }
  | { name: "setBackgroundVolume"; value: number }
  | { name: "toggleVisibility" }
  | { name: "speak" }
  | { name: "removeTimer"; kind: TimerKind; minutes: number }
  | { name: "moreSettings" }
  | { name: "rateLast"; rating: Rating }
  | { name: "saveReflection"; sessionId: string; rating: Rating | null; note: string | null }
  | { name: "setName"; userName: string | null }
  | { name: "finishIntro"; userName: string | null; petId: string }
  | { name: "quit" };

/** Cosa mette a disposizione il ponte (`preload`) alla pagina, come `window.focusfriends`. */
export interface FocusFriendsApi {
  getSettings(): Promise<SettingsSnapshot>;
  onSettingsChanged(callback: (settings: SettingsSnapshot) => void): void;
  /** La prossima frase del mazzo del compagno. */
  nextPhrase(petId: string): Promise<string>;
  onVisibilityChanged(callback: (visible: boolean) => void): void;
  /** Com'è il timer adesso, e ogni volta che cambia qualcosa che si vede (a ogni secondo, o subito se succede qualcosa). */
  getTimerState(): Promise<PomodoroSnapshot>;
  onTimerState(callback: (state: PomodoroSnapshot) => void): void;
  /** Quello che il timer vuole far dire o fare al compagno: una frase, il suono, il «+5 minuti» che compare e scompare… */
  onTimerEvent(callback: (event: PomodoroEvent) => void): void;
  /** Il pulsante «+5 minuti» che compare a fine focus. */
  extendFocus(): void;
  /** I brani della sorgente scelta (inclusi o della cartella); i file si leggono da `ff://app/music/<versione>/<numero>`. */
  musicTracks(source: MusicSource): Promise<MusicList>;
  /** I dati della scheda (statistiche di oggi, timer salvati, impostazioni rapide, compagni bloccati). */
  getCardData(): Promise<CardData>;
  cardCommand(command: CardCommand): void;
  addCustomTimer(kind: TimerKind, minutes: number): Promise<AddTimerResult>;
  /**
   * Cosa serve alla finestra: ricevere tutti i clic (una scheda o una finestra di dialogo è aperta) e/o la tastiera (si sta
   * scrivendo). Altrimenti lascia passare i clic alle altre applicazioni e non prende il fuoco.
   */
  setInputMode(mode: { interactive: boolean; keyboard: boolean }): void;
  /** Il processo principale chiede di scegliere la materia prima di avviare un focus (dal menu dell'area di notifica). */
  onAskSubject(callback: (minutes: number) => void): void;
  /** «Il tuo nome…», dal menu dell'area di notifica. */
  onAskName(callback: () => void): void;
  /** La prima volta: la scheda di benvenuto (nome e compagno). */
  onShowIntro(callback: () => void): void;
  /** Un clic sull'icona nell'area di notifica: apre o chiude la scheda. */
  onCardToggle(callback: (request: CardOpenRequest) => void): void;
  /** Tornare indietro da un'altra finestra (o da un annullamento): la scheda si riapre dov'era. */
  onCardReopen(callback: () => void): void;
  /** «Fai parlare»: dall'area di notifica. */
  onSpeakNow(callback: () => void): void;
  /** La pagina è pronta a ricevere messaggi (prima di questo momento il processo principale li tiene da parte). */
  ready(): void;
  /** Solo nelle prove automatiche: la pagina espone dei comandi in `window.__ff`. */
  readonly selfTest: boolean;
}

export const CHANNEL = {
  getSettings: "settings:get",
  settingsChanged: "settings:changed",
  nextPhrase: "phrase:next",
  visibilityChanged: "overlay:visibility",
  getTimerState: "timer:get-state",
  timerState: "timer:state",
  timerEvent: "timer:event",
  timerExtend: "timer:extend",
  speakNow: "speech:now",
  musicTracks: "music:tracks",
  cardData: "card:data",
  cardCommand: "card:command",
  cardAddTimer: "card:add-timer",
  inputMode: "overlay:input-mode",
  askSubject: "focus:ask-subject",
  showIntro: "intro:show",
  askName: "name:ask",
  cardToggle: "card:toggle",
  cardReopen: "card:reopen",
  rendererReady: "renderer:ready",
} as const;
