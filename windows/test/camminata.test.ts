// La camminata dei compagni (windows/src/core/walker.ts): le stesse regole di Walker.swift.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ACTIVE_INTERVAL_MS, IDLE_INTERVAL_MS, SPEED, Walker } from "../src/core/walker.ts";
import type { WalkerAction, WalkerInput } from "../src/core/walker.ts";
import { PETS } from "../src/core/pets.ts";
import type { PetData } from "../src/core/pets.ts";

const pet = (id: string): PetData => PETS.find((p) => p.id === id)!;
const gattino = pet("gattino");

/** Un generatore di numeri a caso che dà quelli indicati, uno dopo l'altro (poi 0,5). */
function scripted(...values: number[]): () => number {
  const queue = [...values];
  return () => queue.shift() ?? 0.5;
}

const base: Omit<WalkerInput, "now"> = {
  pet: gattino, visible: true, movementEnabled: true, dragging: false, speaking: false, showingFocusGrowth: false,
  x: 500, width: 144, screenMinX: 0, screenMaxX: 1440,
};

/** Un simulatore: avanza il tempo a passi, tiene la posizione della finestra come farebbe l'app. */
function simulator(walker: Walker, start = 0, overrides: Partial<WalkerInput> = {}) {
  const state = { now: start, x: base.x, ...overrides };
  const log: WalkerAction[] = [];
  return {
    state,
    log,
    step(ms: number, more: Partial<WalkerInput> = {}): WalkerAction {
      state.now += ms;
      const { x: _x, now: _now, ...rest } = state;
      const action = walker.tick({ ...base, ...rest, ...more, now: state.now, x: state.x });
      if (action.x !== undefined) state.x = action.x;
      log.push(action);
      return action;
    },
    run(totalMs: number, stepMs = 1000 / 30, more: Partial<WalkerInput> = {}): WalkerAction[] {
      const out: WalkerAction[] = [];
      for (let t = 0; t < totalMs; t += stepMs) out.push(this.step(stepMs, more));
      return out;
    },
  };
}

describe("Camminata", () => {
  it("parte da fermo per due secondi, poi sceglie", () => {
    const walker = new Walker(0, scripted(0.9, 0.9, 0.5));    // niente spuntini, a destra… (0,9 → sinistra), 5,5 s di cammino
    const sim = simulator(walker);
    for (const action of sim.run(1900)) assert.deepEqual(action, { pose: 0, sleepMarks: false });
    const decided = sim.step(150);
    assert.equal(decided.facingRight, false, "con 0,9 va a sinistra");
    assert.equal(decided.pose, 0);
  });

  it("cammina alla velocità giusta, con i fotogrammi dei passi e lo specchio", () => {
    const walker = new Walker(0, scripted(0.9, 0.1, 0.5));    // cammina verso destra
    const sim = simulator(walker);
    sim.run(2100);                                            // fino alla scelta
    const x0 = sim.state.x;
    const actions = sim.run(3000);
    const moved = sim.state.x - x0;
    assert.ok(Math.abs(moved - SPEED * 3) < 4, `in 3 s ha fatto ${moved} punti`);
    assert.ok(actions.every((a) => a.facingRight === true && a.sleepMarks === false));
    const poses = new Set(actions.map((a) => a.pose));
    assert.deepEqual([...poses].sort(), [...gattino.walkFrames].sort(), "usa tutti e soli i fotogrammi del passo");
    // il passo cambia ogni stepInterval (0,15 s = 4,5 tick)
    const sequence = actions.map((a) => a.pose!);
    const changes = sequence.filter((pose, i) => i > 0 && pose !== sequence[i - 1]).length;
    assert.ok(Math.abs(changes - 3000 / (gattino.stepInterval * 1000)) <= 2, `${changes} cambi in 3 s`);
  });

  it("rimbalza ai bordi", () => {
    const walker = new Walker(0, scripted(0.9, 0.1, 0.99));   // destra, quasi 8 s
    const sim = simulator(walker, 0, { x: 1100 });             // il bordo destro è a 1440 − 144 − 6 = 1290: 4,5 s di strada
    sim.run(2100);
    const actions = sim.run(6000);
    assert.ok(sim.state.x <= 1290, `x = ${sim.state.x}`);
    const last = actions.at(-1)!;
    assert.equal(last.facingRight, false, "dopo il rimbalzo guarda a sinistra");
    assert.ok(actions.some((a) => a.x === 1290), "tocca il bordo");
  });

  it("vicino a un bordo va verso il centro", () => {
    const left = new Walker(0, scripted(0.9, 0.3));            // 0,3 a caso andrebbe a sinistra… ma è già a sinistra
    const simLeft = simulator(left, 0, { x: 10 });
    simLeft.run(2000);
    assert.equal(simLeft.step(100).facingRight, true);
    const right = new Walker(0, scripted(0.9, 0.6));
    const simRight = simulator(right, 0, { x: 1280 });
    simRight.run(2000);
    assert.equal(simRight.step(100).facingRight, false);
  });

  it("mangia, e dopo riparte per forza a camminare", () => {
    const walker = new Walker(0, scripted(0.1, 0.0, 0.9, 0.9, 0.5));    // mangia per 6 s; poi 0,9 → cammina
    const sim = simulator(walker);
    sim.run(2000);
    const eating = sim.run(5000);
    const mouths = new Set(eating.map((a) => a.pose));
    assert.ok([...mouths].every((pose) => gattino.eatFrames.includes(pose!)), `pose ${[...mouths]}`);
    assert.ok(eating.every((a) => a.x === undefined), "resta dov'è");
    sim.run(1500);                                                      // fine del pasto + pausa
    const next = sim.run(2000);
    assert.ok(next.some((a) => a.x !== undefined), "poi cammina");
  });

  it("dopo uno spuntino non ne fa subito un altro, anche se il dado lo vorrebbe", () => {
    const walker = new Walker(0, scripted(0.1, 0.0, 0.1, 0.5, 0.5, 0.5));
    const sim = simulator(walker);
    sim.run(2000);            // sceglie di mangiare (6 s)
    sim.run(6100);            // finisce di mangiare
    sim.run(1600);            // pausa di 1,5 s: poi sceglie con 0,1 che direbbe «mangia»…
    const after = sim.run(500);
    assert.ok(after.some((a) => a.facingRight !== undefined), "…ma riparte a camminare");
  });

  it("dorme: assopito, respiro con gli «Zzz», assopito prima di svegliarsi", () => {
    const walker = new Walker(0, scripted(0.35, 0.0));                  // dorme per 12 s
    const sim = simulator(walker);
    sim.run(2000);
    const drowsy = sim.run(1400);
    assert.ok(drowsy.every((a) => a.pose === gattino.sleepIntroFrame && a.sleepMarks === false));
    sim.run(100);
    const breathing = sim.run(4000);
    assert.ok(breathing.every((a) => a.sleepMarks === true && gattino.sleepFrames.includes(a.pose!)));
    sim.run(5000);
    const waking = sim.run(1000);
    assert.ok(waking.some((a) => a.pose === gattino.sleepIntroFrame && a.sleepMarks === false), "assopito prima di svegliarsi");
    const done = sim.run(1000);
    assert.ok(done.every((a) => a.sleepMarks !== true), "svegliato: niente «Zzz»");
  });

  it("saltella e poi si ferma", () => {
    const walker = new Walker(0, scripted(0.5, 0.0));                   // 0,5 − 0,3 − 0,15 = 0,05 < 0,12 → popcorning, 3 s
    const sim = simulator(walker);
    sim.run(2000);
    const jumping = sim.run(2900);
    assert.ok(jumping.every((a) => a.pose !== undefined && gattino.popcornFrames.includes(a.pose)));
    assert.ok(jumping.every((a) => a.x === undefined));
  });

  it("fermo dal menu resta nella posa a riposo e non si muove", () => {
    const walker = new Walker(0, scripted(0.9, 0.1, 0.5));
    const sim = simulator(walker, 0, { movementEnabled: false });
    for (const action of sim.run(10_000)) assert.deepEqual(action, { pose: 0, sleepMarks: false });
    // riacceso, aspetta ancora un attimo prima di partire
    const first = sim.run(1400, 1000 / 30, { movementEnabled: true });
    assert.ok(first.every((a) => a.x === undefined));
  });

  it("mentre lo trascini sta nella posa a riposo e il tempo delle fasi non scorre", () => {
    const walker = new Walker(0, scripted(0.9, 0.1, 0.5));
    const sim = simulator(walker);
    for (const a of sim.run(5000, 100, { dragging: true })) assert.deepEqual(a, { pose: 0, sleepMarks: false });
    // Il riposo iniziale finiva a 2 s: con il tempo «congelato» non è ancora finito.
    const right = sim.run(1500, 100);
    assert.ok(right.every((a) => a.x === undefined), "ancora fermo");
    const later = sim.run(2000, 100);
    assert.ok(later.some((a) => a.x !== undefined), "poi riparte");
  });

  it("mentre parla sta fermo (posa di quando parla), ma se mangia continua a mangiare", () => {
    const porcellino = pet("porcellino");
    const talking = new Walker(0, scripted(0.9, 0.1, 0.5));
    const simTalking = simulator(talking, 0, { pet: porcellino });
    for (const a of simTalking.run(3000, 100, { speaking: true })) assert.deepEqual(a, { pose: porcellino.talkFrame });
    const noTalkFrame = simulator(new Walker(0), 0, { pet: gattino });
    assert.deepEqual(noTalkFrame.step(100, { speaking: true }), { pose: 0 }, "senza posa per parlare, quella a riposo");

    const eating = new Walker(0, scripted(0.1, 0.0));
    const sim = simulator(eating, 0, { pet: porcellino });
    sim.run(2000);
    const whileSpeaking = sim.run(1000, 100, { speaking: true });
    assert.ok(whileSpeaking.every((a) => a.pose !== porcellino.talkFrame && porcellino.eatFrames.includes(a.pose!)));
  });

  it("nascosto, o durante la crescita sul posto, non fa niente", () => {
    const hidden = simulator(new Walker(0), 0, { visible: false });
    assert.deepEqual(hidden.step(100), { sleepMarks: false });
    const growing = simulator(new Walker(0), 0, { showingFocusGrowth: true });
    assert.deepEqual(growing.step(100), { sleepMarks: false });
    const stays = simulator(new Walker(0), 0, { pet: { ...gattino, walks: false } });
    assert.deepEqual(stays.step(100), { sleepMarks: false });
  });

  it("dopo uno stop lungo (sleep del computer) non fa salti", () => {
    const walker = new Walker(0, scripted(0.9, 0.1, 0.99));
    const sim = simulator(walker);
    sim.run(2100);
    const before = sim.state.x;
    sim.step(60_000);
    assert.ok(sim.state.x - before <= SPEED * 0.1 + 1, `salto di ${sim.state.x - before} punti`);
  });

  it("se l'utente sposta la finestra, riparte da lì", () => {
    const walker = new Walker(0, scripted(0.9, 0.1, 0.99));
    const sim = simulator(walker);
    sim.run(2100);
    sim.run(500);
    sim.state.x = 900;
    const action = sim.step(1000 / 30);
    assert.ok(Math.abs(action.x! - 901.4) < 1, `x = ${action.x}`);
  });

  it("mangia subito a fine focus solo se può (porcellino con la sua carota)", () => {
    const porcellino = pet("porcellino");
    const walker = new Walker(0, scripted(0.0, 0.0));
    const sim = simulator(walker, 0, { pet: porcellino });
    walker.eatNow({ now: 100, pet: gattino, visible: true, dragging: false }, true);        // il gattino non mangia a fine focus
    assert.deepEqual(sim.step(100), { pose: 0, sleepMarks: false });
    walker.eatNow({ now: 200, pet: porcellino, visible: true, dragging: false }, false);     // senza le immagini della carota
    assert.deepEqual(sim.step(100), { pose: 0, sleepMarks: false });
    walker.eatNow({ now: 300, pet: porcellino, visible: false, dragging: false }, true);     // nascosto
    walker.eatNow({ now: 300, pet: porcellino, visible: true, dragging: true }, true);       // sollevato
    assert.deepEqual(sim.step(100), { pose: 0, sleepMarks: false });
    walker.eatNow({ now: 400, pet: porcellino, visible: true, dragging: false }, true);
    const eating = sim.run(1000, 100);
    assert.ok(eating.every((a) => porcellino.eatFrames.includes(a.pose!)));
  });

  it("ogni quanto serve chiamare tick", () => {
    const walker = new Walker(0);
    assert.equal(walker.intervalMs(gattino, true, true), ACTIVE_INTERVAL_MS);
    assert.equal(walker.intervalMs(gattino, false, true), IDLE_INTERVAL_MS);
    assert.equal(walker.intervalMs(gattino, true, false), IDLE_INTERVAL_MS);
    assert.equal(walker.intervalMs({ ...gattino, walks: false }, true, true), IDLE_INTERVAL_MS);
  });

  it("Pianty cammina con i suoi sei passi", () => {
    const pianty = pet("pianty");
    const walker = new Walker(0, scripted(0.9, 0.1, 0.99));
    const sim = simulator(walker, 0, { pet: pianty });
    sim.run(2100);
    const poses = new Set(sim.run(2000).map((a) => a.pose));
    assert.deepEqual([...poses].sort(), [...pianty.walkFrames].sort());
  });
});
