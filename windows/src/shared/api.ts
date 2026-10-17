// Il contratto tra il processo principale e l'interfaccia (la pagina non tocca file né sistema: chiede con questi messaggi).

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
  /** Solo nelle prove automatiche: la pagina espone dei comandi in `window.__ff`. */
  readonly selfTest: boolean;
}

export const CHANNEL = {
  getSettings: "settings:get",
  settingsChanged: "settings:changed",
  setInteractive: "overlay:set-interactive",
  nextPhrase: "phrase:next",
  visibilityChanged: "overlay:visibility",
} as const;
