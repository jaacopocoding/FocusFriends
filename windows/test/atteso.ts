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
