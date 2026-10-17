// Sblocco dei compagni e annuncio (core/unlocks.ts), con il profilo vero.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Profile } from "../src/core/profile.ts";
import { evaluateUnlocks, unlockMessage } from "../src/core/unlocks.ts";
import { companionLocks } from "../src/core/card.ts";
import { date, session, tempDirectory } from "./util.ts";

const IDS = ["pianty", "porcellino", "ciccio", "gattino"];
const FOCUS = 3000;           // un «focus pieno»: 50 minuti
const hours = (focuses: number) => [session({ start: date(2026, 10, 1, 9), seconds: focuses * FOCUS })];

describe("Sblocchi", () => {
  it("il secondo compagno arriva a 20 focus pieni, e si ricorda sul disco", () => {
    const dir = tempDirectory();
    const profile = new Profile(dir);
    profile.chooseFirstCompanion("pianty");
    assert.deepEqual(evaluateUnlocks(profile, hours(19), IDS, false), []);
    assert.deepEqual(evaluateUnlocks(profile, hours(20), IDS, false), ["porcellino"]);
    assert.deepEqual([...(profile.unlocked ?? [])].sort(), ["pianty", "porcellino"]);
    assert.deepEqual(JSON.parse(readFileSync(join(dir, "profilo.json"), "utf8")).unlocked, ["pianty", "porcellino"]);
    assert.deepEqual(evaluateUnlocks(profile, hours(20), IDS, false), [], "una volta sola");
  });

  it("a 50 il terzo; con il Gattino scelto per primo l'ordine cambia", () => {
    const profile = new Profile(tempDirectory());
    profile.chooseFirstCompanion("gattino");
    assert.deepEqual(evaluateUnlocks(profile, hours(20), IDS, false), ["pianty"], "dopo il gattino, i personaggi nell'ordine di sempre");
    assert.deepEqual(evaluateUnlocks(profile, hours(50), IDS, false), ["porcellino"]);
    assert.deepEqual(evaluateUnlocks(profile, hours(120), IDS, false), ["ciccio"]);
  });

  it("più sblocchi insieme (dopo aver cancellato e ricostruito i dati)", () => {
    const profile = new Profile(tempDirectory());
    profile.chooseFirstCompanion("pianty");
    assert.deepEqual(evaluateUnlocks(profile, hours(120), IDS, false), ["porcellino", "ciccio", "gattino"]);
  });

  it("in modalità sviluppatore niente da annunciare né da registrare; senza scelta niente è bloccato", () => {
    const dev = new Profile(tempDirectory(), { developer: () => true });
    dev.chooseFirstCompanion("pianty");
    assert.deepEqual(evaluateUnlocks(dev, hours(500), IDS, true), []);
    assert.deepEqual([...(dev.unlocked ?? [])], ["pianty"], "il profilo non si tocca");
    assert.ok(IDS.every((id) => dev.isCompanionUnlocked(id)), "ma sono tutti usabili");
    assert.equal(companionLocks(dev, [], IDS).size, 0);
    const fresh = new Profile(tempDirectory());
    assert.deepEqual(evaluateUnlocks(fresh, hours(500), IDS, false), []);
  });

  it("la frase dell'annuncio, al singolare e al plurale", () => {
    assert.equal(unlockMessage(["porcellino"]), "Hai sbloccato Porcellino! Lo trovi nel menu, tra i compagni.");
    assert.equal(unlockMessage(["ciccio", "gattino"]), "Hai sbloccato Ciccio e Gattino! Li trovi nel menu, tra i compagni.");
  });

  it("un compagno bloccato non risulta usabile e dice quanto manca", () => {
    const profile = new Profile(tempDirectory());
    profile.chooseFirstCompanion("pianty");
    assert.ok(!profile.isCompanionUnlocked("ciccio") && profile.isCompanionUnlocked("pianty"));
    assert.equal(companionLocks(profile, hours(10), IDS).get("ciccio"), "si sblocca a 50 focus: ne hai 10");
  });
});
