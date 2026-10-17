// Le prove delle statistiche (windows/src/core/stats.ts, streak, punti, CSV): le stesse della versione per Mac.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { analyzeStreak, dayLine, duration, encouragement, insights, periodContaining, secondsOnDayOf, shiftedPeriod,
  periodContains, startTime, summarize } from "../src/core/stats.ts";
import type { PeriodKind, StreakResult } from "../src/core/stats.ts";
import { balance, earnedPoints, multiplierForStreak, multiplierToday, progressToNextPoint, weightedMinutes } from "../src/core/points.ts";
import { CSV_HEADER, csv } from "../src/core/csv.ts";
import { DAY_MS } from "../src/core/time.ts";
import { date, rated, session, wall, ZONE } from "./util.ts";

const day = (y: number, m: number, d: number): number => Math.floor(wall(y, m, d) / DAY_MS);

describe("Periodi", () => {
  const wed = wall(2026, 10, 14, 11, 30);
  it("giorno, settimana (da lunedì) e mese", () => {
    const week = periodContaining(wed, "week");
    assert.equal(week.start, wall(2026, 10, 12));
    assert.equal(week.end, wall(2026, 10, 19));
    const month = periodContaining(wed, "month");
    assert.ok(month.start === wall(2026, 10, 1) && month.end === wall(2026, 11, 1));
    const dayPeriod = periodContaining(wed, "day");
    assert.ok(dayPeriod.start === wall(2026, 10, 14) && dayPeriod.end === wall(2026, 10, 15));
    assert.equal(shiftedPeriod(week, -1).start, wall(2026, 10, 5), "settimana precedente");
    assert.equal(shiftedPeriod(month, 1).start, wall(2026, 11, 1), "mese dopo");
    assert.ok(periodContains(dayPeriod, wed) && !periodContains(dayPeriod, wall(2026, 10, 15)), "fine esclusa");
  });
  it("il giorno del cambio d'ora finisce a mezzanotte", () => {
    assert.equal(periodContaining(wall(2026, 10, 25, 12), "day").end, wall(2026, 10, 26));
  });
  it("un mese che attraversa l'anno", () => {
    assert.equal(shiftedPeriod(periodContaining(wall(2026, 12, 15), "month"), 1).start, wall(2027, 1, 1));
    assert.equal(shiftedPeriod(periodContaining(wall(2026, 1, 31), "month"), 1).start, wall(2026, 2, 1));
  });
});

describe("Riepiloghi", () => {
  const sessions = [
    session({ start: date(2026, 10, 12, 9), seconds: 1800, plannedMinutes: 30, subject: "Fisiologia" }),
    session({ start: date(2026, 10, 12, 15), seconds: 3000, plannedMinutes: 50, subject: "Anatomia" }),
    session({ start: date(2026, 10, 12, 23, 40), seconds: 3000, plannedMinutes: 50, subject: "Anatomia" }),  // passa la mezzanotte
    session({ start: date(2026, 10, 13, 10), seconds: 600, plannedMinutes: 25, completed: false }),
    session({ start: date(2026, 10, 14, 10), seconds: 1500, plannedMinutes: 25, subject: "Anatomia" }),
    session({ start: date(2026, 9, 30, 10), seconds: 900, plannedMinutes: 15, subject: "Fisica" }),
  ];
  const summaryFor = (kind: PeriodKind, ref: number) => summarize(sessions, periodContaining(ref, kind), ZONE);

  it("lunedì", () => {
    const mon = summaryFor("day", wall(2026, 10, 12));
    assert.equal(mon.focusCount, 3);
    assert.equal(mon.totalSeconds, 7800, "la sessione di mezzanotte conta al giorno d'inizio");
    assert.ok(mon.completedCount === 3 && mon.interruptedCount === 0);
    assert.equal(mon.buckets.length, 24);
    assert.ok(mon.buckets[9]?.seconds === 1800 && mon.buckets[15]?.seconds === 3000 && mon.buckets[23]?.seconds === 3000);
    assert.ok(mon.bySubject[0]?.subject === "Anatomia" && mon.bySubject[0].seconds === 6000);
  });
  it("la settimana", () => {
    const wk = summaryFor("week", wall(2026, 10, 14));
    assert.equal(wk.focusCount, 5);
    assert.equal(wk.totalSeconds, 1800 + 3000 + 3000 + 600 + 1500);
    assert.deepEqual(wk.buckets.map((b) => b.seconds), [7800, 600, 1500, 0, 0, 0, 0]);
    assert.ok(wk.completedCount === 4 && wk.interruptedCount === 1);
    assert.deepEqual(wk.bySubject.map((x) => x.subject), ["Anatomia", "Fisiologia", "Senza materia"]);
    assert.equal(wk.sessions[0]?.start, date(2026, 10, 14, 10), "la più recente per prima");
  });
  it("il mese, settembre e un periodo vuoto", () => {
    const mo = summaryFor("month", wall(2026, 10, 14));
    assert.ok(mo.focusCount === 5 && mo.buckets.length === 31);
    const sep = summaryFor("month", wall(2026, 9, 15));
    assert.ok(sep.focusCount === 1 && sep.bySubject[0]?.subject === "Fisica");
    const empty = summaryFor("week", wall(2026, 8, 3));
    assert.ok(empty.focusCount === 0 && empty.totalSeconds === 0 && empty.bySubject.length === 0);
  });
  it("le scritture diverse di una materia non si separano", () => {
    const mixed = ["anatomia", "Anatomia", "ANATOMIA"].map((subject, i) =>
      session({ start: date(2026, 10, 12, 9 + i), seconds: 600, plannedMinutes: 10, subject }));
    const result = summarize(mixed, periodContaining(wall(2026, 10, 12), "day"), ZONE);
    assert.ok(result.bySubject.length === 1 && result.bySubject[0]?.seconds === 1800);
    assert.equal(result.bySubject[0]?.subject, "ANATOMIA", "si mostra la scrittura più recente");
  });
  it("i voti del periodo", () => {
    const set = [
      session({ start: date(2026, 10, 12, 9), localStart: "2026-10-12T09:00", seconds: 1500, subject: "A", rating: "good" }),
      session({ start: date(2026, 10, 12, 11), localStart: "2026-10-12T11:00", seconds: 1500, subject: "A", rating: "poor" }),
      session({ start: date(2026, 10, 12, 15), localStart: "2026-10-12T15:00", seconds: 1500, subject: "B" }),
    ];
    const result = summarize(set, periodContaining(wall(2026, 10, 12), "day"), ZONE);
    assert.deepEqual(result.ratingCounts, { good: 1, poor: 1 });
  });
  it("i secondi del giorno", () => {
    const a = session({ start: date(2026, 10, 14, 9), seconds: 1800 });
    assert.equal(secondsOnDayOf(a, [a, session({ start: date(2026, 10, 14, 15), seconds: 1200 })], ZONE), 3000);
  });
});

describe("Fuso orario", () => {
  const lateRome = session({ start: date(2026, 10, 14, 23, 30), localStart: "2026-10-14T23:30", seconds: 1800, plannedMinutes: 30 });
  const tokyo = "Asia/Tokyo";
  it("una sessione serale a Roma resta nel suo giorno anche letta con un altro fuso", () => {
    const same = summarize([lateRome], periodContaining(wall(2026, 10, 14, 12), "day"), tokyo);
    assert.equal(same.focusCount, 1);
    assert.equal(summarize([lateRome], periodContaining(wall(2026, 10, 15, 12), "day"), tokyo).focusCount, 0);
    assert.ok(same.buckets.length === 24 && same.buckets[23]?.seconds === 1800, "all'ora 23, quella dell'orologio");
  });
  it("senza ora locale vale l'istante; con un'ora locale illeggibile si ricade sull'istante", () => {
    const instant = date(2026, 10, 14, 9);
    assert.equal(startTime(session({ start: instant, seconds: 600 }), ZONE), wall(2026, 10, 14, 9));
    assert.equal(startTime(session({ start: instant, seconds: 600, localStart: "boh" }), ZONE), wall(2026, 10, 14, 9));
  });
  it("i giorni di fila usano l'ora locale", () => {
    assert.equal(analyzeStreak([lateRome], date(2026, 10, 15, 8), tokyo).days, 1);
  });
});

describe("Giorni di fila e serie ghiacciata", () => {
  const s = (d: number) => session({ start: date(2026, 10, d, 10), seconds: 600, plannedMinutes: 10 });
  const analysis = (days: number[], today: number, hour = 20): StreakResult =>
    analyzeStreak(days.map(s), date(2026, 10, today, hour), ZONE);
  const streak = (days: number[], todayDay: number, hour = 20): number => analysis(days, todayDay, hour).days;

  it("la serie", () => {
    assert.equal(streak([12, 13, 14], 14), 3, "tre di fila");
    assert.equal(streak([11, 13, 14], 14), 3, "un giorno saltato la ghiaccia");
    assert.equal(streak([10, 13, 14], 14), 2, "due giorni di fila senza studio la spezzano");
    assert.equal(streak([12, 13], 14, 8), 2, "oggi ancora vuoto: conta da ieri");
    assert.equal(streak([10], 14, 8), 0, "serie finita");
    assert.equal(streak([], 14), 0, "senza sessioni");
    assert.equal(streak([14, 14], 14, 12), 1, "due nello stesso giorno = 1");
  });
  it("il ghiaccio", () => {
    const straight = analysis([12, 13, 14], 14);
    assert.ok(straight.days === 3 && straight.perDay.get(day(2026, 10, 12)) === 1 && straight.perDay.get(day(2026, 10, 14)) === 3
      && !straight.isFrozen && straight.studiedToday);
    const oneGap = analysis([11, 13, 14], 14);
    assert.ok(oneGap.days === 3 && oneGap.perDay.get(day(2026, 10, 13)) === 2 && oneGap.perDay.get(day(2026, 10, 14)) === 3);
    const twoGaps = analysis([10, 13, 14], 14);
    assert.ok(twoGaps.days === 2 && twoGaps.perDay.get(day(2026, 10, 13)) === 1);
    const tooOften = analysis([10, 12, 14], 14);
    assert.ok(tooOften.perDay.get(day(2026, 10, 12)) === 2 && tooOften.perDay.get(day(2026, 10, 14)) === 1 && tooOften.days === 1,
      "il ghiaccio non si usa due volte in meno di una settimana");
    const reusable = analysis([1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 13], 13);
    assert.ok(reusable.days === 11 && reusable.perDay.get(day(2026, 10, 13)) === 11, "dopo sette giorni si può riusare");
    const sixApart = analysis([1, 3, 4, 5, 6, 7, 9], 9);
    assert.ok(sixApart.days === 1 && sixApart.perDay.get(day(2026, 10, 9)) === 1, "a sei giorni dal ghiaccio precedente non si riusa");
    const sevenApart = analysis([1, 3, 4, 5, 6, 7, 8, 10], 10);
    assert.ok(sevenApart.days === 8 && sevenApart.perDay.get(day(2026, 10, 10)) === 8, "a sette giorni sì");
    const frozenNow = analysis([12, 13], 15, 8);
    assert.ok(frozenNow.days === 2 && frozenNow.isFrozen && !frozenNow.studiedToday, "ieri saltato, oggi ancora vuoto: ghiacciata");
    const thawed = analysis([12, 13, 15], 15);
    assert.ok(thawed.days === 3 && !thawed.isFrozen && thawed.studiedToday, "studiando oggi si scongela e continua");
    const notYet = analysis([12, 13], 14, 8);
    assert.ok(notYet.days === 2 && !notYet.isFrozen, "oggi ancora vuoto ma ieri sì: niente ghiaccio");
    const lost = analysis([11], 14, 8);
    assert.ok(lost.days === 0 && !lost.isFrozen, "il ghiaccio non salva due giorni di fila");
    assert.ok(analysis([], 14).days === 0 && !analysis([], 14).isFrozen);
    assert.equal(analysis([14, 14], 14).perDay.get(day(2026, 10, 14)), 1);
  });

  describe("Punti del giardino", () => {
    const studyHour = (d: number, minutes = 60, completed = true) =>
      session({ start: date(2026, 10, d, 10), seconds: minutes * 60, plannedMinutes: 60, completed });
    it("i moltiplicatori", () => {
      assert.ok(multiplierForStreak(0) === 1 && multiplierForStreak(2) === 1);
      assert.ok(multiplierForStreak(3) === 1.25 && multiplierForStreak(6) === 1.25);
      assert.ok(multiplierForStreak(7) === 1.5 && multiplierForStreak(13) === 1.5);
      assert.ok(multiplierForStreak(14) === 2 && multiplierForStreak(90) === 2);
    });
    it("due settimane di fila: 2×60 + 4×60×1,25 + 7×60×1,5 + 1×60×2 = 1170 minuti", () => {
      const fortnight = Array.from({ length: 14 }, (_, i) => studyHour(i + 1));
      const now = date(2026, 10, 14, 20);
      const minutes = weightedMinutes(fortnight, now, ZONE);
      assert.ok(Math.abs(minutes - 1170) < 0.001, String(minutes));
      assert.equal(earnedPoints(fortnight, now, ZONE), 19);
      assert.ok(Math.abs(progressToNextPoint(minutes) - 0.5) < 0.001);
    });
    it("senza serie un'ora è un punto; i minuti interrotti contano", () => {
      assert.equal(earnedPoints([studyHour(1), studyHour(5), studyHour(12)], date(2026, 10, 12, 20), ZONE), 3);
      const interrupted = [studyHour(1, 30, false)];
      assert.equal(earnedPoints(interrupted, date(2026, 10, 1, 20), ZONE), 0);
      assert.ok(Math.abs(weightedMinutes(interrupted, date(2026, 10, 1, 20), ZONE) - 30) < 0.001);
      assert.equal(earnedPoints([], date(2026, 10, 1), ZONE), 0);
    });
    it("il saldo non va sotto zero, e il valore di un minuto oggi", () => {
      assert.ok(balance(5, 3) === 2 && balance(2, 5) === 0);
      assert.equal(multiplierToday(analysis([12, 13], 14, 8)), 1.25);
      assert.equal(multiplierToday(analysis([12, 13, 14], 14)), 1.25);
      assert.equal(multiplierToday(analysis([], 14)), 1);
    });
  });
});

describe("Testi", () => {
  const day12 = summarize([
    session({ start: date(2026, 10, 12, 9), seconds: 1800 }),
    session({ start: date(2026, 10, 12, 15), seconds: 3000 }),
    session({ start: date(2026, 10, 12, 23, 40), seconds: 3000 }),
  ], periodContaining(wall(2026, 10, 12), "day"), ZONE);
  const empty = summarize([], periodContaining(wall(2026, 10, 12), "day"), ZONE);
  it("la durata", () => {
    assert.equal(duration(0), "0 min");
    assert.equal(duration(2700), "45 min");
    assert.equal(duration(3600), "1 h");
    assert.equal(duration(12_000), "3 h 20");
    assert.equal(duration(3900), "1 h 05");
  });
  it("la riga del giorno", () => {
    assert.equal(dayLine(day12, true, "Lunedì"), "Oggi hai fatto 3 focus: 2 h 10 di studio.");
    assert.equal(dayLine(empty, true, ""), "Oggi non hai ancora fatto nessun focus.");
    assert.equal(dayLine(empty, false, "Lunedì"), "Lunedì non hai fatto nessun focus.");
    const one = summarize([session({ start: date(2026, 10, 13, 10), seconds: 600 })], periodContaining(wall(2026, 10, 13), "day"), ZONE);
    assert.equal(dayLine(one, false, "Martedì"), "Martedì hai fatto 1 focus: 10 min di studio.");
  });
  it("gli incoraggiamenti", () => {
    assert.ok(encouragement(0) !== "" && encouragement(20_000) !== "");
    assert.notEqual(encouragement(0), encouragement(20_000));
  });
});

describe("Quando rendi meglio", () => {
  it("pochi voti: nessuna frase", () => {
    const few = [rated(12, 9, "A", "good"), rated(12, 11, "A", "poor"), rated(12, 15, "B", "good")];
    assert.deepEqual(insights(few, ZONE), []);
  });
  it("con abbastanza voti compare la fascia migliore, con i conteggi", () => {
    const many = [
      ...[0, 1, 2, 3].map((i) => rated(5 + i, 9, i % 2 === 0 ? "Anatomia" : "Chimica", "good")),
      ...[0, 1, 2, 3].map((i) => rated(5 + i, 21, i % 2 === 0 ? "Anatomia" : "Chimica", "poor")),
    ];
    const found = insights(many, ZONE);
    assert.ok(found.length >= 1 && found.length <= 2, String(found));
    assert.ok(found.some((line) => line.includes("di mattina") && line.includes("4 focus su 4")), String(found));
  });
  it("nessuna differenza: nessuna frase", () => {
    const flat = Array.from({ length: 10 }, (_, i) => rated(5 + (i % 5), Math.floor(i / 2) % 2 === 0 ? 9 : 16, "Anatomia", i % 2 === 0 ? "good" : "poor"));
    assert.deepEqual(insights(flat, ZONE), []);
  });
});

describe("Esportazione CSV", () => {
  it("intestazione, campi di testo protetti e virgolette raddoppiate", () => {
    const text = csv([session({ start: date(2026, 10, 14, 9), localStart: "2026-10-14T09:00", seconds: 1500, plannedMinutes: 25,
      subject: "=SOMMA(A1)", pet: "pianty", rating: "good", note: 'cap. 4, "nervi"' })]);
    assert.ok(text.startsWith(CSV_HEADER + "\n"));
    assert.ok(text.includes(',"\'=SOMMA(A1)",pianty,good,"cap. 4, ""nervi"""'), text);
  });
});
