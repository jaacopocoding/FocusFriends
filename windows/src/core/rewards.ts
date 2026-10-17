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
