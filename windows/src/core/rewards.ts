// Quando si sbloccano i compagni (FORMATI.md §4.1): il primo lo scegli tu, poi si guadagnano studiando.

/** I minuti di studio che fanno un «focus pieno». */
export const MINUTES_PER_FOCUS = 50;
/** Quanti focus pieni servono, per posizione: il primo è libero, il secondo 20, il terzo 50. */
export const THRESHOLDS = [0, 20, 50] as const;

/** Quanti focus pieni sono nei secondi di studio dati. */
export function focuses(totalSeconds: number): number {
  return Math.floor(Math.max(0, totalSeconds) / (MINUTES_PER_FOCUS * 60));
}

/** I focus che servono per la posizione `position` (dopo il terzo: altri 50 per ognuno). */
export function threshold(position: number): number {
  if (position < 0) return 0;
  const known = THRESHOLDS[position];
  if (known !== undefined) return known;
  return (THRESHOLDS[THRESHOLDS.length - 1] ?? 0) + (position - THRESHOLDS.length + 1) * 50;
}

/** L'ordine di sblocco: prima quello scelto, poi gli altri come stanno nell'elenco. */
export function order(first: string | null, all: readonly string[]): string[] {
  if (first === null || !all.includes(first)) return [...all];
  return [first, ...all.filter((id) => id !== first)];
}

/** I compagni meritati con `count` focus pieni. */
export function earned(first: string | null, all: readonly string[], count: number): Set<string> {
  const result = new Set<string>();
  order(first, all).forEach((id, position) => {
    if (count >= threshold(position)) result.add(id);
  });
  return result;
}

/** Quanti focus pieni servono per sbloccare `id` (0 se è il primo o non c'è). */
export function need(id: string, first: string | null, all: readonly string[]): number {
  const position = order(first, all).indexOf(id);
  return position < 0 ? 0 : threshold(position);
}

// ---- La pagina «Avatar» della scheda (AvatarRoster in CompanionRewards.swift): i compagni nell'ordine in cui si sbloccano e i testi che
// dicono quanto manca. Chi non è ancora sbloccato resta senza nome (si vede solo una sagoma sfocata), quindi questi testi non lo nominano mai.

export interface AvatarEntry {
  readonly id: string;
  /** Quanti focus pieni servono per sbloccarlo (0 = fin dall'inizio). */
  readonly need: number;
  readonly unlocked: boolean;
}

/** Al posto del nome di un compagno che non c'è ancora. */
export const HIDDEN_NAME = "???";

/** Gli avatar nell'ordine di sblocco; `isUnlocked` dice se uno c'è già (il profilo: conta anche la modalità sviluppatore). */
export function avatarEntries(first: string | null, all: readonly string[], isUnlocked: (id: string) => boolean): AvatarEntry[] {
  return order(first, all).map((id) => ({ id, need: need(id, first, all), unlocked: isUnlocked(id) }));
}

/** Il prossimo da sbloccare: il primo bloccato nell'ordine (è anche quello che chiede meno focus). */
export function nextAvatar<T extends AvatarEntry>(entries: readonly T[]): T | null {
  return entries.find((entry) => !entry.unlocked) ?? null;
}

/** Quanti focus pieni mancano (almeno uno: se sono già abbastanza, si sblocca al prossimo controllo). */
export function remainingFocuses(required: number, have: number): number {
  return Math.max(required - have, 1);
}

/** «ancora 18 focus pieni», «ancora 1 focus pieno». */
export function remainingText(required: number, have: number): string {
  const rest = remainingFocuses(required, have);
  return rest === 1 ? "ancora 1 focus pieno" : `ancora ${rest} focus pieni`;
}

/** «circa 15 h»: lo studio che manca, in ore (almeno una). */
export function hoursText(required: number, have: number): string {
  const minutes = remainingFocuses(required, have) * MINUTES_PER_FOCUS;
  return `circa ${Math.max(Math.round(minutes / 60), 1)} h`;
}

/** Quanta strada è fatta, da 0 a 1. */
export function avatarProgress(required: number, have: number): number {
  return required > 0 ? Math.min(Math.max(have / required, 0), 1) : 1;
}

/** Sotto la riga «Avatar» della scheda: «Prossimo compagno: ancora 18 focus pieni». */
export function nextAvatarLine(required: number, have: number): string {
  return `Prossimo compagno: ${remainingText(required, have)}`;
}

/** «2 con te · 2 da sbloccare». */
export function avatarCountLine(unlocked: number, locked: number): string {
  return locked > 0 ? `${unlocked} con te · ${locked} da sbloccare` : `${unlocked} con te`;
}
