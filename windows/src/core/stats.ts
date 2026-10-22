// Le statistiche che si ricavano dal registro: periodi, riepiloghi, serie di giorni con un giorno di ghiaccio, frasi
// su quando si rende meglio, testi. Stesse regole di SessionLog.swift e GardenPoints.swift (StudyStreak).

import type { Rating, StudySession } from "./log.ts";
import { DAY_MS, HOUR_MS, addMonths, partsOf, parseLocal, startOfDay, startOfMonth, startOfWeek, startOfYear, wallOf } from "./time.ts";
import type { Wall } from "./time.ts";
import { NO_SUBJECT, subjectKey } from "./text.ts";

/** Quando è iniziata la sessione, sull'orologio: vale `localStart`; se manca o non è valido, l'istante assoluto. */
export function startTime(session: StudySession, zone?: string): Wall {
  if (session.localStart !== undefined) {
    const wall = parseLocal(session.localStart);
    if (wall !== null) return wall;
  }
  return wallOf(session.start, zone);
}

// ---- periodi

export type PeriodKind = "day" | "week" | "month" | "year";

/** Un giorno, una settimana (da lunedì), un mese o un anno: inizio incluso, fine esclusa, sull'orologio. */
export interface Period {
  kind: PeriodKind;
  start: Wall;
  end: Wall;
}

export function periodContaining(wall: Wall, kind: PeriodKind): Period {
  switch (kind) {
    case "day": {
      const start = startOfDay(wall);
      return { kind, start, end: start + DAY_MS };
    }
    case "week": {
      const start = startOfWeek(wall);
      return { kind, start, end: start + 7 * DAY_MS };
    }
    case "month": {
      const start = startOfMonth(wall);
      return { kind, start, end: addMonths(start, 1) };
    }
    case "year": {
      const start = startOfYear(wall);
      return { kind, start, end: addMonths(start, 12) };
    }
  }
}

/** Il periodo `count` posti più avanti (o indietro, se negativo). */
export function shiftedPeriod(period: Period, count: number): Period {
  const moved = period.kind === "day" ? period.start + count * DAY_MS
    : period.kind === "week" ? period.start + count * 7 * DAY_MS
    : period.kind === "month" ? addMonths(period.start, count)
    : addMonths(period.start, 12 * count);
  return periodContaining(moved, period.kind);
}

export function periodContains(period: Period, wall: Wall): boolean {
  return wall >= period.start && wall < period.end;
}

// ---- riepilogo

export interface Summary {
  totalSeconds: number;
  focusCount: number;
  completedCount: number;
  interruptedCount: number;
  /** Per materia, dalla più studiata. */
  bySubject: Array<{ subject: string; seconds: number }>;
  /** Per ora (se il periodo è un giorno) o per giorno (settimana e mese). */
  buckets: Array<{ start: Wall; seconds: number }>;
  /** Le sessioni del periodo, dalla più recente. */
  sessions: StudySession[];
  ratingCounts: Partial<Record<Rating, number>>;
}

export function summarize(sessions: readonly StudySession[], period: Period, zone?: string): Summary {
  // Una sessione va al periodo in cui è iniziata (anche se passa la mezzanotte), secondo l'ora «sull'orologio».
  const inPeriod = sessions.map((session) => ({ session, at: startTime(session, zone) })).filter(({ at }) => periodContains(period, at));
  const summary: Summary = {
    totalSeconds: inPeriod.reduce((total, { session }) => total + session.seconds, 0),
    focusCount: inPeriod.length,
    completedCount: inPeriod.filter(({ session }) => session.completed).length,
    interruptedCount: 0,
    bySubject: [], buckets: [], ratingCounts: {},
    sessions: [...inPeriod].sort((a, b) => b.at - a.at).map(({ session }) => session),
  };
  summary.interruptedCount = summary.focusCount - summary.completedCount;
  for (const { session } of inPeriod) {
    if (session.rating !== undefined) summary.ratingCounts[session.rating] = (summary.ratingCounts[session.rating] ?? 0) + 1;
  }

  // Le materie si raggruppano senza distinguere maiuscole e accenti; si mostra la scrittura più recente.
  const secondsByKey = new Map<string, number>();
  const displayByKey = new Map<string, string>();
  for (const { session } of [...inPeriod].sort((a, b) => a.at - b.at)) {
    const name = session.subject ?? NO_SUBJECT;
    const key = session.subject === undefined ? "\u0000senza-materia" : subjectKey(session.subject);
    secondsByKey.set(key, (secondsByKey.get(key) ?? 0) + session.seconds);
    displayByKey.set(key, name);
  }
  summary.bySubject = [...secondsByKey.keys()]
    .map((key) => ({ subject: displayByKey.get(key) ?? NO_SUBJECT, seconds: secondsByKey.get(key) ?? 0 }))
    .sort((a, b) => (a.seconds !== b.seconds ? b.seconds - a.seconds : a.subject < b.subject ? -1 : a.subject > b.subject ? 1 : 0));

  const step = period.kind === "day" ? HOUR_MS : DAY_MS;
  for (let cursor = period.start; cursor < period.end; cursor += step) {
    const seconds = inPeriod
      .filter(({ at }) => at >= cursor && at < cursor + step)
      .reduce((total, { session }) => total + session.seconds, 0);
    summary.buckets.push({ start: cursor, seconds });
  }
  return summary;
}

/** I secondi di studio del giorno in cui è iniziata `session` (compresa lei). */
export function secondsOnDayOf(session: StudySession, sessions: readonly StudySession[], zone?: string): number {
  const day = startOfDay(startTime(session, zone));
  return sessions.filter((s) => startOfDay(startTime(s, zone)) === day).reduce((total, s) => total + s.seconds, 0);
}

// ---- la serie di giorni, con un giorno di ghiaccio

/** Dopo un giorno ghiacciato ne devono passare altrettanti prima di poterne ghiacciare un altro. */
export const FREEZE_INTERVAL = 7;

export interface StreakResult {
  /** Per ogni giorno con studio (numero di giorni dal 1970 sull'orologio): i giorni di fila raggiunti quel giorno. */
  perDay: Map<number, number>;
  /** I giorni di fila a oggi. */
  days: number;
  /** Ieri non si è studiato ma la serie è salva (ghiacciata): studiando oggi continua. */
  isFrozen: boolean;
  /** Oggi si è già studiato. */
  studiedToday: boolean;
}

/**
 * Un giorno senza studio non azzera la serie: la «ghiaccia». Il numero resta fermo, e se il giorno dopo si studia riparte
 * da lì. Due giorni di fila senza studio la azzerano, e il ghiaccio si usa una volta ogni 7 giorni. Un giorno senza studio
 * che è ancora oggi non si giudica: la giornata non è finita.
 */
export function analyzeStreak(sessions: readonly StudySession[], nowInstant: number, zone?: string): StreakResult {
  const studyDays = new Set(sessions.map((s) => Math.floor(startOfDay(startTime(s, zone)) / DAY_MS)));
  const today = Math.floor(startOfDay(wallOf(nowInstant, zone)) / DAY_MS);
  if (studyDays.size === 0) return { perDay: new Map(), days: 0, isFrozen: false, studiedToday: false };
  const first = Math.min(...studyDays);
  const last = Math.max(today, ...studyDays);

  const perDay = new Map<number, number>();
  let streak = 0;
  let frozen = false;
  let previousWasStudy = false;
  let lastFreeze: number | undefined;
  for (let day = first; day <= last; day += 1) {
    if (studyDays.has(day)) {
      streak += 1;
      perDay.set(day, streak);
      previousWasStudy = true;
      frozen = false;
    } else if (day < today) {
      // Un giorno passato senza studio: si ghiaccia (una volta di fila, e non più di una ogni 7 giorni) o la serie finisce.
      const freezeReady = lastFreeze === undefined || day - lastFreeze >= FREEZE_INTERVAL;
      if (streak > 0 && previousWasStudy && freezeReady) {
        lastFreeze = day;
        frozen = true;
      } else {
        streak = 0;
        frozen = false;
      }
      previousWasStudy = false;
    }
  }
  return { perDay, days: streak, isFrozen: frozen, studiedToday: studyDays.has(today) };
}

// ---- quando rendi meglio

export const MINIMUM_RATED_FOR_INSIGHTS = 8;
export const MINIMUM_PER_GROUP = 3;
export const MINIMUM_GAP = 0.2;

/** Le fasce della giornata, per `hour` (0...23). */
export function daySlot(hour: number): string {
  if (hour >= 6 && hour < 12) return "di mattina";
  if (hour >= 12 && hour < 18) return "nel pomeriggio";
  if (hour >= 18 && hour < 24) return "di sera";
  return "di notte";
}

/** Il giorno della settimana (1 = domenica, come in Calendar) in italiano. */
export function weekdayName(weekday: number): string {
  const names = ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"];
  return names[Math.max(0, Math.min(6, weekday - 1))] ?? "domenica";
}

interface Candidate {
  gap: number;
  text: string;
  dimension: number;
}

/** Fino a due frasi su quando o con cosa i focus vanno meglio o peggio, con i conteggi; niente se i dati sono pochi. */
export function insights(sessions: readonly StudySession[], zone?: string): string[] {
  const rated = sessions.filter((s) => s.rating !== undefined);
  if (rated.length < MINIMUM_RATED_FOR_INSIGHTS) return [];
  const overall = rated.filter((s) => s.rating === "good").length / rated.length;
  const candidates: Candidate[] = [];

  const evaluate = (dimension: number, key: (s: StudySession) => string | null, display: (key: string) => string,
                    best: (name: string, good: number, total: number) => string,
                    worst: (name: string, good: number, total: number) => string): void => {
    const groups = new Map<string, { good: number; total: number }>();
    for (const s of rated) {
      const k = key(s);
      if (k === null) continue;
      const group = groups.get(k) ?? { good: 0, total: 0 };
      group.total += 1;
      if (s.rating === "good") group.good += 1;
      groups.set(k, group);
    }
    // Dal migliore e dal peggiore: si ordina anche per nome per avere sempre lo stesso risultato.
    const scored = [...groups.entries()]
      .filter(([, g]) => g.total >= MINIMUM_PER_GROUP)
      .map(([k, g]) => ({ key: k, share: g.good / g.total, good: g.good, total: g.total }))
      .sort((a, b) => (a.share !== b.share ? b.share - a.share : a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
    const top = scored[0];
    if (top && top.share - overall >= MINIMUM_GAP && scored.length > 1) {
      candidates.push({ gap: top.share - overall, text: best(display(top.key), top.good, top.total), dimension });
    }
    const low = scored[scored.length - 1];
    if (low && overall - low.share >= MINIMUM_GAP && scored.length > 1) {
      candidates.push({ gap: overall - low.share, text: worst(display(low.key), low.good, low.total), dimension });
    }
  };

  evaluate(0, (s) => daySlot(partsOf(startTime(s, zone)).hour), (k) => k,
    (n, g, t) => `Rendi meglio ${n}: ${g} focus su ${t} sono andati bene.`,
    (n, g, t) => `Rendi meno ${n}: ${g} focus su ${t} sono andati bene.`);
  evaluate(1, (s) => String(partsOf(startTime(s, zone)).weekday), (k) => weekdayName(Number(k) || 1),
    (n, g, t) => `Il ${n} rendi meglio: ${g} focus su ${t} sono andati bene.`,
    (n, g, t) => `Il ${n} fai più fatica: ${g} focus su ${t} sono andati bene.`);
  evaluate(2, (s) => (s.subject === undefined ? null : subjectKey(s.subject)),
    (k) => rated.find((s) => s.subject !== undefined && subjectKey(s.subject) === k)?.subject ?? k,
    (n, g, t) => `Con ${n} vai bene: ${g} focus su ${t} sono andati bene.`,
    (n, g, t) => `Con ${n} fai più fatica: ${g} focus su ${t} sono andati bene.`);

  const result: string[] = [];
  const used = new Set<number>();
  const ordered = [...candidates].sort((a, b) => (a.gap !== b.gap ? b.gap - a.gap : a.text < b.text ? -1 : a.text > b.text ? 1 : 0));
  for (const c of ordered) {
    if (used.has(c.dimension)) continue;
    used.add(c.dimension);
    result.push(c.text);
    if (result.length === 2) break;
  }
  return result;
}

// ---- testi

/** «3 h 20», «45 min», «2 h», «0 min». */
export function duration(seconds: number): string {
  const minutes = Math.trunc((seconds + 30) / 60);
  if (minutes < 60) return `${minutes} min`;
  const h = Math.trunc(minutes / 60);
  const m = minutes % 60;
  return m === 0 ? `${h} h` : `${h} h ${String(m).padStart(2, "0")}`;
}

/** La riga del riepilogo: «Oggi hai fatto 5 focus: 3 h 20 di studio.» */
export function dayLine(summary: Summary, isToday: boolean, dayName: string): string {
  const when = isToday ? "Oggi" : dayName;
  if (summary.focusCount === 0) return isToday ? "Oggi non hai ancora fatto nessun focus." : `${when} non hai fatto nessun focus.`;
  const focus = summary.focusCount === 1 ? "1 focus" : `${summary.focusCount} focus`;
  return `${when} hai fatto ${focus}: ${duration(summary.totalSeconds)} di studio.`;
}

/** Una parola gentile in base a quanto si è studiato nel giorno. */
export function encouragement(totalSeconds: number): string {
  const minutes = Math.trunc(totalSeconds / 60);
  if (minutes <= 0) return "Quando vuoi, io sono qui.";
  if (minutes < 45) return "Un bell'inizio: ogni minuto conta.";
  if (minutes < 120) return "Che bel lavoro! Ora una pausa te la sei meritata.";
  if (minutes < 240) return "Una giornata di studio bella piena. Complimenti!";
  return "Una giornata di studio davvero lunga: ricordati di riposare.";
}
