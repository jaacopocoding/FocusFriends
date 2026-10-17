// Il motore del timer (windows/src/core/pomodoro.ts).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { SessionLog } from "../src/core/log.ts";
import { ALWAYS_VISIBLE_MINUTES, EXTENSION_MINUTES, GRACE_SECONDS, PomodoroEngine, clockWanted, focusFinishedMessage, formatRemaining } from "../src/core/pomodoro.ts";
import type { PomodoroEvent } from "../src/core/pomodoro.ts";
import { BreakCycle } from "../src/core/rules.ts";
import { date, tempDirectory, ZONE } from "./util.ts";

const MIN = 60_000;

function setup(options: { longBreak?: boolean; start?: number; pet?: string; gardenLine?: () => string } = {}) {
  const dir = tempDirectory();
  const clock = { now: options.start ?? date(2026, 10, 14, 9, 0) };
  const log = new SessionLog(dir, { now: () => clock.now, zone: ZONE });
  const engine = new PomodoroEngine({
    log, now: () => clock.now, random: () => 0, cycle: new BreakCycle(), zone: ZONE,
    longBreakEnabled: () => options.longBreak ?? true, petId: () => options.pet ?? "pianty",
    ...(options.gardenLine ? { gardenLine: options.gardenLine } : {}),
  });
  const events: PomodoroEvent[] = [];
  engine.onEvent((event) => events.push(event));
  /** Avanza il tempo, facendo battere il timer ogni 0,2 secondi (o un solo battito se `beats` è falso). */
  const advance = (ms: number, beats = true): void => {
    if (!beats) { clock.now += ms; engine.tick(); return; }
    const end = clock.now + ms;
    while (clock.now < end) { clock.now = Math.min(clock.now + 200, end); engine.tick(); }
  };
  const types = (): string[] => events.map((e) => e.type);
  const says = (): string[] => events.flatMap((e) => (e.type === "say" ? [e.text] : []));
  return { dir, clock, log, engine, events, advance, types, says };
}

describe("Avvio del focus", () => {
  it("scrive il segno «in corso», dice la frase e parte da 25:00", () => {
    const t = setup();
    t.engine.startFocus(25, " Anatomia ");
    assert.deepEqual(t.types(), ["reset", "focusActive", "say"]);
    assert.deepEqual(t.says(), ["Focus di 25 minuti su Anatomia: si parte!"]);
    assert.ok(existsSync(join(t.dir, "in-corso.json")));
    const s = t.engine.snapshot();
    assert.deepEqual([s.phase, s.label, s.remainingText, s.subject, s.focusMinutes, s.rangeText], ["focus", "FOCUS", "25:00", "Anatomia", 25, "09:00 – 09:25"]);
    t.engine.stop();
    const quiet = setup();
    quiet.engine.startFocus(30);
    assert.deepEqual(quiet.says(), ["Focus di 30 minuti: si parte!"]);
  });

  it("il conto alla rovescia scende e arrotonda per eccesso", () => {
    const t = setup();
    t.engine.startFocus(25);
    t.advance(200);
    assert.equal(t.engine.snapshot().remainingText, "25:00");
    t.advance(800);
    assert.equal(t.engine.snapshot().remainingText, "24:59");
    t.advance(5 * MIN - 1000);
    assert.equal(t.engine.snapshot().remainingText, "20:00");
    assert.ok(Math.abs(t.engine.snapshot().progress - 0.2) < 1e-9);
    assert.equal(t.engine.snapshot().growthProgress, 0.2);
  });

  it("un focus nuovo mentre uno è in corso salva il primo come interrotto", () => {
    const t = setup();
    t.engine.startFocus(25, "Fisica");
    t.advance(10 * MIN);
    t.engine.startFocus(50, "Chimica");
    assert.equal(t.log.sessions.length, 1);
    const first = t.log.sessions[0]!;
    assert.deepEqual([first.subject, first.seconds, first.completed, first.plannedMinutes, first.pet], ["Fisica", 600, false, 25, "pianty"]);
    assert.equal(t.engine.snapshot().subject, "Chimica");
  });
});

describe("Fine del focus e «+5 minuti»", () => {
  it("allo scadere suona e aspetta dieci secondi; poi registra, e parte la pausa", () => {
    const t = setup();
    t.engine.startFocus(25, "Anatomia");
    t.events.length = 0;
    t.advance(25 * MIN);
    assert.deepEqual(t.types(), ["sound", "dismissSpeech", "graceBegan"]);
    assert.equal(t.log.sessions.length, 0, "ancora non registrato");
    assert.equal(t.engine.snapshot().remainingText, "00:00");
    assert.ok(t.engine.snapshot().graceSecondsLeft !== null);
    t.events.length = 0;
    t.advance(GRACE_SECONDS * 1000);
    assert.ok(t.types().includes("graceEnded") && t.types().includes("focusCompleted") && t.types().includes("focusRecorded"));
    assert.ok(!t.types().includes("sound"), "il suono era già partito");
    const session = t.log.sessions[0]!;
    assert.deepEqual([session.completed, session.seconds, session.plannedMinutes, session.subject], [true, 25 * 60, 25, "Anatomia"]);
    const s = t.engine.snapshot();
    assert.deepEqual([s.phase, s.label, s.remainingText, s.cycleDone, s.isLongBreak, s.lastFocus?.minutes, s.lastFocus?.sessionId], ["rest", "PAUSA", "05:00", 1, false, 25, session.id]);
    assert.ok(!existsSync(join(t.dir, "in-corso.json")), "il segno «in corso» è tolto");
    assert.equal(t.says().at(-1), "Hai studiato Anatomia per 25 minuti. Che bel lavoro! Ora 5 minuti di pausa.");
    assert.equal(s.growthProgress, null);
  });

  it("«+5 minuti» durante l'attesa: il focus continua e conta il tempo in più", () => {
    const t = setup();
    t.engine.startFocus(25);
    t.advance(25 * MIN + 3000);                         // scaduto da 3 secondi
    t.events.length = 0;
    t.engine.extendFocus();
    assert.deepEqual(t.types(), ["graceEnded", "say"]);
    assert.match(t.says()[0]!, /Altri 5 minuti/);
    let s = t.engine.snapshot();
    assert.deepEqual([s.phase, s.focusMinutes, s.remainingText, s.graceSecondsLeft, s.growthProgress], ["focus", 30, "05:00", null, 1]);
    t.advance(5 * MIN + GRACE_SECONDS * 1000 + 1000);
    const session = t.log.sessions[0]!;
    assert.deepEqual([session.completed, session.plannedMinutes, session.seconds], [true, 30, 25 * 60 + 3 + 5 * 60]);
    s = t.engine.snapshot();
    assert.equal(s.phase, "rest");
  });

  it("«+5 minuti» prima che scada allunga il focus", () => {
    const t = setup();
    t.engine.startFocus(25);
    t.advance(10 * MIN);
    t.engine.addMinutes();
    const s = t.engine.snapshot();
    assert.deepEqual([s.focusMinutes, s.remainingText, s.rangeText, s.growthProgress], [30, "20:00", "09:00 – 09:30", 1]);
    assert.equal(new SessionLog(t.dir, { now: () => t.clock.now, zone: ZONE }).recoverInterrupted()?.plannedMinutes, 30);
  });

  it("nella pausa si possono aggiungere minuti", () => {
    const t = setup();
    t.engine.startBreak(5);
    t.engine.addMinutes(EXTENSION_MINUTES);
    assert.equal(t.engine.snapshot().remainingText, "10:00");
  });

  it("la pausa che finisce ferma tutto e saluta", () => {
    const t = setup();
    t.engine.startBreak(5);
    assert.deepEqual(t.says(), ["Pausa di 5 minuti: stacca un attimo."]);
    t.events.length = 0;
    t.advance(5 * MIN);
    assert.deepEqual(t.types().filter((e) => e !== "reset"), ["sound", "say"]);
    assert.equal(t.says()[0], "Pausa finita! Pronto per un altro giro?");
    assert.equal(t.engine.phase, null);
  });
});

describe("Pausa, sleep e chiusure", () => {
  it("«Ferma» non conta come studio e «Riprendi» riparte", () => {
    const t = setup();
    t.engine.startFocus(25);
    t.advance(10 * MIN);
    t.events.length = 0;
    t.engine.toggleFocusPause();
    assert.deepEqual(t.types(), ["focusActive", "say"]);
    assert.equal(t.engine.snapshot().label, "FERMO");
    t.advance(3 * MIN);
    assert.equal(t.engine.snapshot().remainingText, "15:00", "fermo: il conto non scorre");
    assert.equal(t.engine.snapshot().elapsedSeconds, 600);
    t.engine.toggleFocusPause();
    assert.equal(t.engine.snapshot().label, "FOCUS");
    assert.deepEqual(t.says().slice(-2), ["Timer fermo. Riprendi quando sei pronto.", "Si riparte!"]);
    t.advance(15 * MIN);
    t.advance(GRACE_SECONDS * 1000);
    const session = t.log.sessions[0]!;
    assert.deepEqual([session.completed, session.seconds], [true, 25 * 60], "i 3 minuti fermi non contano");
  });

  it("chiusa mentre è fermo, l'app recupera solo il tempo di studio", () => {
    const t = setup();
    t.engine.startFocus(50);
    t.advance(10 * MIN);
    t.engine.toggleFocusPause();
    t.advance(5 * MIN);
    t.log.heartbeat(t.clock.now + 31_000);
    const recovered = new SessionLog(t.dir, { zone: ZONE }).recoverInterrupted();
    assert.equal(recovered?.seconds, 600);
  });

  it("un salto di tempo di oltre dieci secondi (sleep) conta come tempo fermo", () => {
    const t = setup();
    t.engine.startFocus(25);
    t.advance(5 * MIN);
    t.advance(8 * 3600_000, false);              // il computer ha dormito otto ore
    const s = t.engine.snapshot();
    assert.equal(s.phase, "focus");
    assert.equal(s.remainingText, "20:00");
    assert.equal(s.elapsedSeconds, 300);
    assert.equal(t.log.sessions.length, 0, "niente registrato come studio");
    t.advance(20 * MIN + GRACE_SECONDS * 1000);
    assert.equal(t.log.sessions[0]?.seconds, 25 * 60);
  });

  it("un salto breve (meno di dieci secondi) non è uno sleep", () => {
    const t = setup();
    t.engine.startFocus(25);
    t.advance(5 * MIN);
    t.advance(9000, false);
    assert.equal(t.engine.snapshot().remainingText, "19:51");
    t.advance(11_000, false);                 // più di dieci secondi: quello sì
    assert.equal(t.engine.snapshot().remainingText, "19:51");
  });

  it("«Termina e salva»: il focus si registra come interrotto; sotto il minuto no", () => {
    const t = setup();
    t.engine.startFocus(25, "Fisica");
    t.advance(7 * MIN);
    t.engine.stop();
    const session = t.log.sessions[0]!;
    assert.deepEqual([session.completed, session.seconds, session.plannedMinutes], [false, 7 * 60, 25]);
    assert.equal(t.engine.phase, null);
    assert.ok(t.types().includes("reset"));
    const quick = setup();
    quick.engine.startFocus(25);
    quick.advance(30_000);
    quick.engine.stop();
    assert.equal(quick.log.sessions.length, 0);
  });

  it("fermare durante i secondi del «+5 minuti» (Termina) registra il focus come completo", () => {
    const t = setup();
    t.engine.startFocus(25);
    t.advance(25 * MIN + 2000);
    t.engine.toggleFocusPause();
    assert.equal(t.engine.phase, null);
    assert.deepEqual([t.log.sessions[0]?.completed, t.log.sessions[0]?.seconds], [true, 25 * 60]);
  });

  it("«Elimina questo focus» non lascia traccia", () => {
    const t = setup();
    t.engine.startFocus(25);
    t.advance(10 * MIN);
    t.engine.discardFocus();
    assert.equal(t.log.sessions.length, 0);
    assert.ok(!existsSync(join(t.dir, "in-corso.json")));
    assert.equal(t.says().at(-1), "Focus eliminato: non resta traccia.");
    assert.equal(t.engine.phase, null);
  });

  it("chiusura dell'app: il focus in corso si salva come interrotto", () => {
    const t = setup();
    t.engine.startFocus(25);
    t.advance(12 * MIN);
    t.engine.recordInterruptedFocusOnQuit();
    assert.deepEqual([t.log.sessions[0]?.seconds, t.log.sessions[0]?.completed], [720, false]);
  });

  it("le note del focus finiscono nella sessione", () => {
    const t = setup();
    t.engine.startFocus(25);
    t.engine.addNote("  chiedere   al prof ");
    t.engine.addNote("   ");
    t.engine.addNote("esercizio 4");
    assert.deepEqual(t.engine.snapshot().notes, ["chiedere al prof", "esercizio 4"]);
    t.advance(25 * MIN + GRACE_SECONDS * 1000);
    assert.deepEqual(t.log.sessions[0]?.notes, ["chiedere al prof", "esercizio 4"]);
    assert.deepEqual(t.engine.snapshot().notes, [], "dopo, il foglietto è vuoto");
    t.engine.addNote("in pausa non si scrive");
    assert.deepEqual(t.engine.snapshot().notes, []);
  });
});

describe("Ciclo dei quattro focus", () => {
  const focusRound = (t: ReturnType<typeof setup>): void => {
    t.engine.startFocus(25, "Anatomia");
    t.advance(25 * MIN + GRACE_SECONDS * 1000);
  };

  it("dopo il quarto la pausa è lunga", () => {
    const t = setup();
    for (let i = 1; i <= 3; i += 1) {
      focusRound(t);
      assert.deepEqual([t.engine.snapshot().remainingText, t.engine.snapshot().cycleDone, t.engine.snapshot().isLongBreak], ["05:00", i, false]);
      t.engine.stop();
    }
    focusRound(t);
    const s = t.engine.snapshot();
    assert.deepEqual([s.remainingText, s.isLongBreak, s.cycleDone], ["15:00", true, 4]);
    assert.match(t.says().at(-1)!, /Quattro focus di fila su Anatomia/);
    t.engine.stop();
    focusRound(t);
    assert.deepEqual([t.engine.snapshot().remainingText, t.engine.snapshot().cycleDone], ["05:00", 1], "dopo la pausa lunga si riparte");
  });

  it("una pausa scelta più lunga di 15 minuti resta com'è", () => {
    const t = setup();
    t.engine.startBreak(20);
    t.engine.stop();
    for (let i = 0; i < 4; i += 1) { focusRound(t); if (i < 3) t.engine.stop(); }
    assert.equal(t.engine.snapshot().remainingText, "20:00");
  });

  it("con la pausa lunga spenta non c'è mai e il conteggio è nullo", () => {
    const t = setup({ longBreak: false });
    for (let i = 0; i < 4; i += 1) { focusRound(t); assert.deepEqual([t.engine.snapshot().remainingText, t.engine.snapshot().cycleDone], ["05:00", null]); t.engine.stop(); }
  });
});

describe("Orologio e messaggi", () => {
  it("si vede nei primi due minuti, negli ultimi cinque e al passaggio del mouse", () => {
    const at = (elapsedSeconds: number, remainingSeconds: number) => ({ phase: "focus" as const, elapsedSeconds, remainingSeconds });
    assert.ok(clockWanted(at(0, 1500), false));
    assert.ok(clockWanted(at(119, 1381), false));
    assert.ok(!clockWanted(at(120, 1380), false));
    assert.ok(clockWanted(at(120, ALWAYS_VISIBLE_MINUTES * 60), false));
    assert.ok(!clockWanted(at(600, 900), false));
    assert.ok(clockWanted(at(600, 900), true));
    assert.ok(!clockWanted({ phase: null, elapsedSeconds: 0, remainingSeconds: 0 }, true));
  });

  it("il tempo rimasto come MM:SS", () => {
    assert.deepEqual([0, 0.2, 1, 59.1, 60, 1800, 6000].map(formatRemaining), ["00:00", "00:01", "00:01", "01:00", "01:00", "30:00", "100:00"]);
  });

  it("il messaggio di fine focus, con e senza riga sul giardino", () => {
    const base = { subject: "Anatomia", studiedMinutes: 50, breakMinutes: 10, longBreak: false };
    assert.equal(focusFinishedMessage({ ...base, garden: "" }, () => 0), "Hai studiato Anatomia per 50 minuti. Che bel lavoro! Ora 10 minuti di pausa.");
    assert.equal(focusFinishedMessage({ ...base, garden: "Un punto in più per il giardino." }, () => 0),
      "Hai studiato Anatomia per 50 minuti. Che bel lavoro! Un punto in più per il giardino. Ora 10 minuti di pausa.");
    assert.equal(focusFinishedMessage({ ...base, subject: null, garden: "" }), "Focus finito! Ti sei meritato 10 minuti di pausa.");
    assert.match(focusFinishedMessage({ ...base, subject: null, longBreak: true, garden: "" }, () => 0.99), /^Il quarto focus è andato! Pausa lunga: 10 minuti/);
    const seen = new Set([0, 0.4, 0.8].map((r) => focusFinishedMessage({ ...base, garden: "" }, () => r)));
    assert.equal(seen.size, 3, "tre varianti");
  });

  it("la riga sul giardino arriva dal motore solo se è stata data", () => {
    const t = setup({ gardenLine: () => "Il giardino cresce." });
    t.engine.startFocus(25, "Anatomia");
    t.advance(25 * MIN + GRACE_SECONDS * 1000);
    assert.match(t.says().at(-1)!, /Il giardino cresce\./);
  });
});
