// I testi e le liste della finestra delle statistiche (core/dashboard.ts).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { canGoNext, chartLabel, diaryEntries, focusNotesLine, periodTitle, secondaryLine, sessionHeading, streakLabel, subjectRows, subtitle } from "../src/core/dashboard.ts";
import { periodContaining, shiftedPeriod, summarize } from "../src/core/stats.ts";
import { date, session, wall, ZONE } from "./util.ts";

const sessions = [
  session({ start: date(2026, 10, 12, 9), seconds: 1800, plannedMinutes: 30, subject: "Fisiologia" }),
  session({ start: date(2026, 10, 12, 15), seconds: 3000, plannedMinutes: 50, subject: "Anatomia", rating: "good", note: "nervi cranici", notes: ["uno", "due"] }),
  session({ start: date(2026, 10, 13, 10), seconds: 600, plannedMinutes: 25, completed: false }),
  session({ start: date(2026, 10, 14, 10), seconds: 1500, plannedMinutes: 25, subject: "Anatomia" }),
];

describe("Titoli dei periodi", () => {
  it("giorno, settimana e mese in italiano", () => {
    assert.equal(periodTitle(periodContaining(wall(2026, 10, 14, 11), "day")), "Mercoledì 14 ottobre 2026");
    assert.equal(periodTitle(periodContaining(wall(2026, 10, 14, 11), "week")), "12 ott – 18 ott 2026");
    assert.equal(periodTitle(periodContaining(wall(2026, 10, 14, 11), "month")), "Ottobre 2026");
    assert.equal(periodTitle(shiftedPeriod(periodContaining(wall(2026, 10, 14), "week"), -1)), "5 ott – 11 ott 2026");
    assert.equal(periodTitle(periodContaining(wall(2026, 12, 30), "week")), "28 dic – 3 gen 2027");
  });
  it("si può andare avanti solo fino a oggi", () => {
    const now = wall(2026, 10, 14, 20);
    const day = periodContaining(now, "day");
    assert.equal(canGoNext(day, now), false);
    assert.equal(canGoNext(shiftedPeriod(day, -1), now), true);
    assert.equal(canGoNext(shiftedPeriod(day, 1), now), true, "come sul Mac: fino a un anno avanti");
    assert.equal(canGoNext(shiftedPeriod(day, 400), now), false);
  });
});

describe("Riepilogo", () => {
  const week = summarize(sessions, periodContaining(wall(2026, 10, 14), "week"), ZONE);
  it("sotto il numero", () => {
    assert.equal(subtitle(week), "di studio · 4 focus · 1 interrotto");
    assert.equal(subtitle(summarize([], periodContaining(wall(2026, 10, 14), "week"), ZONE)), "");
    const two = summarize([sessions[2]!, { ...sessions[2]!, id: "b" }], periodContaining(wall(2026, 10, 13), "day"), ZONE);
    assert.equal(subtitle(two), "di studio · 2 focus · 2 interrotti");
    assert.equal(subtitle(summarize([sessions[0]!], periodContaining(wall(2026, 10, 12), "day"), ZONE)), "di studio · 1 focus");
  });
  it("la riga in più", () => {
    assert.equal(secondaryLine(week, "week", true), "In media 38 min nei 3 giorni in cui hai studiato.");
    const empty = summarize([], periodContaining(wall(2026, 10, 14), "day"), ZONE);
    assert.equal(secondaryLine(empty, "day", true), "Quando vuoi, io sono qui.");
    assert.equal(secondaryLine(empty, "day", false), "Nessun focus in questo periodo.");
    const today = summarize([sessions[3]!], periodContaining(wall(2026, 10, 14), "day"), ZONE);
    assert.equal(secondaryLine(today, "day", true), "Un bell'inizio: ogni minuto conta.");
    assert.equal(secondaryLine(today, "day", false), "");
  });
  it("le materie: fino a sei, il resto in «Altre (n)»", () => {
    const rows = subjectRows(week);
    assert.deepEqual(rows.map((r) => [r.subject, r.seconds, r.muted]), [["Anatomia", 4500, false], ["Fisiologia", 1800, false], ["Senza materia", 600, true]]);
    const many = Array.from({ length: 9 }, (_, i) => session({ start: date(2026, 10, 12, 8 + i), seconds: 600 + i * 60, subject: `Materia ${i}` }));
    const big = subjectRows(summarize(many, periodContaining(wall(2026, 10, 12), "day"), ZONE));
    assert.equal(big.length, 7);
    assert.deepEqual([big[6]!.subject, big[6]!.muted], ["Altre (3)", true]);
    assert.equal(big[6]!.seconds, many.slice(0, 3).reduce((t, s) => t + s.seconds, 0));
  });
  it("la serie", () => {
    assert.equal(streakLabel(1, false), "1 giorno di fila");
    assert.equal(streakLabel(5, false), "5 giorni di fila");
    assert.equal(streakLabel(3, true), "3 giorni di fila · ghiacciata: studia oggi");
  });
  it("le etichette delle barre", () => {
    assert.equal(chartLabel("week", wall(2026, 10, 12)), "lun");
    assert.equal(chartLabel("month", wall(2026, 10, 1)), "1");
    assert.equal(chartLabel("month", wall(2026, 10, 5)), "5");
    assert.equal(chartLabel("month", wall(2026, 10, 6)), null);
    assert.equal(chartLabel("day", wall(2026, 10, 6, 9)), null);
  });
});

describe("Diario", () => {
  it("un giorno: la striscia delle ore e le sessioni dalla più antica", () => {
    const entries = diaryEntries(sessions.slice(0, 2), "day", ZONE);
    assert.deepEqual(entries.map((e) => e.type), ["strip", "session", "session"]);
    const strip = entries[0]!;
    assert.ok(strip.type === "strip" && strip.firstHour === 8 && strip.lastHour === 18);
    assert.ok(strip.type === "strip" && Math.abs(strip.blocks[1]!.startHour - 15) < 1e-9 && Math.abs(strip.blocks[1]!.endHour - (15 + 50 / 60)) < 1e-9);
    const first = entries[1]!;
    assert.ok(first.type === "session" && first.time === "09:00" && first.minutes === 30);
  });
  it("la striscia si allarga per una sessione notturna o prima delle 8", () => {
    const wide = diaryEntries([session({ start: date(2026, 10, 12, 6, 30), seconds: 1800 }), session({ start: date(2026, 10, 12, 22), seconds: 7200 })], "day", ZONE)[0]!;
    assert.ok(wide.type === "strip" && wide.firstHour === 6 && wide.lastHour === 24);
  });
  it("settimana: un'intestazione per ogni giorno, con il totale", () => {
    const entries = diaryEntries(sessions, "week", ZONE);
    assert.deepEqual(entries.map((e) => e.type), ["header", "session", "session", "header", "session", "header", "session"]);
    const headers = entries.flatMap((e) => (e.type === "header" ? [[e.title, e.seconds]] : []));
    assert.deepEqual(headers, [["Lunedì 12 ottobre", 4800], ["Martedì 13 ottobre", 600], ["Mercoledì 14 ottobre", 1500]]);
  });
  it("nessuna sessione: niente", () => {
    assert.deepEqual(diaryEntries([], "day", ZONE), []);
  });
  it("le note del focus su una riga, e il titolo della modifica", () => {
    assert.equal(focusNotesLine(sessions[1]!), "Note: uno  ·  due");
    assert.equal(focusNotesLine(sessions[0]!), null);
    assert.equal(sessionHeading(sessions[1]!, ZONE), "lunedì 12 ottobre, 15:00 · 50 min");
  });
});
