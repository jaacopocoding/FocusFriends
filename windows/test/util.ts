// Piccoli aiuti per le prove: date a Roma, cartelle temporanee, sessioni di esempio.

import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { wallOf } from "../src/core/time.ts";
import type { Wall } from "../src/core/time.ts";
import type { Rating, StudySession } from "../src/core/log.ts";

export const ZONE = "Europe/Rome";

/** L'orologio a Roma come `Wall` (giorno e ora, senza fuso): per i periodi e le barre. */
export function wall(y: number, m: number, d: number, h = 0, min = 0): Wall {
  return Date.UTC(y, m - 1, d, h, min);
}

/** L'istante in cui a Roma l'orologio segna questa data e quest'ora. */
export function date(y: number, m: number, d: number, h = 0, min = 0): number {
  const target = wall(y, m, d, h, min);
  let instant = target;
  // L'orologio a Roma è avanti di 1 o 2 ore rispetto a UTC: si corregge due volte per stare dalla parte giusta del cambio d'ora.
  for (let i = 0; i < 2; i += 1) instant = target - (wallOf(instant, ZONE) - instant);
  return instant;
}

const created: string[] = [];
process.on("exit", () => {
  for (const path of created) {
    try { rmSync(path, { recursive: true, force: true }); } catch { /* resta nella cartella temporanea */ }
  }
});

export function tempDirectory(): string {
  const path = mkdtempSync(join(tmpdir(), "ff-test-"));
  created.push(path);
  return path;
}

export function session(fields: Partial<StudySession> & Pick<StudySession, "start" | "seconds">): StudySession {
  return { id: randomUUID().toUpperCase(), plannedMinutes: Math.round(fields.seconds / 60), completed: true, ...fields };
}

export function rated(day: number, hour: number, subject: string, rating: Rating): StudySession {
  const start = date(2026, 10, day, hour);
  return session({ start, seconds: 1500, plannedMinutes: 25, subject, rating,
    localStart: `2026-10-${String(day).padStart(2, "0")}T${String(hour).padStart(2, "0")}:00` });
}
