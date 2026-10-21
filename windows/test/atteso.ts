// Rifà in TypeScript quello che tests/genera-attesi/main.swift ricava da una cartella di dati di esempio, con lo stesso
// «adesso» fisso (14 ottobre 2026, ore 20:00, Europe/Rome). Il test di contratto lo confronta con i file in
// tests/fixtures/attesi/, che sono generati dalla versione per Mac.

import { cpSync, mkdtempSync, readdirSync, rmSync, statSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SessionLog } from "../src/core/log.ts";
import type { StudySession } from "../src/core/log.ts";
import { Profile } from "../src/core/profile.ts";
import { csv } from "../src/core/csv.ts";
import { DAY_MS, dayString, wallOf } from "../src/core/time.ts";
import { analyzeStreak, insights, periodContaining, summarize } from "../src/core/stats.ts";
import type { PeriodKind, Summary } from "../src/core/stats.ts";
import { balance, earnedPoints, multiplierToday, pointsForWeightedMinutes, progressToNextPoint, weightedMinutes } from "../src/core/points.ts";
import { earned, focuses } from "../src/core/rewards.ts";
import { ToDoList } from "../src/core/todoList.ts";
import { addDays, dueLabel, GROUP_TITLES, reminderMessage, todayOf } from "../src/core/todo.ts";
import { isoUtc } from "../src/core/time.ts";
import { insight, launchGreeting, milestone, wakeGreeting, weeklyRecap } from "../src/core/remarks.ts";
import type { RemarksContext } from "../src/core/remarks.ts";

export const ZONE = "Europe/Rome";
export const NOW = Date.UTC(2026, 9, 14, 18, 0, 0);     // le 20:00 a Roma (CEST, UTC+2)
export const PETS = ["pianty", "porcellino", "ciccio", "gattino"];      // l'ordine dei personaggi

const round = (x: number): number => Math.round(x * 1000) / 1000;

function normalized(text: string): string {
  return text.replace(/corrotto-\d+/g, "corrotto-<epoch>");
}

function summaryJson(s: Summary): Record<string, unknown> {
  return {
    secondiTotali: s.totalSeconds, focus: s.focusCount, completati: s.completedCount, interrotti: s.interruptedCount,
    perMateria: s.bySubject.map((x) => ({ materia: x.subject, secondi: x.seconds })),
    barre: s.buckets.map((b) => b.seconds),
    voti: { good: s.ratingCounts.good ?? 0, soso: s.ratingCounts.soso ?? 0, poor: s.ratingCounts.poor ?? 0 },
  };
}

function relativeFiles(directory: string, prefix = ""): string[] {
  const found: string[] = [];
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) found.push(...relativeFiles(path, `${prefix}${entry}/`));
    else found.push(normalized(`${prefix}${entry}`));
  }
  return found.sort();
}

// ---- le frasi di contesto (remarks.ts): gli stessi momenti fissi e gli stessi dati di tests/genera-attesi/main.swift

const CONTEXT_MOMENTS: Array<[number, number, number, number, number]> = [
  [2026, 10, 12, 9, 30], [2026, 10, 13, 15, 0], [2026, 10, 14, 20, 0], [2026, 10, 15, 2, 30], [2026, 10, 18, 10, 0], [2026, 10, 26, 8, 0],
];
const CONTEXT_DUE = "Oggi scade «Esercizi di analisi». Un focus adesso?";

/** L'istante in cui a Roma l'orologio segna questa data e quest'ora. */
function romeInstant(y: number, m: number, d: number, h = 0, min = 0): number {
  const target = Date.UTC(y, m - 1, d, h, min);
  let instant = target;
  for (let i = 0; i < 2; i += 1) instant = target - (wallOf(instant, ZONE) - instant);
  return instant;
}

const two = (n: number): string => String(n).padStart(2, "0");

export function contextJson(sessions: readonly StudySession[]): Record<string, unknown> {
  const context = (at: number, extra: Partial<RemarksContext> = {}): RemarksContext =>
    ({ now: at, zone: ZONE, name: "Jacopo", sessions, openTodoCount: 0, due: null, ...extra });
  const moments = CONTEXT_MOMENTS.map(([y, mo, d, h, mi]) => {
    const at = romeInstant(y, mo, d, h, mi);
    const withDue = launchGreeting(context(at, { openTodoCount: 2, due: CONTEXT_DUE }), 0);
    const recap = weeklyRecap(context(at));
    return {
      adesso: `${y}-${two(mo)}-${two(d)}T${two(h)}:${two(mi)}`,
      saluti: [0, 1, 2, 3, 4, 5].map((variant) => launchGreeting(context(at, { openTodoCount: 2 }), variant).text),
      salutoSenzaNome: launchGreeting(context(at, { name: null }), 0).text,
      salutoConScadenza: { testo: withDue.text, copreIlPromemoria: withDue.coversReminder },
      risveglio: [0, 1, 2, 3, 4, 5].map((variant) => wakeGreeting(context(at, { openTodoCount: 2 }), 7200, variant)?.text ?? null),
      risveglioBreve: wakeGreeting(context(at), 1800, 0)?.text ?? null,
      riepilogo: recap === null ? null : { chiave: recap.key, testo: recap.text },
      numeri: [0, 1, 2].map((variant) => insight(context(at), variant)),
    };
  });
  // I traguardi: man mano che il registro cresce (ogni sessione, dalla più vecchia), quali frasi scattano.
  const ordered = [...sessions].sort((a, b) => (a.start !== b.start ? a.start - b.start : a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const milestones: Array<{ dopo: number; frase: string }> = [];
  ordered.forEach((current, index) => {
    const text = milestone(ordered.slice(0, index), ordered.slice(0, index + 1), current.start, ZONE);
    if (text !== null) milestones.push({ dopo: index + 1, frase: text });
  });
  return { momenti: moments, traguardi: milestones };
}

/** Gli anniversari su date inventate (come `anniversaryJSON` nel generatore Swift). */
export function anniversariesJson(): { anniversari: Array<Record<string, string>> } {
  const sessionOn = (y: number, m: number, d: number): StudySession => ({
    id: `${y}-${m}-${d}`, start: romeInstant(y, m, d, 10), localStart: `${y}-${two(m)}-${two(d)}T10:00`, seconds: 3000, plannedMinutes: 50, completed: true,
  });
  const found: Array<Record<string, string>> = [];
  const firsts: Array<[number, number, number]> = [[2026, 1, 31], [2026, 1, 30], [2026, 1, 29], [2024, 2, 29], [2025, 12, 15], [2026, 8, 31], [2026, 3, 31], [2026, 2, 28]];
  for (const [fy, fm, fd] of firsts) {
    const first = sessionOn(fy, fm, fd);
    const end = Date.UTC(2029, 0, 1);
    for (let day = Date.UTC(fy, fm - 1, fd) + DAY_MS; day < end; day += DAY_MS) {
      const at = new Date(day);
      const [y, m, d] = [at.getUTCFullYear(), at.getUTCMonth() + 1, at.getUTCDate()];
      const today = sessionOn(y, m, d);
      const text = milestone([first], [first, today], today.start + 2 * 3_600_000, ZONE);
      if (text !== null) found.push({ primo: `${fy}-${two(fm)}-${two(fd)}`, oggi: `${y}-${two(m)}-${two(d)}`, frase: text });
    }
  }
  return { anniversari: found };
}

/** Le cartelle di esempio da confrontare (le «impostazioni-*» hanno un altro test, e «attesi» è l'uscita). */
export function fixtureNames(fixtures: string): string[] {
  return readdirSync(fixtures)
    .filter((name) => name !== "attesi" && !name.startsWith("impostazioni") && statSync(join(fixtures, name)).isDirectory())
    .sort();
}

/** Quello che l'app ricava dalla cartella `name` di `fixtures`, nella stessa forma dei file attesi. */
export function derive(fixtures: string, name: string): Record<string, unknown> {
  const temp = mkdtempSync(join(tmpdir(), "ff-attesi-"));
  try {
    cpSync(join(fixtures, name), temp, { recursive: true });
    const has = (file: string): boolean => existsSync(join(temp, file));
    const result: Record<string, unknown> = { cartella: name, adesso: "2026-10-14T20:00 Europe/Rome" };
    let sessions: readonly StudySession[] = [];

    if (has("sessioni.json") || has("in-corso.json")) {
      const log = new SessionLog(temp, { now: () => NOW, zone: ZONE });
      const problems: string[] = [];
      log.onProblem = (message) => problems.push(normalized(message));
      const part: Record<string, unknown> = {};
      const hadProgress = has("in-corso.json");
      if (hadProgress) {
        const recovered = log.recoverInterrupted();
        part["recuperata"] = recovered === null ? null : {
          secondi: recovered.seconds, minutiPrevisti: recovered.plannedMinutes, completa: recovered.completed,
          materia: recovered.subject ?? null, personaggio: recovered.pet ?? null, note: recovered.notes ?? [],
          inizioLocale: recovered.localStart ?? null,
        };
        part["inCorsoRimasto"] = has("in-corso.json");
      }
      sessions = log.sessions;
      part["numero"] = sessions.length;
      part["solaLettura"] = log.isReadOnly;
      part["secondiTotali"] = sessions.reduce((total, s) => total + s.seconds, 0);
      part["materie"] = [...new Set(sessions.flatMap((s) => (s.subject === undefined ? [] : [s.subject])))].sort();
      part["conOraLocale"] = sessions.filter((s) => s.localStart !== undefined).length;
      part["avvisi"] = problems;
      if (!hadProgress) part["ordineId"] = sessions.map((s) => s.id.slice(-4).toUpperCase());
      result["registro"] = part;

      if (sessions.length > 0) {
        const stats: Record<string, unknown> = {};
        const today = wallOf(NOW, ZONE);
        const kinds: Array<[string, PeriodKind]> = [["giorno", "day"], ["settimana", "week"], ["mese", "month"]];
        for (const [label, kind] of kinds) stats[label] = summaryJson(summarize(sessions, periodContaining(today, kind), ZONE));
        const streak = analyzeStreak(sessions, NOW, ZONE);
        const perDay: Record<string, number> = {};
        for (const [day, count] of streak.perDay) perDay[dayString(day * DAY_MS)] = count;
        stats["serie"] = { giorni: streak.days, ghiacciata: streak.isFrozen, hoStudiatoOggi: streak.studiedToday, perGiorno: perDay };
        const weighted = weightedMinutes(sessions, NOW, ZONE);
        stats["punti"] = {
          minutiPesati: round(weighted), guadagnati: pointsForWeightedMinutes(weighted),
          "verso il prossimo": round(progressToNextPoint(weighted)), valoreMinutoOggi: multiplierToday(streak),
        };
        stats["frasi"] = insights(sessions, ZONE);
        stats["csv"] = csv(sessions);
        result["statistiche"] = stats;
        result["contesto"] = contextJson(sessions);
      }
    }

    if (has("profilo.json")) {
      const profile = new Profile(temp, { now: () => NOW });
      const problems: string[] = [];
      profile.onProblem = (message) => problems.push(normalized(message));
      const part: Record<string, unknown> = {
        nome: profile.name, introduzioneVista: profile.introSeen,
        sbloccati: profile.unlocked === null ? null : [...profile.unlocked].sort(), primoCompagno: profile.firstCompanion,
        avvisi: problems, titoloGiardino: profile.gardenTitle, titoloStatistiche: profile.statsTitle,
        compagniUsabili: Object.fromEntries(PETS.map((pet) => [pet, profile.isCompanionUnlocked(pet)])),
      };
      if (sessions.length > 0) {
        const full = focuses(sessions.reduce((total, s) => total + s.seconds, 0));
        part["focusPieni"] = full;
        part["compagniMeritati"] = [...earned(profile.firstCompanion, PETS, full)].sort();
      }
      profile.keepAllCompanions(PETS);
      part["sbloccatiDopoKeepAll"] = profile.unlocked === null ? null : [...profile.unlocked].sort();
      result["profilo"] = part;
    } else if (name.startsWith("profilo")) {
      result["profilo"] = { nota: "nessun file" };
    }

    if (has("dafare.json")) {
      const list = new ToDoList(temp, { now: () => NOW });
      const problems: string[] = [];
      list.onProblem = (message) => problems.push(normalized(message));
      const today = todayOf(NOW, ZONE);
      const reminders: Record<string, string | null> = {};
      for (const offset of [-1, 0, 1]) {
        const day = addDays(today, offset)!;
        reminders[day] = reminderMessage(list.items, day);
      }
      result["daFare"] = {
        voci: list.items.length, daFare: list.openCount, solaLettura: list.isReadOnly, avvisi: problems,
        gruppi: list.sections(today).map((section) => ({
          gruppo: GROUP_TITLES[section.group],
          voci: section.items.map((item) => ({
            testo: item.text, scadenza: item.due, etichetta: item.due === null ? null : dueLabel(item.due, today), materia: item.subject,
          })),
        })),
        fatte: list.doneItems.map((item) => ({ testo: item.text, fattaIl: isoUtc(item.doneAt!) })),
        promemoria: reminders,
      };
    }

    result["fileDopo"] = relativeFiles(temp);
    return result;
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

export { balance, earnedPoints };
