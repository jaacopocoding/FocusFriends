// I punti del giardino: un punto per ogni ora di studio, ma ogni minuto vale di più se la serie di giorni è lunga.
// Contano tutti i minuti, anche quelli dei focus interrotti. Si ricavano dal registro, come tutto il resto.

import type { StudySession } from "./log.ts";
import { analyzeStreak, startTime } from "./stats.ts";
import type { StreakResult } from "./stats.ts";
import { DAY_MS, startOfDay } from "./time.ts";

/** I minuti pesati che fanno un punto. */
export const MINUTES_PER_POINT = 60;
/** Da quanti giorni di fila, quanto vale ogni minuto. */
export const MULTIPLIERS: ReadonlyArray<{ days: number; factor: number }> = [
  { days: 1, factor: 1 }, { days: 3, factor: 1.25 }, { days: 7, factor: 1.5 }, { days: 14, factor: 2 },
];

export function multiplierForStreak(days: number): number {
  let factor = 1;
  for (const step of MULTIPLIERS) if (days >= step.days) factor = step.factor;
  return factor;
}

/** Quanto vale un minuto di studio oggi: se oggi si è già studiato è il valore raggiunto, altrimenti quello che avrebbe studiando adesso. */
export function multiplierToday(streak: StreakResult): number {
  return multiplierForStreak(streak.studiedToday ? streak.days : streak.days + 1);
}

/** I minuti di studio, ognuno moltiplicato per il valore della serie del suo giorno. */
export function weightedMinutes(sessions: readonly StudySession[], nowInstant: number, zone?: string): number {
  const streak = analyzeStreak(sessions, nowInstant, zone);
  const perDay = new Map<number, number>();
  for (const session of sessions) {
    const day = Math.floor(startOfDay(startTime(session, zone)) / DAY_MS);
    perDay.set(day, (perDay.get(day) ?? 0) + Math.max(session.seconds, 0) / 60);
  }
  let total = 0;
  for (const [day, minutes] of perDay) total += minutes * multiplierForStreak(streak.perDay.get(day) ?? 1);
  return total;
}

export function pointsForWeightedMinutes(minutes: number): number {
  return Math.max(Math.trunc(minutes / MINUTES_PER_POINT), 0);
}

/** I punti guadagnati in tutto. */
export function earnedPoints(sessions: readonly StudySession[], nowInstant: number, zone?: string): number {
  return pointsForWeightedMinutes(weightedMinutes(sessions, nowInstant, zone));
}

/** Quanto manca al prossimo punto, da 0 a 1 (quanto è già pieno). */
export function progressToNextPoint(minutes: number): number {
  return (Math.max(minutes, 0) % MINUTES_PER_POINT) / MINUTES_PER_POINT;
}

/** Quanti punti restano: quelli guadagnati meno quelli spesi (mai sotto zero). */
export function balance(earned: number, spent: number): number {
  return Math.max(earned - spent, 0);
}
