// Le regole e i valori delle preferenze, senza toccare nessun file (si usano anche dalla pagina): gli elenchi di valori,
// la frequenza delle frasi, il volume, i limiti dei timer personalizzati, il quadrante e il ciclo della pausa lunga.

// ---- elenchi di valori

export const CHATTINESS = ["often", "sometimes", "rarely", "never"] as const;
export type Chattiness = (typeof CHATTINESS)[number];
export const CHATTINESS_TITLES: Record<Chattiness, string> = {
  often: "Spesso", sometimes: "Ogni tanto", rarely: "Raramente", never: "Mai",
};

/** Pausa (in secondi) tra una frase e la successiva; null = non parla mai di sua iniziativa. Durante un focus parla molto meno. */
export function chattinessInterval(chattiness: Chattiness, focusing: boolean): { min: number; max: number } | null {
  switch (chattiness) {
    case "never": return null;
    case "often": return focusing ? { min: 120, max: 240 } : { min: 20, max: 55 };
    case "sometimes": return focusing ? { min: 240, max: 480 } : { min: 40, max: 110 };
    case "rarely": return focusing ? { min: 600, max: 900 } : { min: 180, max: 360 };
  }
}

export const AMBIENT_SOUNDS = ["none", "rain", "brown", "wind"] as const;
export type AmbientSound = (typeof AMBIENT_SOUNDS)[number];
export const AMBIENT_TITLES: Record<AmbientSound, string> = {
  none: "Nessuno", rain: "Pioggia", brown: "Rumore marrone", wind: "Vento",
};

export const MUSIC_SOURCES = ["off", "bundled", "folder"] as const;
export type MusicSource = (typeof MUSIC_SOURCES)[number];

export const AMBIENT_DEFAULT_VOLUME = 0.25;
/** Più basso del normale: la musica deve restare un sottofondo. */
export const MUSIC_DEFAULT_VOLUME = 0.30;

/** Un volume da 0 a 1; se non è un numero finito vale quello di partenza. */
export function clampVolume(volume: number): number {
  if (!Number.isFinite(volume)) return AMBIENT_DEFAULT_VOLUME;
  return Math.min(Math.max(volume, 0), 1);
}

// ---- timer personalizzati

export type TimerKind = "focus" | "rest";
export const TIMER_TITLES: Record<TimerKind, string> = { focus: "Focus", rest: "Pausa" };
export const BUILT_IN_TIMERS: Record<TimerKind, readonly number[]> = { focus: [30, 50], rest: [5, 10] };
/** Durate ammesse, in minuti. */
export const ALLOWED_TIMERS: Record<TimerKind, { min: number; max: number }> = { focus: { min: 1, max: 180 }, rest: { min: 1, max: 60 } };
/** Quanti timer personalizzati per tipo: più di così il menu diventa una lista infinita. */
export const MAX_CUSTOM_PER_KIND = 6;

export type AddTimerResult =
  | { result: "added" }
  | { result: "outOfRange"; min: number; max: number }
  | { result: "alreadyExists" }
  | { result: "tooMany"; max: number };

// ---- il quadrante dei timer

/**
 * Dal punto in cui si trascina ai minuti. `fraction` è 0..<1 del giro, da mezzogiorno in senso orario. I minuti sono
 * multipli di `step`, tra `step` e `maxMinutes`; passando per mezzogiorno non si salta da un estremo all'altro.
 */
export function dialMinutes(fraction: number, previous: number, maxMinutes: number, step: number): number {
  const maxM = Math.max(maxMinutes, step);
  const before = previous / maxM;
  if (before > 0.75 && fraction < 0.25) return maxM;
  if (before < 0.25 && fraction > 0.75) return step;
  // (Swift arrotonda i casi a metà lontano da zero: Math.round li porta verso +∞, ma qui i valori sono positivi)
  const snapped = Math.round((fraction * maxM) / step) * step;
  return Math.min(Math.max(snapped, step), maxM);
}

/** La parte di giro da colorare per `minutes` (al massimo un giro intero). */
export function dialFilledFraction(minutes: number, maxMinutes: number): number {
  return Math.min(Math.max(minutes / Math.max(maxMinutes, 1), 0), 1);
}

// ---- il ciclo della pausa lunga

/** Quanti focus completati portano a una pausa lunga. */
export const FOCUSES_PER_CYCLE = 4;
/** La durata della pausa lunga, in minuti. */
export const LONG_BREAK_MINUTES = 15;
/** Se tra un focus completato e il successivo passa più di così, il ciclo ricomincia da capo. */
export const CYCLE_RESET_AFTER_MS = 2 * 3600 * 1000;

/** Dopo quattro focus completati di fila la pausa è lunga. Conta e basta: non sa niente di timer o finestre. */
export class BreakCycle {
  /** Quanti focus del ciclo in corso sono già stati completati (0...3). */
  completed = 0;
  private lastCompletion: number | null = null;

  /** Un focus è stato completato: conta, e dice se la pausa che segue è quella lunga. Dopo la pausa lunga il conteggio riparte da zero. */
  focusCompleted(at: number): boolean {
    if (this.lastCompletion !== null && at - this.lastCompletion > CYCLE_RESET_AFTER_MS) this.completed = 0;
    this.lastCompletion = at;
    this.completed += 1;
    if (this.completed >= FOCUSES_PER_CYCLE) {
      this.completed = 0;
      return true;
    }
    return false;
  }

  /** Quanti focus del ciclo risultano fatti in questo momento (se è passato troppo dall'ultimo, il ciclo è ricominciato). */
  done(at: number): number {
    if (this.lastCompletion !== null && at - this.lastCompletion > CYCLE_RESET_AFTER_MS) return 0;
    return this.completed;
  }

  /** Il ciclo ricomincia (per esempio quando si spegne la pausa lunga). */
  reset(): void {
    this.completed = 0;
    this.lastCompletion = null;
  }
}
