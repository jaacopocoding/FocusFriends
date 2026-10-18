// Fuso orario e ora legale (windows/src/core/time.ts): il computer può cambiare fuso mentre l'app è aperta, e due volte
// l'anno un giorno dura 23 o 25 ore. Le statistiche contano i giorni «sull'orologio», quindi nulla di tutto questo deve
// spostare una sessione di giorno, perdere un giorno di una serie o contare un'ora due volte.

import { after, describe, it } from "node:test";
import assert from "node:assert/strict";
import { analyzeStreak, periodContaining, summarize } from "../src/core/stats.ts";
import { DAY_MS, dayString, localString, refreshSystemZone, startOfDay, systemZone, wallOf } from "../src/core/time.ts";
import { date, session, wall } from "./util.ts";

const utc = (y: number, m: number, d: number, h = 0, min = 0): number => Date.UTC(y, m - 1, d, h, min);
const clock = (instant: number, zone: string): string => localString(wallOf(instant, zone));

describe("Il fuso del computer cambia mentre l'app gira", () => {
  const original = process.env["TZ"];
  after(() => {
    if (original === undefined) delete process.env["TZ"]; else process.env["TZ"] = original;
    refreshSystemZone();
  });

  const noon = utc(2026, 10, 14, 10, 0);

  it("dopo uno sleep o un viaggio l'orologio segue il fuso nuovo", () => {
    process.env["TZ"] = "Europe/Rome";
    refreshSystemZone();
    assert.equal(localString(wallOf(noon)), "2026-10-14T12:00");
    process.env["TZ"] = "Asia/Tokyo";
    refreshSystemZone();
    assert.equal(localString(wallOf(noon)), "2026-10-14T19:00");
    process.env["TZ"] = "America/Los_Angeles";
    refreshSystemZone();
    assert.equal(localString(wallOf(noon)), "2026-10-14T03:00");
  });

  it("anche senza che nessuno lo dica, il fuso si rilegge dopo cinque secondi", () => {
    process.env["TZ"] = "Europe/Rome";
    refreshSystemZone();
    assert.equal(systemZone(1_000), "Europe/Rome");
    process.env["TZ"] = "Asia/Tokyo";
    assert.equal(systemZone(1_001), "Europe/Rome", "dentro i cinque secondi non si rilegge ogni volta");
    assert.equal(systemZone(6_000), "Asia/Tokyo");
    assert.equal(systemZone(4_000), "Asia/Tokyo", "un orologio di sistema portato indietro si rilegge, non si fida");
  });

  it("un fuso scelto esplicitamente non dipende da quello del computer", () => {
    process.env["TZ"] = "Asia/Tokyo";
    refreshSystemZone();
    assert.equal(clock(noon, "Europe/Rome"), "2026-10-14T12:00");
  });
});

describe("Il giorno del cambio d'ora", () => {
  const rome = "Europe/Rome";

  it("a ottobre (alle 3 si torna alle 2) il giorno dura 25 ore ma resta un giorno solo", () => {
    const start = utc(2026, 10, 24, 22, 0);          // 00:00 del 25 ottobre a Roma (ancora ora legale)
    const end = utc(2026, 10, 25, 23, 0);            // 00:00 del 26 ottobre (ora solare)
    assert.equal(end - start, 25 * 3_600_000);
    assert.equal(clock(start, rome), "2026-10-25T00:00");
    assert.equal(clock(end - 1000, rome), "2026-10-25T23:59");
    assert.equal(clock(end, rome), "2026-10-26T00:00");
    assert.equal(startOfDay(wallOf(start, rome)), startOfDay(wallOf(end - 1000, rome)));
  });

  it("l'ora ripetuta (02:30 due volte) è la stessa ora sull'orologio", () => {
    const first = utc(2026, 10, 25, 0, 30);          // 02:30 ora legale
    const second = utc(2026, 10, 25, 1, 30);         // 02:30 ora solare
    assert.equal(clock(first, rome), "2026-10-25T02:30");
    assert.equal(clock(second, rome), "2026-10-25T02:30");
  });

  it("a marzo (alle 2 si va alle 3) il giorno dura 23 ore e l'ora che manca non c'è", () => {
    const start = utc(2026, 3, 28, 23, 0);           // 00:00 del 29 marzo
    const end = utc(2026, 3, 29, 22, 0);             // 00:00 del 30 marzo (ora legale)
    assert.equal(end - start, 23 * 3_600_000);
    assert.equal(clock(utc(2026, 3, 29, 0, 59), rome), "2026-03-29T01:59");
    assert.equal(clock(utc(2026, 3, 29, 1, 0), rome), "2026-03-29T03:00", "dalle 01:59 si salta alle 03:00");
  });

  it("le sessioni di una settimana con il cambio d'ora vanno ognuna al suo giorno", () => {
    // Ogni giorno una sessione appena dopo mezzanotte e una poco prima, dal 19 (lunedì) al 26 ottobre; senza ora locale
    // registrata, quindi vale l'istante letto sull'orologio di Roma.
    const sessions = [];
    for (let day = 19; day <= 26; day += 1) {
      sessions.push(session({ start: date(2026, 10, day, 0, 30), seconds: 1800 }));
      sessions.push(session({ start: date(2026, 10, day, 23, 30), seconds: 600 }));
    }
    const week = summarize(sessions, periodContaining(wall(2026, 10, 21, 12), "week"), rome);
    assert.equal(week.buckets.length, 7);
    assert.deepEqual(week.buckets.map((b) => b.seconds), [2400, 2400, 2400, 2400, 2400, 2400, 2400]);
    assert.equal(week.focusCount, 14);
    assert.equal(week.totalSeconds, 7 * 2400);
    const sunday = summarize(sessions, periodContaining(wall(2026, 10, 25, 12), "day"), rome);
    assert.equal(sunday.focusCount, 2, "il giorno da 25 ore ha le sue due sessioni");
    assert.equal(sunday.buckets.length, 24, "un giorno ha sempre 24 caselle, anche se dura 25 ore");
  });

  it("la serie di giorni non perde un giorno attraverso il cambio d'ora", () => {
    // Uno studio ogni giorno alle 23:30 sull'orologio dal 22 al 27 ottobre: sei giorni.
    const days = [22, 23, 24, 25, 26, 27].map((d) => session({ start: date(2026, 10, d, 23, 30), seconds: 600 }));
    assert.equal(analyzeStreak(days, date(2026, 10, 27, 23, 45), rome).days, 6);
    // E alle 00:30, il giorno di ottobre che dura 25 ore e quello di marzo che ne dura 23.
    const early = [23, 24, 25, 26, 27].map((d) => session({ start: date(2026, 10, d, 0, 30), seconds: 600 }));
    assert.equal(analyzeStreak(early, date(2026, 10, 27, 12), rome).days, 5);
    const march = [27, 28, 29, 30, 31].map((d) => session({ start: date(2026, 3, d, 23, 30), seconds: 600 }));
    assert.equal(analyzeStreak(march, date(2026, 3, 31, 23, 45), rome).days, 5);
  });

  it("il «giorno» di oggi parte da mezzanotte anche il giorno del cambio", () => {
    const after = utc(2026, 10, 25, 23, 30);         // 00:30 del 26 ottobre... ora solare, quindi 00:30
    const today = periodContaining(wallOf(after, rome), "day");
    assert.equal(dayString(today.start), "2026-10-26");
    assert.equal(today.end - today.start, DAY_MS);
  });
});

describe("Fusi strani", () => {
  it("mezz'ore e tre quarti d'ora", () => {
    const noonUtc = utc(2026, 10, 14, 12, 0);
    assert.equal(clock(noonUtc, "Asia/Kolkata"), "2026-10-14T17:30");
    assert.equal(clock(noonUtc, "Asia/Kathmandu"), "2026-10-14T17:45");
    assert.equal(clock(noonUtc, "Australia/Adelaide"), "2026-10-14T22:30");
  });

  it("Lord Howe cambia l'ora di mezz'ora", () => {
    // A ottobre 2026 l'ora legale comincia alle 02:00 del 4 e porta l'orologio a 02:30.
    assert.equal(clock(utc(2026, 10, 3, 15, 29), "Australia/Lord_Howe"), "2026-10-04T01:59");
    assert.equal(clock(utc(2026, 10, 3, 15, 30), "Australia/Lord_Howe"), "2026-10-04T02:30");
  });

  it("emisfero australe: l'ora legale comincia a ottobre", () => {
    assert.equal(clock(utc(2026, 10, 3, 15, 59), "Australia/Sydney"), "2026-10-04T01:59");
    assert.equal(clock(utc(2026, 10, 3, 16, 0), "Australia/Sydney"), "2026-10-04T03:00");
  });

  it("oltre la linea del cambio di data", () => {
    const instant = utc(2026, 10, 14, 12, 0);
    assert.equal(clock(instant, "Pacific/Kiritimati"), "2026-10-15T02:00");      // UTC+14
    assert.equal(clock(instant, "Pacific/Pago_Pago"), "2026-10-14T01:00");       // UTC-11
  });

  it("una sessione serale vista da fusi lontani resta nel suo giorno (con l'ora locale registrata)", () => {
    const late = session({ start: utc(2026, 10, 14, 21, 30), localStart: "2026-10-14T23:30", seconds: 1800 });
    for (const zone of ["Pacific/Kiritimati", "Pacific/Pago_Pago", "America/Los_Angeles", "Asia/Kolkata"]) {
      assert.equal(summarize([late], periodContaining(wall(2026, 10, 14, 12), "day"), zone).focusCount, 1, zone);
      assert.equal(summarize([late], periodContaining(wall(2026, 10, 15, 12), "day"), zone).focusCount, 0, zone);
    }
  });
});
