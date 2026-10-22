// La scheda «Anno» delle statistiche (windows/src/core/yearStats.ts e i testi in dashboard.ts): le stesse prove della versione per Mac
// ("Anno: mappa, numeri e andamento" in tests/main.swift). Il confronto con Swift su altri dati è in contratto.test.ts.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import type { StudySession } from "../src/core/log.ts";
import { dayText, monthLabel, periodTitle, trendCaption, weekText, yearTiles } from "../src/core/dashboard.ts";
import { periodContaining, shiftedPeriod, summarize } from "../src/core/stats.ts";
import { cellOf, columnsOf, highlights, level, monthStarts, showsTrend, trendSubjects, weeklyTrend, yearDays } from "../src/core/yearStats.ts";
import { date, session, wall, ZONE } from "./util.ts";

const pad = (n: number): string => String(n).padStart(2, "0");

function ys(m: number, d: number, h = 10, seconds = 3000, y = 2026, subject: string | undefined = "Anatomia"): StudySession {
  return session({
    start: date(y, m, d, h), localStart: `${y}-${pad(m)}-${pad(d)}T${pad(h)}:00`, seconds, plannedMinutes: 50,
    ...(subject !== undefined ? { subject } : {}),
  });
}

const year2026 = periodContaining(wall(2026, 10, 22, 12), "year");
const NOW = wall(2026, 10, 22, 12);

describe("Il periodo «anno»", () => {
  it("dal 1 gennaio all'anno dopo, e l'anno prima e quello dopo", () => {
    assert.equal(year2026.start, wall(2026, 1, 1));
    assert.equal(year2026.end, wall(2027, 1, 1));
    assert.equal(shiftedPeriod(year2026, -1).start, wall(2025, 1, 1));
    assert.equal(shiftedPeriod(year2026, 1).start, wall(2027, 1, 1));
    assert.equal(periodTitle(year2026), "2026");
  });

  it("una barra per giorno: 365, o 366 in un anno bisestile", () => {
    assert.equal(summarize([], year2026, ZONE).buckets.length, 365);
    assert.equal(summarize([], periodContaining(wall(2024, 5, 1), "year"), ZONE).buckets.length, 366);
  });
});

describe("I giorni della mappa", () => {
  it("i livelli di colore (soglie a 30, 90 e 180 minuti)", () => {
    assert.deepEqual([0, 1, 1799, 1800, 5399, 5400, 10799, 10800, 40_000].map(level), [0, 1, 1, 2, 2, 3, 3, 4, 4]);
  });

  const sessions = [
    ys(10, 12, 9, 1800), ys(10, 12, 15, 3000), ys(10, 13, 10, 600), ys(10, 14, 10, 1500),
    ys(3, 3, 10, 7200, 2026, "Chimica"), ys(3, 4, 10, 1000, 2026, "chimica"),
    ys(12, 31, 23, 3000, 2025), ys(1, 2, 8, 900, 2026, undefined),
  ];

  it("un elemento per ogni giorno, con i secondi, i focus e il livello", () => {
    const days = yearDays(sessions, year2026, ZONE);
    assert.equal(days.length, 365);
    assert.equal(days[0]!.start, wall(2026, 1, 1));
    assert.equal(days[364]!.start, wall(2026, 12, 31));
    assert.deepEqual(days.find((day) => day.start === wall(2026, 10, 12)), { start: wall(2026, 10, 12), seconds: 4800, focusCount: 2, level: 2 });
    assert.equal(days.find((day) => day.start === wall(2026, 1, 2))!.level, 1);
    assert.equal(days.find((day) => day.start === wall(2026, 1, 3))!.level, 0);
    assert.equal(days.reduce((total, day) => total + day.seconds, 0), 1800 + 3000 + 600 + 1500 + 7200 + 1000 + 900, "il 31 dicembre dell'anno prima non conta");
  });

  it("i tre numeri: giorni, serie, giorno più forte, mese migliore", () => {
    const found = highlights(sessions, year2026, date(2026, 10, 22, 12), ZONE);
    assert.equal(found.studiedDays, 6);
    assert.deepEqual(found.bestDay, { start: wall(2026, 3, 3), seconds: 7200 });
    assert.deepEqual(found.bestMonth, { start: wall(2026, 3, 1), seconds: 8200 });
    assert.equal(found.longestStreak, 3);
  });

  it("il giorno di ghiaccio non interrompe la serie; a pari merito vince il primo; senza studio, niente", () => {
    assert.equal(highlights([ys(10, 12), ys(10, 13), ys(10, 15)], year2026, date(2026, 10, 22, 12), ZONE).longestStreak, 3);
    const tie = highlights([ys(5, 20, 10, 3600), ys(2, 10, 10, 3600)], year2026, date(2026, 10, 22, 12), ZONE);
    assert.equal(tie.bestDay?.start, wall(2026, 2, 10));
    assert.equal(tie.bestMonth?.start, wall(2026, 2, 1));
    assert.deepEqual(highlights([], year2026, date(2026, 10, 22, 12), ZONE), { studiedDays: 0, longestStreak: 0, bestDay: null, bestMonth: null });
  });
});

describe("La griglia", () => {
  it("una colonna per settimana (da lunedì) e una riga per giorno", () => {
    assert.deepEqual(cellOf(wall(2026, 1, 1), year2026), { column: 0, row: 3 });
    assert.deepEqual(cellOf(wall(2026, 1, 5), year2026), { column: 1, row: 0 });
    assert.deepEqual(cellOf(wall(2026, 12, 31), year2026), { column: 52, row: 3 });
    assert.equal(columnsOf(year2026), 53);
  });

  it("54 colonne in un anno bisestile che comincia di domenica (il 2012), 53 nel 2028", () => {
    assert.equal(columnsOf(periodContaining(wall(2012, 6, 1), "year")), 54);
    assert.equal(columnsOf(periodContaining(wall(2028, 6, 1), "year")), 53);
  });

  it("dove comincia ogni mese", () => {
    const marks = monthStarts(year2026);
    assert.equal(marks.length, 12);
    assert.deepEqual(marks[0], { month: 1, column: 0 });
    assert.equal(marks.find((m) => m.month === 2)!.column, 4);
    assert.equal(marks.find((m) => m.month === 10)!.column, 39);
    assert.equal(marks[11]!.month, 12);
  });
});

describe("L'andamento per settimana", () => {
  const sessions = [
    ys(10, 12, 9, 1800), ys(10, 12, 15, 3000), ys(10, 13, 10, 600), ys(10, 14, 10, 1500),
    ys(3, 3, 10, 7200, 2026, "Chimica"), ys(3, 4, 10, 1000, 2026, "chimica"), ys(12, 31, 23, 3000, 2025), ys(1, 2, 8, 900, 2026, undefined),
  ];
  const through = NOW;

  it("43 settimane fino a oggi, la prima da lunedì 29 dicembre, con solo i giorni dell'anno", () => {
    const all = weeklyTrend(sessions, year2026, null, through, ZONE);
    assert.equal(all.length, 43);
    assert.equal(all[0]!.start, wall(2025, 12, 29));
    assert.equal(all[42]!.start, wall(2026, 10, 19));
    assert.equal(all[0]!.seconds, 900);
    assert.equal(all.find((w) => w.start === wall(2026, 10, 12))!.seconds, 1800 + 3000 + 600 + 1500);
  });

  it("una materia: le scritture diverse contano insieme; mai studiata, tutto a zero; un anno passato ha tutte le settimane", () => {
    const chemistry = weeklyTrend(sessions, year2026, "CHIMICA", through, ZONE);
    assert.equal(chemistry.find((w) => w.start === wall(2026, 3, 2))!.seconds, 8200);
    assert.equal(chemistry.reduce((total, w) => total + w.seconds, 0), 8200);
    assert.ok(weeklyTrend(sessions, year2026, "Fisica", through, ZONE).every((w) => w.seconds === 0));
    assert.equal(weeklyTrend(sessions, year2026, null, wall(2030, 1, 1), ZONE).length, 53);
  });

  it("le materie tra cui scegliere: senza «Senza materia», al massimo cinque, nessuna se ce n'è una sola", () => {
    const names = trendSubjects(summarize(sessions, year2026, ZONE));
    assert.equal(names.length, 2);
    assert.ok(names.includes("Anatomia"));
    assert.deepEqual(trendSubjects(summarize([ys(3, 3)], year2026, ZONE)), []);
    const many = Array.from({ length: 8 }, (_, i) => ys(3, 1 + i, 10, 600 * (i + 1), 2026, `Materia ${i}`));
    assert.equal(trendSubjects(summarize(many, year2026, ZONE)).length, 5);
  });

  it("l'andamento si mostra da quattro settimane con studio", () => {
    const week = (day: number, seconds: number) => ({ start: wall(2026, 1, day), seconds });
    assert.equal(showsTrend([week(5, 600), week(12, 600), week(19, 600), week(26, 0)]), false);
    assert.equal(showsTrend([week(5, 60), week(12, 60), week(19, 60), week(26, 60)]), true);
  });
});

describe("I testi della scheda «Anno»", () => {
  it("passando sopra un giorno", () => {
    assert.equal(dayText({ start: wall(2026, 10, 2), seconds: 0, focusCount: 0 }), "Venerdì 2 ottobre · nessun focus");
    assert.equal(dayText({ start: wall(2026, 10, 14), seconds: 7800, focusCount: 3 }), "Mercoledì 14 ottobre · 2 h 10 · 3 focus");
    assert.equal(dayText({ start: wall(2026, 10, 14), seconds: 1500, focusCount: 1 }), "Mercoledì 14 ottobre · 25 min · 1 focus");
  });

  it("passando sopra una barra e la didascalia", () => {
    assert.equal(weekText({ start: wall(2026, 6, 29), seconds: 34_500 }), "Settimana del 29 giu · 9 h 35");
    assert.equal(trendCaption(55_800), "al massimo 15 h 30 in una settimana");
  });

  it("le tre caselle, e senza studio la sola serie", () => {
    const sessions = [ys(10, 12, 9, 1800), ys(10, 12, 15, 3000), ys(10, 13, 10, 600), ys(10, 14, 10, 1500), ys(3, 3, 10, 7200, 2026, "Chimica"), ys(3, 4, 10, 1000)];
    assert.deepEqual(yearTiles(highlights(sessions, year2026, date(2026, 10, 22, 12), ZONE)), [
      { value: "3 giorni", caption: "la serie più lunga" },
      { value: "2 h", caption: "il giorno più forte · 3 mar" },
      { value: "Marzo", caption: "il mese migliore · 2 h 17" },
    ]);
    assert.deepEqual(yearTiles({ studiedDays: 0, longestStreak: 1, bestDay: null, bestMonth: null }), [{ value: "1 giorno", caption: "la serie più lunga" }]);
  });

  it("i nomi dei mesi", () => {
    assert.equal(Array.from({ length: 12 }, (_, i) => monthLabel(i + 1)).join(" "), "gen feb mar apr mag giu lug ago set ott nov dic");
  });
});

