// Quello che la finestra delle statistiche scrive e disegna, ricavato dai dati con funzioni pure: i titoli dei periodi in italiano,
// le righe sotto il grande numero, le materie e la legenda, le etichette delle barre, il diario (DashboardWindow.swift).

import type { StudySession } from "./log.ts";
import { duration, encouragement, startTime } from "./stats.ts";
import type { Period, PeriodKind, Summary } from "./stats.ts";
import { NO_SUBJECT } from "./text.ts";
import { DAY_MS, HOUR_MS, partsOf, startOfDay } from "./time.ts";
import type { Wall } from "./time.ts";
import type { Rating } from "./log.ts";
import type { Highlights, WeekBucket, YearDay } from "./yearStats.ts";

const formatters = new Map<string, Intl.DateTimeFormat>();

/** Una data (un `Wall`, che legge giorno e ora come se fossero UTC) in italiano con le opzioni date. */
function format(wall: Wall, options: Intl.DateTimeFormatOptions): string {
  const key = JSON.stringify(options);
  let formatter = formatters.get(key);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("it-IT", { timeZone: "UTC", ...options });
    formatters.set(key, formatter);
  }
  return formatter.format(wall);
}

const capitalized = (text: string): string => text.charAt(0).toLocaleUpperCase("it") + text.slice(1);
const pad = (n: number): string => String(n).padStart(2, "0");

/** «Mercoledì 14 ottobre 2026», «12 ott – 18 ott 2026», «Ottobre 2026». */
export function periodTitle(period: Period): string {
  switch (period.kind) {
    case "day": return capitalized(format(period.start, { weekday: "long", day: "numeric", month: "long", year: "numeric" }));
    case "week": return `${format(period.start, { day: "numeric", month: "short" })} – ${format(period.end - 1000, { day: "numeric", month: "short", year: "numeric" })}`;
    case "month": return capitalized(format(period.start, { month: "long", year: "numeric" }));
    case "year": return String(partsOf(period.start).year);
  }
}

/** Sotto al numero: «di studio · 4 focus · 1 interrotto». */
export function subtitle(summary: Summary): string {
  if (summary.focusCount === 0) return "";
  const parts = ["di studio", summary.focusCount === 1 ? "1 focus" : `${summary.focusCount} focus`];
  if (summary.interruptedCount === 1) parts.push("1 interrotto");
  if (summary.interruptedCount > 1) parts.push(`${summary.interruptedCount} interrotti`);
  return parts.join(" · ");
}

/** Una riga in più, più piccola: una parola gentile oggi, la media negli altri periodi. */
export function secondaryLine(summary: Summary, kind: PeriodKind, isCurrent: boolean): string {
  if (summary.focusCount === 0) return isCurrent ? "Quando vuoi, io sono qui." : "Nessun focus in questo periodo.";
  if (kind === "day") return isCurrent ? encouragement(summary.totalSeconds) : "";
  const days = summary.buckets.filter((b) => b.seconds > 0).length;
  return `In media ${duration(Math.trunc(summary.totalSeconds / Math.max(days, 1)))} nei ${days} giorni in cui hai studiato.`;
}

export const MAX_SUBJECT_ROWS = 6;

export interface SubjectRow {
  subject: string;
  seconds: number;
  /** «Altre (n)» o «Senza materia»: si disegna in grigio. */
  muted: boolean;
}

/** Le materie del periodo: fino a sei, il resto in «Altre (n)». */
export function subjectRows(summary: Summary): SubjectRow[] {
  const rows: SubjectRow[] = summary.bySubject.slice(0, MAX_SUBJECT_ROWS).map((row) => ({ ...row, muted: row.subject === NO_SUBJECT }));
  if (summary.bySubject.length > MAX_SUBJECT_ROWS) {
    const rest = summary.bySubject.slice(MAX_SUBJECT_ROWS);
    rows.push({ subject: `Altre (${rest.length})`, seconds: rest.reduce((total, row) => total + row.seconds, 0), muted: true });
  }
  return rows;
}

/** L'etichetta sotto una barra: il giorno della settimana, o il numero del giorno (il primo e ogni cinque) nel mese. */
export function chartLabel(kind: PeriodKind, bucketStart: Wall): string | null {
  if (kind === "week") return format(bucketStart, { weekday: "short" });
  if (kind === "month") {
    const day = partsOf(bucketStart).day;
    return day === 1 || day % 5 === 0 ? String(day) : null;
  }
  return null;
}

/** «3 giorni di fila · ghiacciata: studia oggi». */
export function streakLabel(streak: number, frozen: boolean): string {
  return (streak === 1 ? "1 giorno di fila" : `${streak} giorni di fila`) + (frozen ? " · ghiacciata: studia oggi" : "");
}

/** Si può andare al periodo dopo? Non oltre quello di oggi (e non oltre un anno: come sul Mac). */
export function canGoNext(period: Period, nowWall: Wall): boolean {
  return !(nowWall >= period.start && nowWall < period.end) && period.end <= nowWall + 366 * DAY_MS;
}

// ---- il diario

export const RATING_ORDER: readonly Rating[] = ["good", "soso", "poor"];

/** Le note scritte durante il focus, su una riga («Note: una  ·  due»), o null se non ce ne sono. */
export function focusNotesLine(session: StudySession): string | null {
  return session.notes && session.notes.length > 0 ? `Note: ${session.notes.join("  ·  ")}` : null;
}

export type DiaryEntry =
  | { type: "strip"; blocks: Array<{ session: StudySession; startHour: number; endHour: number }>; firstHour: number; lastHour: number }
  | { type: "header"; day: Wall; title: string; seconds: number }
  | { type: "session"; session: StudySession; time: string; minutes: number };

/** Le ore del giorno in orizzontale: dalle 8 (o prima) alle 18 (o dopo), per contenere tutti i focus. */
function stripOf(sessions: readonly StudySession[], zone?: string): Extract<DiaryEntry, { type: "strip" }> {
  const blocks = sessions.map((session) => {
    const at = startTime(session, zone);
    const startHour = (at - startOfDay(at)) / HOUR_MS;
    return { session, startHour, endHour: startHour + session.seconds / 3600 };
  });
  const firstHour = Math.max(Math.min(8, Math.trunc(Math.min(...blocks.map((b) => b.startHour)))), 0);
  const lastHour = Math.min(Math.max(18, Math.ceil(Math.max(...blocks.map((b) => b.endHour)))), 24);
  return { type: "strip", blocks, firstHour, lastHour };
}

/** Le sessioni del periodo, dalla più antica: per un giorno solo la striscia delle ore, per settimana e mese un'intestazione per ogni giorno. */
export function diaryEntries(sessions: readonly StudySession[], kind: PeriodKind, zone?: string): DiaryEntry[] {
  const ordered = [...sessions].sort((a, b) => startTime(a, zone) - startTime(b, zone));
  const entries: DiaryEntry[] = [];
  if (kind === "day" && ordered.length > 0) entries.push(stripOf(ordered, zone));
  let currentDay: Wall | null = null;
  for (const session of ordered) {
    const at = startTime(session, zone);
    if (kind !== "day") {
      const day = startOfDay(at);
      if (currentDay !== day) {
        currentDay = day;
        const seconds = ordered.filter((s) => startOfDay(startTime(s, zone)) === day).reduce((total, s) => total + s.seconds, 0);
        entries.push({ type: "header", day, title: capitalized(format(day, { weekday: "long", day: "numeric", month: "long" })), seconds });
      }
    }
    const p = partsOf(at);
    entries.push({ type: "session", session, time: `${pad(p.hour)}:${pad(p.minute)}`, minutes: Math.trunc((session.seconds + 30) / 60) });
  }
  return entries;
}

/** «mercoledì 14 ottobre, 09:30 · 25 min»: per il titolo della finestra di modifica di una sessione. */
export function sessionHeading(session: StudySession, zone?: string): string {
  const at = startTime(session, zone);
  const p = partsOf(at);
  return `${format(at, { weekday: "long", day: "numeric", month: "long" })}, ${pad(p.hour)}:${pad(p.minute)} · ${Math.trunc((session.seconds + 30) / 60)} min`;
}

// ---- la scheda «Anno» (YearStats.swift)

const MONTH_LABELS = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"];

/** Il nome corto del mese (1...12) sopra la mappa e sotto le barre. */
export function monthLabel(month: number): string {
  return MONTH_LABELS[Math.max(1, Math.min(12, month)) - 1]!;
}

/** Cosa si legge passando sopra un giorno: «Venerdì 2 ottobre · 2 h 10 · 3 focus». */
export function dayText(day: Pick<YearDay, "start" | "seconds" | "focusCount">): string {
  const name = capitalized(format(day.start, { weekday: "long", day: "numeric", month: "long" }));
  if (day.seconds <= 0) return `${name} · nessun focus`;
  return `${name} · ${duration(day.seconds)} · ${day.focusCount === 1 ? "1 focus" : `${day.focusCount} focus`}`;
}

/** Cosa si legge passando sopra una barra: «Settimana del 29 giu · 9 h 35». */
export function weekText(week: WeekBucket): string {
  return `Settimana del ${format(week.start, { day: "numeric", month: "short" })} · ${duration(week.seconds)}`;
}

/** Sopra le barre, a destra: «al massimo 15 h 30 in una settimana». */
export function trendCaption(maxSeconds: number): string {
  return `al massimo ${duration(maxSeconds)} in una settimana`;
}

export interface YearTile {
  value: string;
  caption: string;
}

/** Le caselle sotto la mappa: la serie più lunga, il giorno più forte, il mese migliore (le ultime due solo se c'è stato studio). */
export function yearTiles(found: Highlights): YearTile[] {
  const tiles: YearTile[] = [{ value: found.longestStreak === 1 ? "1 giorno" : `${found.longestStreak} giorni`, caption: "la serie più lunga" }];
  if (found.bestDay !== null) {
    tiles.push({ value: duration(found.bestDay.seconds), caption: `il giorno più forte · ${format(found.bestDay.start, { day: "numeric", month: "short" })}` });
  }
  if (found.bestMonth !== null) {
    tiles.push({ value: capitalized(format(found.bestMonth.start, { month: "long" })), caption: `il mese migliore · ${duration(found.bestMonth.seconds)}` });
  }
  return tiles;
}
