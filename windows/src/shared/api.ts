// Il contratto tra il processo principale e l'interfaccia (la pagina non tocca file né sistema: chiede con questi messaggi).

import type { PomodoroEvent, PomodoroSnapshot } from "../core/pomodoro.ts";
import type { Chattiness } from "../core/rules.ts";

/** Le preferenze che l'interfaccia deve conoscere. */
export interface SettingsSnapshot {
  pet: string;
  movement: boolean;
  phraseFrequency: Chattiness;
}

/** Cosa mette a disposizione il ponte (`preload`) alla pagina, come `window.focusfriends`. */
export interface FocusFriendsApi {
  getSettings(): Promise<SettingsSnapshot>;
  onSettingsChanged(callback: (settings: SettingsSnapshot) => void): void;
  /** Dice al processo principale se la finestra deve ricevere i clic (sopra il compagno) o lasciarli passare. */
  setInteractive(interactive: boolean): void;
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
  setInteractive: "overlay:set-interactive",
  nextPhrase: "phrase:next",
  visibilityChanged: "overlay:visibility",
  getTimerState: "timer:get-state",
  timerState: "timer:state",
  timerEvent: "timer:event",
  timerExtend: "timer:extend",
  speakNow: "speech:now",
  rendererReady: "renderer:ready",
} as const;
