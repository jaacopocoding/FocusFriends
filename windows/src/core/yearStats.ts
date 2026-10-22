// La scheda «Anno» delle statistiche (YearStats.swift): una mappa con un quadratino per giorno (come i contributi di GitHub) e l'andamento
// per settimana, di tutte le materie o di una sola. Si ricava tutto dal registro: niente da salvare. Stesse regole della versione per Mac.

import type { StudySession } from "./log.ts";
import { analyzeStreak, startTime } from "./stats.ts";
import type { Period, Summary } from "./stats.ts";
import { NO_SUBJECT, subjectKey } from "./text.ts";
import { DAY_MS, startOfDay, startOfMonth, startOfWeek } from "./time.ts";
import type { Wall } from "./time.ts";

// ---- i giorni della mappa

/**
 * Fino a quanti secondi di studio un giorno ha il livello 1, 2 e 3 (da 3 ore in su è il 4): meno di 30 minuti, meno di 90, meno di 180.
 * Le soglie sono fisse, non relative ai giorni migliori: un giorno da due ore ha lo stesso colore in tutti gli anni.
 */
export const LEVEL_LIMITS: readonly number[] = [30 * 60, 90 * 60, 180 * 60];

/** Il colore del giorno, da 0 (niente) a 4 (tanto). */
export function level(seconds: number): number {
  if (seconds <= 0) return 0;
  if (seconds < LEVEL_LIMITS[0]!) return 1;
  if (seconds < LEVEL_LIMITS[1]!) return 2;
  if (seconds < LEVEL_LIMITS[2]!) return 3;
  return 4;
}

export interface YearDay {
  start: Wall;
  seconds: number;
  focusCount: number;
  level: number;
}

/** Un elemento per ogni giorno del periodo (anche senza studio), in ordine. Una sessione va al giorno in cui è iniziata. */
export function yearDays(sessions: readonly StudySession[], period: Period, zone?: string): YearDay[] {
  const seconds = new Map<Wall, number>();
  const focus = new Map<Wall, number>();
  for (const session of sessions) {
    const at = startTime(session, zone);
    if (at < period.start || at >= period.end) continue;
    const day = startOfDay(at);
    seconds.set(day, (seconds.get(day) ?? 0) + session.seconds);
    focus.set(day, (focus.get(day) ?? 0) + 1);
  }
  const days: YearDay[] = [];
  for (let cursor = startOfDay(period.start); cursor < period.end; cursor += DAY_MS) {
    const total = seconds.get(cursor) ?? 0;
    days.push({ start: cursor, seconds: total, focusCount: focus.get(cursor) ?? 0, level: level(total) });
  }
  return days;
}

// ---- la griglia

/** Il lunedì della settimana in cui cade il primo giorno del periodo: da lì parte la prima colonna. */
function firstColumnStart(period: Period): Wall {
  return startOfWeek(period.start);
}

/** Dove sta un giorno nella griglia: una colonna per settimana (da lunedì) e una riga per giorno (lunedì = 0). */
export function cellOf(day: Wall, period: Period): { column: number; row: number } {
  const offset = Math.round((startOfDay(day) - firstColumnStart(period)) / DAY_MS);
  return { column: Math.floor(offset / 7), row: offset % 7 };
}

/** Quante colonne ha la griglia (53, o 54 in un anno bisestile che comincia di domenica). */
export function columnsOf(period: Period): number {
  return cellOf(period.end - DAY_MS, period).column + 1;
}

export interface MonthMark {
  /** 1...12 */
  month: number;
  column: number;
}

/** In quale colonna comincia ogni mese, per scriverne il nome sopra la griglia. */
export function monthStarts(period: Period): MonthMark[] {
  const marks: MonthMark[] = [];
  for (let cursor = startOfDay(period.start); cursor < period.end; cursor += DAY_MS) {
    const at = new Date(cursor);
    if (at.getUTCDate() === 1 || marks.length === 0) marks.push({ month: at.getUTCMonth() + 1, column: cellOf(cursor, period).column });
  }
  return marks;
}

// ---- i tre numeri

export interface Highlights {
  /** In quanti giorni hai studiato. */
  studiedDays: number;
  /** La serie di giorni di fila più lunga raggiunta nell'anno (con il giorno di ghiaccio, come la serie di oggi). */
  longestStreak: number;
  /** Il giorno con più studio (a pari merito, il primo): `start` è il giorno. */
  bestDay: { start: Wall; seconds: number } | null;
  /** Il mese con più studio (a pari merito, il primo): `start` è il suo primo giorno. */
  bestMonth: { start: Wall; seconds: number } | null;
}

export function highlights(sessions: readonly StudySession[], period: Period, nowInstant: number, zone?: string): Highlights {
  const studied = yearDays(sessions, period, zone).filter((day) => day.seconds > 0);
  const result: Highlights = { studiedDays: studied.length, longestStreak: 0, bestDay: null, bestMonth: null };
  for (const day of studied) {
    if (result.bestDay === null || day.seconds > result.bestDay.seconds) result.bestDay = { start: day.start, seconds: day.seconds };
  }
  const perMonth = new Map<number, number>();
  for (const day of studied) perMonth.set(startOfMonth(day.start), (perMonth.get(startOfMonth(day.start)) ?? 0) + day.seconds);
  for (const [start, seconds] of [...perMonth].sort((a, b) => a[0] - b[0])) {
    if (result.bestMonth === null || seconds > result.bestMonth.seconds) result.bestMonth = { start, seconds };
  }
  for (const [dayNumber, count] of analyzeStreak(sessions, nowInstant, zone).perDay) {
    const start = dayNumber * DAY_MS;
    if (start >= period.start && start < period.end) result.longestStreak = Math.max(result.longestStreak, count);
  }
  return result;
}

// ---- l'andamento per settimana

/** Quante materie al massimo si possono scegliere per l'andamento (oltre a «Tutte»). */
export const MAX_TREND_SUBJECTS = 5;
/** Con meno settimane con studio di queste l'andamento non si mostra: non c'è un andamento da vedere. */
export const MINIMUM_TREND_WEEKS = 4;

/** Le materie tra cui scegliere (la scrittura più recente, le più studiate dell'anno), senza «Senza materia». Con meno di due non c'è niente da scegliere. */
export function trendSubjects(summary: Summary): string[] {
  const named = summary.bySubject.filter((row) => row.subject !== NO_SUBJECT).map((row) => row.subject);
  return named.length < 2 ? [] : named.slice(0, MAX_TREND_SUBJECTS);
}

export interface WeekBucket {
  start: Wall;
  seconds: number;
}

/**
 * Le settimane (da lunedì) del periodo fino a `through` (un'ora sull'orologio), con i secondi di studio di una materia (le scritture diverse
 * della stessa materia contano insieme) o di tutte (`subject` null). La prima e l'ultima settimana possono essere tagliate dai bordi dell'anno.
 */
export function weeklyTrend(sessions: readonly StudySession[], period: Period, subject: string | null, through: Wall, zone?: string): WeekBucket[] {
  const key = subject === null ? null : subjectKey(subject);
  const wanted = sessions
    .map((session) => ({ session, at: startTime(session, zone) }))
    .filter(({ session, at }) => at >= period.start && at < period.end && (key === null || (session.subject !== undefined && subjectKey(session.subject) === key)));
  const limit = Math.min(period.end, through);
  const weeks: WeekBucket[] = [];
  for (let cursor = firstColumnStart(period); cursor < limit; cursor += 7 * DAY_MS) {
    const seconds = wanted.filter(({ at }) => at >= cursor && at < cursor + 7 * DAY_MS).reduce((total, { session }) => total + session.seconds, 0);
    weeks.push({ start: cursor, seconds });
  }
  return weeks;
}

/** Ha senso mostrare l'andamento? (almeno `MINIMUM_TREND_WEEKS` settimane con studio) */
export function showsTrend(weeks: readonly WeekBucket[]): boolean {
  return weeks.filter((week) => week.seconds > 0).length >= MINIMUM_TREND_WEEKS;
}
