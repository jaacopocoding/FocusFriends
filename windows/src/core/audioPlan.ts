// Le decisioni dei suoni, senza toccare l'audio: quando un sottofondo deve sentirsi, con che volume e con che dissolvenza, e in che
// ordine suonano i brani. Si prova da sole; i riproduttori nella pagina (renderer/audio) fanno solo quello che qui si decide.

import { shuffled } from "./tracks.ts";
import { NOISE_KINDS } from "./noise.ts";
import type { AmbientSound, MusicSource } from "./rules.ts";

/** Dissolvenza di accensione e spegnimento del suono ambiente e della musica, in secondi. */
export const FADE_SECONDS = 2;
/** Un cambio di volume si sente subito. */
export const QUICK_FADE_SECONDS = 0.25;
/** Quanto dura l'anteprima quando si sceglie un suono (o un volume) fuori da un focus, in millisecondi. */
export const AMBIENT_PREVIEW_MS = 3000;
export const MUSIC_PREVIEW_MS = 5000;
/** Dopo lo spegnimento (e la sua dissolvenza) il motore si ferma del tutto. */
export const AMBIENT_STOP_AFTER_MS = (FADE_SECONDS + 0.3) * 1000;

export interface AmbientPlan {
  /** Il suono deve sentirsi adesso. */
  wanted: boolean;
  /** Che rumore (0 = nessuno) e a che volume (0 = spento), con quanta dissolvenza. */
  kind: number;
  gain: number;
  fadeSeconds: number;
  /** Se è un'anteprima: dopo quanto si spegne da solo. */
  previewMs: number | null;
  /** Se si spegne: dopo quanto si può fermare il motore. */
  stopAfterMs: number | null;
}

/** Il suono ambiente è acceso (al volume scelto) solo se c'è un focus e un suono, o in anteprima. */
export function planAmbient(input: { sound: AmbientSound; volume: number; focusActive: boolean; previewing: boolean; quick?: boolean }): AmbientPlan {
  const wanted = input.sound !== "none" && (input.focusActive || input.previewing);
  if (!wanted) return { wanted, kind: NOISE_KINDS[input.sound], gain: 0, fadeSeconds: FADE_SECONDS, previewMs: null, stopAfterMs: AMBIENT_STOP_AFTER_MS };
  return {
    wanted, kind: NOISE_KINDS[input.sound], gain: input.volume,
    // Un cambio di volume si sente subito; l'accensione (e lo spegnimento) sfumano piano.
    fadeSeconds: input.quick ? QUICK_FADE_SECONDS : FADE_SECONDS,
    previewMs: input.previewing ? AMBIENT_PREVIEW_MS : null, stopAfterMs: null,
  };
}

/** La musica suona solo se c'è un focus (o in anteprima) e una sorgente. */
export function musicWanted(source: MusicSource, focusActive: boolean, previewing: boolean): boolean {
  return source !== "off" && (focusActive || previewing);
}

/** La coda dei brani: tutti, in ordine casuale, e il primo del giro nuovo non è mai quello appena suonato. */
export class MusicQueue {
  private queue: string[] = [];
  private last: string | null = null;
  private readonly random: () => number;

  constructor(random: () => number = Math.random) {
    this.random = random;
  }

  /** Il prossimo brano (null se non ce ne sono). `tracks` è l'elenco di adesso: a coda vuota si rimescola. */
  next(tracks: readonly string[]): string | null {
    if (this.queue.length === 0) this.queue = shuffled(tracks, this.last, this.random);
    const track = this.queue.shift() ?? null;
    if (track !== null) this.last = track;
    return track;
  }

  /** Una nuova scelta (un'altra sorgente, un'altra cartella) ricomincia da zero. */
  reset(): void {
    this.queue = [];
  }

  get remaining(): number { return this.queue.length; }
}
