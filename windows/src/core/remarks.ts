// Le frasi «di contesto» del compagno (Remarks.swift): il saluto di quando si avvia l'app o si torna dallo sleep, i numeri dello
// studio detti a voce (il riepilogo della settimana, le frasi «quando rendi meglio») e i traguardi (giorni di fila, focus, ore, anni
// insieme). Tutto si ricava dal registro e dall'ora: niente da salvare, tranne quale riepilogo della settimana è già stato detto.
// Italiano senza genere (niente «bentornato» o «contento» riferiti a chi studia). Logica pura: la usano il processo principale e le prove.

import type { StudySession } from "./log.ts";
import { analyzeStreak, duration, insights, periodContaining, shiftedPeriod, startTime, summarize, weekdayName } from "./stats.ts";
import { DAY_MS, dayString, partsOf, startOfDay, wallOf } from "./time.ts";

/** Quello che serve a sapere come far parlare il compagno adesso. */
export interface RemarksContext {
  /** L'istante, in millisecondi dal 1970. */
  now: number;
  /** Il fuso in cui leggere l'orologio (nessuno = quello del computer). */
  zone?: string;
  name: string | null;
  sessions: readonly StudySession[];
  /** Le cose da fare ancora aperte. */
  openTodoCount?: number;
  /** La frase sulle scadenze di oggi o di domani (`reminderMessage`), se c'è. */
  due?: string | null;
}

/** Una frase, e se dice già le scadenze (allora non serve ripeterle subito dopo). */
export interface Remark {
  text: string;
  coversReminder: boolean;
}

export type DayPart = "morning" | "afternoon" | "evening" | "night";

/** 5–12 mattina, 12–18 pomeriggio, 18–23 sera, il resto notte. */
export function dayPart(hour: number): DayPart {
  if (hour >= 5 && hour < 12) return "morning";
  if (hour >= 12 && hour < 18) return "afternoon";
  if (hour >= 18 && hour < 23) return "evening";
  return "night";
}

/** Un indice valido anche per varianti negative o più grandi del numero di frasi. */
function positive(variant: number, count: number): number {
  return ((variant % count) + count) % count;
}

// ---- saluti

function studiedOn(wall: number, context: RemarksContext): number {
  return summarize(context.sessions, periodContaining(wall, "day"), context.zone).totalSeconds;
}

/** «cosa» al singolare o al plurale: «1 cosa da fare», «3 cose da fare». */
function todoLine(count: number): string {
  return count === 1 ? "Hai 1 cosa da fare." : `Hai ${count} cose da fare.`;
}

/** Il saluto di quando si avvia l'app. `variant` sceglie tra le frasi possibili (così si prova sempre lo stesso risultato). */
export function launchGreeting(context: RemarksContext, variant: number): Remark {
  const wall = wallOf(context.now, context.zone);
  const { hour, weekday } = partsOf(wall);           // weekday: 1 = domenica
  const part = dayPart(hour);
  const name = context.name;

  if (part === "night") {
    const who = name === null ? "È tardi" : `${name}, è tardi`;
    const lines = [`${who}. Un ultimo focus e poi a dormire?`, `${who}: la testa ha bisogno di riposo, non solo di studio.`];
    return { text: lines[positive(variant, lines.length)]!, coversReminder: false };
  }
  let hello: string;
  switch (part) {
    case "morning": hello = weekday === 1 ? "Buona domenica" : "Buongiorno"; break;
    case "afternoon": hello = weekday === 1 ? "Buona domenica" : "Buon pomeriggio"; break;
    default: hello = "Buonasera";
  }
  const head = name === null ? `${hello}!` : `${hello}, ${name}!`;

  // Se oggi o domani scade qualcosa, è la prima cosa da dire.
  if (context.due != null) return { text: `${head} ${context.due}`, coversReminder: true };

  const lines: string[] = [];
  const todaySeconds = studiedOn(wall, context);
  if (part !== "evening") {
    const seconds = studiedOn(wall - DAY_MS, context);
    if (seconds >= 60 && todaySeconds === 0) lines.push(`Ieri hai studiato ${duration(seconds)}: si riparte?`);
  }
  if (todaySeconds >= 60) lines.push(`Oggi hai già studiato ${duration(todaySeconds)}.`);
  const streak = analyzeStreak(context.sessions, context.now, context.zone);
  if (streak.days >= 2) lines.push(`Sei a ${streak.days} giorni di fila.`);
  const open = context.openTodoCount ?? 0;
  if (open > 0) lines.push(todoLine(open));
  if (lines.length === 0) lines.push("Si comincia quando vuoi.");
  return { text: `${head} ${lines[positive(variant, lines.length)]}`, coversReminder: false };
}

/** Meno di un'ora di sleep non merita un saluto. */
export const MINIMUM_AWAY_SECONDS = 3600;

/** Il saluto di quando si torna dallo sleep (`away` = quanto si è stati via, in secondi). Niente se è passato poco: null. */
export function wakeGreeting(context: RemarksContext, away: number, variant: number): Remark | null {
  if (!(away >= MINIMUM_AWAY_SECONDS)) return null;
  const hello = ["Rieccoti!", "Eccoti di nuovo!", "Ti stavo aspettando!"][positive(variant, 3)]!;
  if (context.due != null) return { text: `${hello} ${context.due}`, coversReminder: true };
  const lines: string[] = [];
  const todaySeconds = studiedOn(wallOf(context.now, context.zone), context);
  if (todaySeconds >= 60) lines.push(`Oggi sei a ${duration(todaySeconds)}.`);
  const open = context.openTodoCount ?? 0;
  if (open > 0) lines.push(todoLine(open));
  const text = lines.length === 0 ? hello : `${hello} ${lines[positive(Math.trunc(variant / 3), lines.length)]}`;
  return { text, coversReminder: false };
}

// ---- i numeri a voce

/**
 * Il riepilogo della settimana appena passata, da dire il lunedì (fino al mercoledì, se non l'hai ancora sentito). `key`
 * identifica la settimana (il suo lunedì), per non dirlo due volte. Null se non è un giorno adatto o la settimana scorsa non hai studiato.
 */
export function weeklyRecap(context: RemarksContext): { key: string; text: string } | null {
  const wall = wallOf(context.now, context.zone);
  if (![2, 3, 4].includes(partsOf(wall).weekday)) return null;
  const last = shiftedPeriod(periodContaining(wall, "week"), -1);
  const summary = summarize(context.sessions, last, context.zone);
  if (summary.totalSeconds < 60) return null;
  const perDay = new Map<number, number>();
  for (const s of summary.sessions) {
    const day = startOfDay(startTime(s, context.zone));
    perDay.set(day, (perDay.get(day) ?? 0) + s.seconds);
  }
  const days = perDay.size;
  const focus = summary.focusCount === 1 ? "1 focus" : `${summary.focusCount} focus`;
  let text = `Settimana scorsa: ${duration(summary.totalSeconds)} in ${days === 1 ? "1 giorno" : `${days} giorni`}, ${focus}.`;
  if (days > 1) {
    // Il giorno con più studio; a pari merito, il primo.
    let best: [number, number] | null = null;
    for (const entry of perDay) {
      if (best === null || entry[1] > best[1] || (entry[1] === best[1] && entry[0] < best[0])) best = entry;
    }
    if (best !== null) text += ` Il giorno più forte: ${weekdayName(partsOf(best[0]).weekday)} (${duration(best[1])}).`;
  }
  return { key: dayString(last.start), text };
}

/** Una delle frasi «quando rendi meglio» delle statistiche, o null se non ce ne sono ancora. */
export function insight(context: RemarksContext, variant: number): string | null {
  const lines = insights(context.sessions, context.zone);
  return lines.length === 0 ? null : lines[positive(variant, lines.length)]!;
}

// ---- traguardi

export const STREAK_MILESTONES = [3, 7, 14, 30, 60, 100];
export const FOCUS_MILESTONES = [10, 25, 50, 100, 250, 500, 1000];
export const HOUR_MILESTONES = [10, 25, 50, 100, 250, 500];

/** Il più grande dei traguardi che si è passato (prima sotto, ora sopra o pari). */
function passed(list: readonly number[], before: number, after: number): number | undefined {
  return [...list].reverse().find((m) => before < m && after >= m);
}

/**
 * Una frase se con l'ultimo focus si è passato un traguardo: giorni di fila, numero di focus, ore di studio, o «un mese insieme».
 * `before` sono le sessioni senza quella appena finita, `after` con lei. Una sola frase (la prima trovata, in quest'ordine).
 */
export function milestone(before: readonly StudySession[], after: readonly StudySession[], now: number, zone?: string): string | null {
  const streakBefore = analyzeStreak(before, now, zone).days;
  const streakAfter = analyzeStreak(after, now, zone).days;
  const streak = passed(STREAK_MILESTONES, streakBefore, streakAfter);
  if (streak !== undefined) {
    switch (streak) {
      case 3: return "Tre giorni di fila!";
      case 7: return "Sette giorni di fila! Una settimana intera.";
      case 14: return "Due settimane di fila: che costanza!";
      case 30: return "Trenta giorni di fila! Un mese intero.";
      case 60: return "Sessanta giorni di fila: incredibile.";
      default: return "Cento giorni di fila!";
    }
  }
  const count = passed(FOCUS_MILESTONES, before.length, after.length);
  if (count !== undefined) return count === 10 ? "10 focus insieme!" : `${count} focus: un traguardo tondo!`;
  const hoursOf = (list: readonly StudySession[]): number => Math.floor(list.reduce((total, s) => total + s.seconds, 0) / 3600);
  const hours = passed(HOUR_MILESTONES, hoursOf(before), hoursOf(after));
  if (hours !== undefined) return hours >= 100 ? `${hours} ore passate insieme a me. Grazie!` : `${hours} ore di studio insieme!`;

  // «Oggi è un mese che studiamo insieme»: lo stesso giorno del mese del primo focus, la prima volta che si studia oggi.
  if (after.length === 0) return null;
  const first = Math.min(...after.map((s) => startTime(s, zone)));
  const today = startOfDay(wallOf(now, zone));
  const studiedBefore = before.some((s) => startOfDay(startTime(s, zone)) === today);
  const from = partsOf(first), to = partsOf(today);
  // I mesi si contano sul calendario: l'anniversario di un 31 cade l'ultimo giorno dei mesi più corti.
  const months = (to.year * 12 + to.month) - (from.year * 12 + from.month);
  if (!studiedBefore && months >= 1 && isAnniversaryDay(from.day, to)) {
    if (months === 1) return "Oggi è un mese che studiamo insieme.";
    if (months === 12) return "Oggi è un anno che studiamo insieme!";
    if (months % 12 === 0) return `Oggi sono ${months / 12} anni che studiamo insieme!`;
    return `Oggi sono ${months} mesi che studiamo insieme.`;
  }
  return null;
}

/** Oggi è «lo stesso giorno del mese» di quello del primo focus (se nel mese corrente non c'è, l'ultimo del mese). */
function isAnniversaryDay(wantedDay: number, today: { year: number; month: number; day: number }): boolean {
  const length = new Date(Date.UTC(today.year, today.month, 0)).getUTCDate();
  return today.day === Math.min(wantedDay, length);
}
