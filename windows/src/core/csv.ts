// L'esportazione CSV delle sessioni (FORMATI.md non la descrive: è un'uscita, non un file dei dati).

import type { StudySession } from "./log.ts";
import { isoUtc } from "./time.ts";

export const CSV_HEADER = "inizio,inizio_locale,minuti,minuti_previsti,completa,materia,personaggio,com_e_andata,nota,note_del_focus";

/** Un campo di testo tra virgolette. Se comincia con un carattere che un foglio di calcolo prende per una formula
 *  (= + - @, tabulazione, ritorno a capo) gli si mette davanti un apice, così non viene eseguito. */
export function quoted(text: string): string {
  let value = text;
  const first = Array.from(value)[0];
  if (first !== undefined && "=+-@\t\r".includes(first)) value = `'${value}`;
  return `"${value.replaceAll('"', '""')}"`;
}

export function csv(sessions: readonly StudySession[]): string {
  const lines = [CSV_HEADER];
  for (const s of sessions) {
    lines.push([
      isoUtc(s.start), s.localStart ?? "", String(Math.trunc((s.seconds + 30) / 60)), String(s.plannedMinutes),
      s.completed ? "si" : "no", quoted(s.subject ?? ""), s.pet ?? "", s.rating ?? "", quoted(s.note ?? ""),
      quoted((s.notes ?? []).join(" | ")),
    ].join(","));
  }
  return lines.join("\n") + "\n";
}
