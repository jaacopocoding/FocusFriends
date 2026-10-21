// Le frasi «di contesto» del compagno (windows/src/core/remarks.ts e phraseChooser.ts): le stesse prove della versione per Mac
// ("Frasi di contesto" in tests/main.swift). I risultati sono confrontati con quelli di Swift anche in contratto.test.ts.

import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import { SessionLog } from "../src/core/log.ts";
import type { StudySession } from "../src/core/log.ts";
import { GRACE_SECONDS, PomodoroEngine } from "../src/core/pomodoro.ts";
import type { PomodoroEvent } from "../src/core/pomodoro.ts";
import { Profile } from "../src/core/profile.ts";
import { BreakCycle } from "../src/core/rules.ts";
import { Settings } from "../src/core/settings.ts";
import { refreshSystemZone } from "../src/core/time.ts";
import { ToDoList } from "../src/core/todoList.ts";
import { createRemarks } from "../src/main/remarks.ts";
import type { QuietSpeech } from "../src/shared/api.ts";
import { dayPart, insight, launchGreeting, milestone, wakeGreeting, weeklyRecap } from "../src/core/remarks.ts";
import type { RemarksContext } from "../src/core/remarks.ts";
import { PhraseChooser, REMINDER_EVERY_MS } from "../src/core/phraseChooser.ts";
import { insights } from "../src/core/stats.ts";
import { date, rated, session, tempDirectory, ZONE } from "./util.ts";

function rk(m: number, d: number, h = 10, seconds = 3000, y = 2026): StudySession {
  const start = date(y, m, d, h);
  const pad = (n: number): string => String(n).padStart(2, "0");
  return session({ start, localStart: `${y}-${pad(m)}-${pad(d)}T${pad(h)}:00`, seconds, plannedMinutes: 50, subject: "Anatomia" });
}

function context(now: number, extra: Partial<RemarksContext> = {}): RemarksContext {
  return { now, zone: ZONE, name: "Jacopo", sessions: [], openTodoCount: 0, due: null, ...extra };
}

const tuesdayMorning = date(2026, 10, 20, 9);

describe("Saluto dell'avvio", () => {
  it("le fasce della giornata", () => {
    assert.deepEqual([4, 5, 11, 12, 17, 18, 22, 23, 0].map(dayPart),
      ["night", "morning", "morning", "afternoon", "afternoon", "evening", "evening", "night", "night"]);
  });

  it("mattina, pomeriggio, sera e domenica, con o senza nome", () => {
    assert.equal(launchGreeting(context(tuesdayMorning), 0).text, "Buongiorno, Jacopo! Si comincia quando vuoi.");
    assert.equal(launchGreeting(context(tuesdayMorning, { name: null }), 0).text, "Buongiorno! Si comincia quando vuoi.");
    assert.ok(launchGreeting(context(date(2026, 10, 20, 15)), 0).text.startsWith("Buon pomeriggio, Jacopo!"));
    assert.ok(launchGreeting(context(date(2026, 10, 20, 20)), 0).text.startsWith("Buonasera, Jacopo!"));
    assert.ok(launchGreeting(context(date(2026, 10, 18, 10)), 0).text.startsWith("Buona domenica, Jacopo!"));
  });

  it("di notte", () => {
    const night = date(2026, 10, 20, 0, 30);
    assert.equal(launchGreeting(context(night), 0).text, "Jacopo, è tardi. Un ultimo focus e poi a dormire?");
    assert.equal(launchGreeting(context(night, { name: null }), 0).text, "È tardi. Un ultimo focus e poi a dormire?");
    assert.ok(launchGreeting(context(night), 1).text.includes("riposo"));
  });

  it("ieri, oggi, la serie e le cose da fare: una per volta", () => {
    assert.equal(launchGreeting(context(tuesdayMorning, { sessions: [rk(10, 19)] }), 0).text, "Buongiorno, Jacopo! Ieri hai studiato 50 min: si riparte?");
    assert.equal(launchGreeting(context(date(2026, 10, 20, 15), { sessions: [rk(10, 20, 9)] }), 0).text, "Buon pomeriggio, Jacopo! Oggi hai già studiato 50 min.");
    const streak = [rk(10, 17), rk(10, 18), rk(10, 19)];
    const lines = [0, 1, 2].map((variant) => launchGreeting(context(tuesdayMorning, { sessions: streak, openTodoCount: 2 }), variant).text);
    assert.deepEqual(lines, ["Buongiorno, Jacopo! Ieri hai studiato 50 min: si riparte?", "Buongiorno, Jacopo! Sei a 3 giorni di fila.", "Buongiorno, Jacopo! Hai 2 cose da fare."]);
    assert.equal(launchGreeting(context(tuesdayMorning, { sessions: streak, openTodoCount: 2 }), 3).text, lines[0], "la variante rientra sempre");
    assert.ok(launchGreeting(context(tuesdayMorning, { openTodoCount: 1 }), -1).text.length > 0);
    assert.equal(launchGreeting(context(tuesdayMorning, { openTodoCount: 1 }), 0).text, "Buongiorno, Jacopo! Hai 1 cosa da fare.");
  });

  it("se scade qualcosa è la prima cosa che dice, e non va ripetuta", () => {
    const due = "Oggi scade «Esercizi di analisi». Un focus adesso?";
    const withDue = launchGreeting(context(tuesdayMorning, { openTodoCount: 3, due }), 2);
    assert.deepEqual(withDue, { text: `Buongiorno, Jacopo! ${due}`, coversReminder: true });
    assert.equal(launchGreeting(context(tuesdayMorning), 0).coversReminder, false);
  });
});

describe("Saluto al risveglio", () => {
  it("niente se è passato poco; dopo un'ora «Rieccoti!»", () => {
    assert.equal(wakeGreeting(context(tuesdayMorning), 1800, 0), null);
    assert.equal(wakeGreeting(context(tuesdayMorning), 7200, 0)?.text, "Rieccoti!");
    assert.equal(wakeGreeting(context(tuesdayMorning), 7200, 1)?.text, "Eccoti di nuovo!");
    assert.equal(wakeGreeting(context(tuesdayMorning), 7200, 2)?.text, "Ti stavo aspettando!");
  });

  it("con le cose da fare, con lo studio di oggi, con una scadenza", () => {
    assert.equal(wakeGreeting(context(tuesdayMorning, { openTodoCount: 3 }), 7200, 0)?.text, "Rieccoti! Hai 3 cose da fare.");
    assert.equal(wakeGreeting(context(date(2026, 10, 20, 15), { sessions: [rk(10, 20, 9)], openTodoCount: 3 }), 7200, 0)?.text, "Rieccoti! Oggi sei a 50 min.");
    assert.equal(wakeGreeting(context(tuesdayMorning, { due: "Domani scade «Tesi»." }), 7200, 0)?.coversReminder, true);
  });
});

describe("Riepilogo della settimana", () => {
  const week = [rk(10, 12, 9, 3600), rk(10, 14, 15, 7800), rk(10, 16, 11, 1800)];
  const monday = date(2026, 10, 19, 9);

  it("la settimana scorsa, il lunedì, con il giorno più forte", () => {
    const recap = weeklyRecap(context(monday, { sessions: week }));
    assert.equal(recap?.key, "2026-10-12");
    assert.equal(recap?.text, "Settimana scorsa: 3 h 40 in 3 giorni, 3 focus. Il giorno più forte: mercoledì (2 h 10).");
  });

  it("fino al mercoledì, non da giovedì a domenica", () => {
    assert.equal(weeklyRecap(context(date(2026, 10, 21, 9), { sessions: week }))?.key, "2026-10-12");
    assert.equal(weeklyRecap(context(date(2026, 10, 22, 9), { sessions: week })), null);
    assert.equal(weeklyRecap(context(date(2026, 10, 18, 9), { sessions: week })), null);
  });

  it("se la settimana scorsa non hai studiato: niente", () => {
    assert.equal(weeklyRecap(context(monday, { sessions: [rk(10, 20)] })), null);
    assert.equal(weeklyRecap(context(monday)), null);
  });

  it("un giorno solo, e il pari merito", () => {
    assert.equal(weeklyRecap(context(monday, { sessions: [rk(10, 14, 15, 7800)] }))?.text, "Settimana scorsa: 2 h 10 in 1 giorno, 1 focus.");
    assert.ok(weeklyRecap(context(monday, { sessions: [rk(10, 15, 9, 3600), rk(10, 13, 9, 3600)] }))?.text.includes("martedì"), "a pari merito, il giorno prima");
  });
});

describe("Frasi «quando rendi meglio»", () => {
  it("una delle frasi delle statistiche, se ce n'è", () => {
    const many: StudySession[] = [];
    for (let i = 0; i < 4; i += 1) many.push(rated(5 + i, 9, i % 2 === 0 ? "Anatomia" : "Chimica", "good"));
    for (let i = 0; i < 4; i += 1) many.push(rated(5 + i, 21, i % 2 === 0 ? "Anatomia" : "Chimica", "poor"));
    const found = insights(many, ZONE);
    assert.ok(found.length > 0);
    assert.equal(insight(context(tuesdayMorning, { sessions: many }), 0), found[0]);
    assert.equal(insight(context(tuesdayMorning, { sessions: many }), found.length), found[0]);
    assert.equal(insight(context(tuesdayMorning), 0), null);
  });
});

describe("Traguardi", () => {
  const days = (list: number[], month = 10): StudySession[] => list.map((d) => rk(month, d));
  const at = (m: number, d: number, h = 12): number => date(2026, m, d, h);

  it("giorni di fila", () => {
    assert.equal(milestone(days([17, 18]), days([17, 18, 19]), at(10, 19), ZONE), "Tre giorni di fila!");
    assert.equal(milestone(days([17, 18, 19]), [...days([17, 18, 19]), rk(10, 19, 14)], at(10, 19, 16), ZONE), null, "un altro focus lo stesso giorno");
    assert.equal(milestone(days([13, 14, 15, 16, 17, 18]), days([13, 14, 15, 16, 17, 18, 19]), at(10, 19), ZONE), "Sette giorni di fila! Una settimana intera.");
  });

  it("numero di focus", () => {
    const nine = Array.from({ length: 9 }, (_, i) => rk(9, 1, 8 + Math.floor(i / 3), 600 + i));
    assert.equal(milestone(nine, [...nine, rk(9, 1, 20, 600)], at(9, 1, 21), ZONE), "10 focus insieme!");
    const fortyNine = Array.from({ length: 49 }, (_, i) => rk(8, 1 + Math.floor(i / 3), 8 + (i % 3), 600));
    assert.equal(milestone(fortyNine, [...fortyNine, rk(9, 20, 9, 600)], at(9, 20, 10), ZONE), "50 focus: un traguardo tondo!");
  });

  it("ore di studio", () => {
    assert.equal(milestone([rk(9, 1, 8, 35_940)], [rk(9, 1, 8, 35_940), rk(9, 20, 9, 120)], at(9, 20, 10), ZONE), "10 ore di studio insieme!");
    assert.equal(milestone([rk(7, 1, 8, 359_400)], [rk(7, 1, 8, 359_400), rk(9, 20, 9, 1200)], at(9, 20, 10), ZONE), "100 ore passate insieme a me. Grazie!");
  });

  it("se ne scattano due insieme, vince la serie", () => {
    const old = Array.from({ length: 7 }, (_, i) => rk(9, 1, 8, 600 + i));
    assert.equal(milestone([...days([17, 18]), ...old], [...days([17, 18, 19]), ...old], at(10, 19), ZONE), "Tre giorni di fila!");
  });

  it("un mese, un anno, due anni, tre mesi insieme", () => {
    assert.equal(milestone([rk(9, 19)], [rk(9, 19), rk(10, 19)], at(10, 19), ZONE), "Oggi è un mese che studiamo insieme.");
    assert.equal(milestone([rk(9, 19), rk(10, 19, 8)], [rk(9, 19), rk(10, 19, 8), rk(10, 19, 14)], at(10, 19, 16), ZONE), null, "solo al primo focus del giorno");
    assert.equal(milestone([rk(10, 19, 10, 3000, 2025)], [rk(10, 19, 10, 3000, 2025), rk(10, 19)], at(10, 19), ZONE), "Oggi è un anno che studiamo insieme!");
    assert.equal(milestone([rk(10, 19, 10, 3000, 2024)], [rk(10, 19, 10, 3000, 2024), rk(10, 19)], at(10, 19), ZONE), "Oggi sono 2 anni che studiamo insieme!");
    assert.equal(milestone([rk(7, 19)], [rk(7, 19), rk(10, 19)], at(10, 19), ZONE), "Oggi sono 3 mesi che studiamo insieme.");
    assert.equal(milestone([rk(9, 5)], [rk(9, 5), rk(10, 19)], at(10, 19), ZONE), null, "un giorno qualunque");
  });

  it("anche se il primo focus era un 31, l'anniversario cade a fine mese", () => {
    assert.equal(milestone([rk(1, 31)], [rk(1, 31), rk(2, 28)], at(2, 28), ZONE), "Oggi è un mese che studiamo insieme.");
    assert.equal(milestone([rk(1, 31)], [rk(1, 31), rk(4, 30)], at(4, 30), ZONE), "Oggi sono 3 mesi che studiamo insieme.");
    assert.equal(milestone([rk(1, 31)], [rk(1, 31), rk(2, 27)], at(2, 27), ZONE), null, "il 27 febbraio non è ancora un mese");
  });

  it("senza sessioni, niente", () => {
    assert.equal(milestone([], [], at(10, 19), ZONE), null);
  });
});

describe("Quale frase dice il compagno", () => {
  function chooser(extra: { reminder?: () => string | null; insight?: () => string | null; random?: () => number } = {}) {
    const clock = { now: 1_000_000_000_000 };
    let drawn = 0;
    const c = new PhraseChooser({
      now: () => clock.now, random: extra.random ?? (() => 0.99), reminder: extra.reminder ?? (() => null), insight: extra.insight ?? (() => null),
    });
    return { c, clock, next: () => c.next(() => `mazzo ${drawn += 1}`) };
  }

  it("prima le frasi in coda, nell'ordine; poi il mazzo", () => {
    const { c, next } = chooser();
    const said: string[] = [];
    c.enqueue({ text: "Buongiorno!" });
    c.enqueue({ text: "Settimana scorsa…", onSaid: () => said.push("riepilogo") });
    assert.deepEqual([next(), next(), next()], ["Buongiorno!", "Settimana scorsa…", "mazzo 1"]);
    assert.deepEqual(said, ["riepilogo"], "onSaid parte quando la frase è scelta");
  });

  it("il promemoria al massimo ogni tre ore", () => {
    const { clock, next } = chooser({ reminder: () => "Oggi scade «Tesi»." });
    assert.equal(next(), "Oggi scade «Tesi».");
    assert.equal(next(), "mazzo 1");
    clock.now += REMINDER_EVERY_MS - 1;
    assert.equal(next(), "mazzo 2");
    clock.now += 1;
    assert.equal(next(), "Oggi scade «Tesi».");
  });

  it("un saluto che dice già le scadenze rimanda il promemoria", () => {
    const { c, next } = chooser({ reminder: () => "Oggi scade «Tesi»." });
    c.enqueue({ text: "Buongiorno! Oggi scade «Tesi».", coversReminder: true });
    assert.equal(next(), "Buongiorno! Oggi scade «Tesi».");
    assert.equal(next(), "mazzo 1", "il promemoria non si ripete subito");
  });

  it("segnare il promemoria come detto lo rimanda (il saluto al risveglio)", () => {
    const { c, next } = chooser({ reminder: () => "Domani scade «Tesi»." });
    c.markReminderSaid();
    assert.equal(next(), "mazzo 1");
  });

  it("una volta su sei un numero dello studio, se ce n'è uno", () => {
    assert.equal(chooser({ random: () => 0, insight: () => "Rendi meglio di mattina." }).next(), "Rendi meglio di mattina.");
    assert.equal(chooser({ random: () => 0 }).next(), "mazzo 1", "senza numeri da dire, il mazzo");
    assert.equal(chooser({ random: () => 0.2, insight: () => "Rendi meglio di mattina." }).next(), "mazzo 1", "fuori da quell'una su sei, il mazzo");
  });

  it("il promemoria viene prima del numero", () => {
    const { next } = chooser({ random: () => 0, reminder: () => "Oggi scade «Tesi».", insight: () => "Rendi meglio di mattina." });
    assert.deepEqual([next(), next()], ["Oggi scade «Tesi».", "Rendi meglio di mattina."]);
  });
});

describe("Il servizio delle frasi nel processo principale", () => {
  const MIN = 60_000;
  let originalZone: string | undefined;
  before(() => {
    originalZone = process.env["TZ"];
    process.env["TZ"] = ZONE;
    refreshSystemZone();
  });
  after(() => {
    if (originalZone === undefined) delete process.env["TZ"]; else process.env["TZ"] = originalZone;
    refreshSystemZone();
  });

  function setup(options: { start?: number; introSeen?: boolean; name?: string | null; visible?: boolean; phase?: string | null; sessions?: StudySession[] } = {}) {
    const dir = tempDirectory();
    const clock = { now: options.start ?? date(2026, 10, 21, 9) };
    const settings = new Settings(dir);
    const profile = new Profile(dir);
    if (options.name !== null) profile.setName(options.name ?? "Jacopo");
    if (options.introSeen !== false) profile.markIntroSeen();
    const todo = new ToDoList(dir, { now: () => clock.now });
    const log = new SessionLog(dir, { now: () => clock.now, zone: ZONE });
    for (const s of options.sessions ?? []) log.add({ start: s.start, seconds: s.seconds, plannedMinutes: s.plannedMinutes, completed: true, subject: s.subject ?? null });
    const state = { phase: options.phase ?? null, visible: options.visible ?? true };
    const spoken: QuietSpeech[] = [];
    const remarks = createRemarks({
      settings, profile, todo, log: () => log, timerPhase: () => state.phase, isVisible: () => state.visible,
      sayWhenQuiet: (speech) => spoken.push(speech), now: () => clock.now, random: () => 0,
    });
    let drawn = 0;
    const next = (): string => remarks.nextPhrase(() => `mazzo ${drawn += 1}`);
    return { dir, clock, settings, profile, todo, log, state, spoken, remarks, next };
  }

  it("all'avvio: il saluto, poi il riepilogo della settimana (una volta sola), poi il mazzo", () => {
    const week = [rk(10, 12, 9, 3600), rk(10, 14, 15, 7800), rk(10, 16, 11, 1800)];     // mercoledì 21 ottobre: la settimana scorsa è dal 12 al 18
    const t = setup({ sessions: week });
    t.remarks.greetOnLaunch();
    assert.equal(t.next(), "Buongiorno, Jacopo! Si comincia quando vuoi.");
    assert.equal(t.next(), "Settimana scorsa: 3 h 40 in 3 giorni, 3 focus. Il giorno più forte: mercoledì (2 h 10).");
    assert.equal(t.settings.lastWeeklyRecap, "2026-10-12", "ricorda quale settimana ha raccontato");
    assert.equal(t.next(), "mazzo 1");
    // Al prossimo avvio la stessa settimana non si ripete.
    const again = createRemarks({
      settings: t.settings, profile: t.profile, todo: t.todo, log: () => t.log, timerPhase: () => null, isVisible: () => true,
      sayWhenQuiet: () => undefined, now: () => t.clock.now, random: () => 0,
    });
    again.greetOnLaunch();
    let drawn = 0;
    assert.equal(again.nextPhrase(() => `mazzo ${drawn += 1}`), "Buongiorno, Jacopo! Si comincia quando vuoi.");
    assert.equal(again.nextPhrase(() => `mazzo ${drawn += 1}`), "mazzo 1");
  });

  it("la prima volta (la scheda di benvenuto non è ancora stata vista) non saluta", () => {
    const t = setup({ introSeen: false });
    t.remarks.greetOnLaunch();
    assert.equal(t.next(), "mazzo 1");
  });

  it("se scade qualcosa il saluto lo dice e il promemoria non si ripete subito", () => {
    const t = setup();
    t.todo.add("Esercizi di analisi", "2026-10-21", null);
    t.remarks.greetOnLaunch();
    assert.equal(t.next(), "Buongiorno, Jacopo! Oggi scade «Esercizi di analisi». Un focus adesso?");
    assert.equal(t.next(), "mazzo 1");
  });

  it("senza saluti in coda, le scadenze tornano al posto di una frase, ma non durante un focus", () => {
    const t = setup({ phase: "focus" });
    t.todo.add("Esercizi di analisi", "2026-10-21", null);
    assert.equal(t.next(), "mazzo 1", "durante un focus niente promemoria");
    t.state.phase = null;
    assert.equal(t.next(), "Oggi scade «Esercizi di analisi». Un focus adesso?");
  });

  it("al risveglio dopo almeno un'ora: «Rieccoti!», un'ora dopo lo sleep e fuori da un focus", () => {
    const t = setup();
    t.todo.add("Tesi", null, null);
    t.remarks.suspended();
    t.clock.now += 30 * MIN;
    t.remarks.resumed();
    assert.deepEqual(t.spoken, [], "mezz'ora non basta");
    t.remarks.suspended();
    t.clock.now += 2 * 60 * MIN;
    t.remarks.resumed();
    assert.deepEqual(t.spoken, [{ text: "Rieccoti! Hai 1 cosa da fare.", after: 5, only: "outsideFocus" }]);
    t.remarks.resumed();
    assert.equal(t.spoken.length, 1, "un risveglio senza sleep non saluta");
  });

  it("il saluto al risveglio tace con «Frasi: Mai», con il compagno nascosto, durante un focus, o prima della scheda di benvenuto", () => {
    const wake = (change: (t: ReturnType<typeof setup>) => void): number => {
      const t = setup();
      change(t);
      t.remarks.wake(7200);
      return t.spoken.length;
    };
    assert.equal(wake(() => undefined), 1);
    assert.equal(wake((t) => { t.settings.phraseFrequency = "never"; }), 0);
    assert.equal(wake((t) => { t.state.visible = false; }), 0);
    assert.equal(wake((t) => { t.state.phase = "focus"; }), 0);
    const first = setup({ introSeen: false });
    first.remarks.wake(7200);
    assert.equal(first.spoken.length, 0);
  });

  it("se al risveglio dice le scadenze, il promemoria non si ripete subito", () => {
    const t = setup();
    t.todo.add("Tesi", "2026-10-21", null);
    t.remarks.wake(7200);
    assert.equal(t.spoken[0]?.text, "Rieccoti! Oggi scade «Tesi». Un focus adesso?");
    assert.equal(t.next(), "mazzo 1");
  });

  it("a fine focus: un traguardo detto dopo nove secondi, in pausa; niente se non ne scatta nessuno", () => {
    // Due giorni di fila già fatti: il terzo (oggi, con questo focus) è il traguardo.
    const t = setup({ start: date(2026, 10, 21, 9), sessions: [rk(10, 19), rk(10, 20)] });
    const engine = new PomodoroEngine({
      log: t.log, now: () => t.clock.now, random: () => 0, cycle: new BreakCycle(), zone: ZONE, longBreakEnabled: () => true, petId: () => "pianty",
    });
    const events: PomodoroEvent[] = [];
    engine.onEvent((event) => {
      events.push(event);
      if (event.type === "focusRecorded") t.remarks.focusRecorded(event.session);
    });
    engine.startFocus(25, "Anatomia");
    const end = t.clock.now + 25 * MIN + (GRACE_SECONDS + 1) * 1000;
    while (t.clock.now < end) { t.clock.now += 200; engine.tick(); }
    assert.ok(events.some((e) => e.type === "focusRecorded"));
    assert.deepEqual(t.spoken, [{ text: "Tre giorni di fila!", after: 9, only: "inBreak" }]);

    // Un secondo focus lo stesso giorno: nessun traguardo nuovo.
    const quiet = setup({ start: date(2026, 10, 21, 9), sessions: [rk(10, 19), rk(10, 20), rk(10, 21, 8)] });
    const extra = quiet.log.add({ start: date(2026, 10, 21, 9), seconds: 3000, plannedMinutes: 50, completed: true, subject: "Anatomia" })!;
    quiet.remarks.focusRecorded(extra);
    assert.deepEqual(quiet.spoken, []);
  });
});
