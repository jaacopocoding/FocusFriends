// Le prove del profilo e dei compagni da sbloccare: le stesse della versione per Mac.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Profile, PROFILE_FORMAT_VERSION } from "../src/core/profile.ts";
import { SessionLog } from "../src/core/log.ts";
import { earned, focuses, need, order, threshold } from "../src/core/rewards.ts";
import { date, tempDirectory, ZONE } from "./util.ts";

const write = (dir: string, text: string): void => writeFileSync(join(dir, "profilo.json"), text, "utf8");

describe("Profilo e titoli", () => {
  it("un profilo nuovo e i titoli", () => {
    const dir = tempDirectory();
    const profile = new Profile(dir);
    assert.ok(profile.name === null && !profile.introSeen);
    assert.deepEqual([profile.gardenTitle, profile.statsTitle], ["Il mio giardino", "Statistiche e riepilogo"]);
    let changes = 0;
    profile.addObserver(() => { changes += 1; });
    profile.setName(" Marco ");
    assert.deepEqual([profile.gardenTitle, profile.statsTitle], ["Il giardino di Marco", "Le statistiche di Marco"]);
    profile.markIntroSeen();
    assert.equal(changes, 2, "gli osservatori vengono avvisati");

    const again = new Profile(dir);
    assert.ok(again.name === "Marco" && again.introSeen, "si salva e si rilegge");
    assert.equal(JSON.parse(readFileSync(join(dir, "profilo.json"), "utf8")).version, PROFILE_FORMAT_VERSION);
    again.setName("");
    assert.ok(again.name === null && again.gardenTitle === "Il mio giardino");
    again.reset();
    assert.ok(!existsSync(join(dir, "profilo.json")), "reset: il file sparisce");
    assert.ok(!new Profile(dir).introSeen, "reset: alla riapertura si ricomincia");
  });

  it("il nome non finisce nelle sessioni", () => {
    const dir = tempDirectory();
    new Profile(dir).setName("Marco");
    const made = new SessionLog(dir, { zone: ZONE }).add({ start: date(2026, 10, 14, 9), seconds: 600, plannedMinutes: 10, completed: true, subject: "X" });
    assert.ok(made !== null && !readFileSync(join(dir, "sessioni.json"), "utf8").includes("Marco"));
  });

  it("un file mancante di version o introSeen è rovinato", () => {
    for (const text of ['{"name": "Marco", "introSeen": true}', '{"version": 1, "name": "Marco"}', '{"version": 1, "introSeen": "si"}',
                        '{"version": 1, "introSeen": true, "unlocked": [1]}', "[]"]) {
      const dir = tempDirectory();
      write(dir, text);
      const profile = new Profile(dir);
      assert.ok(profile.name === null && readdirSync(dir).some((f) => f.startsWith("profilo.corrotto-")), text);
    }
  });
});

describe("Compagni da sbloccare", () => {
  const pets = ["pianty", "porcellino", "ciccio"];

  it("i focus pieni", () => {
    assert.ok(focuses(0) === 0 && focuses(49 * 60) === 0);
    assert.ok(focuses(50 * 60) === 1 && focuses(20 * 50 * 60 + 59) === 20);
    assert.equal(focuses(-5), 0);
  });
  it("l'ordine e le soglie", () => {
    assert.deepEqual(order("ciccio", pets), ["ciccio", "pianty", "porcellino"]);
    assert.deepEqual(order(null, pets), pets);
    assert.deepEqual(order("sconosciuto", pets), pets);
    assert.ok(threshold(3) === 100 && threshold(4) === 150, "oltre il terzo: altri 50 a testa");
  });
  it("chi è meritato", () => {
    const sorted = (set: Set<string>) => [...set].sort();
    assert.deepEqual(sorted(earned("pianty", pets, 0)), ["pianty"]);
    assert.deepEqual(sorted(earned("pianty", pets, 19)), ["pianty"]);
    assert.deepEqual(sorted(earned("pianty", pets, 20)), ["pianty", "porcellino"]);
    assert.deepEqual(sorted(earned("pianty", pets, 49)), ["pianty", "porcellino"]);
    assert.deepEqual(sorted(earned("pianty", pets, 50)), [...pets].sort());
    assert.deepEqual(sorted(earned("ciccio", pets, 20)), ["ciccio", "pianty"]);
    assert.ok(need("ciccio", "pianty", pets) === 50 && need("porcellino", "pianty", pets) === 20 && need("pianty", "pianty", pets) === 0);
  });

  it("il profilo ricorda cosa è sbloccato", () => {
    const dir = tempDirectory();
    const fresh = new Profile(dir);
    assert.ok(fresh.isCompanionUnlocked("ciccio"), "senza scelta, niente è bloccato");
    fresh.keepAllCompanions(pets);
    assert.equal(fresh.unlocked, null, "chi non ha visto la presentazione non li ha ancora tutti");
    fresh.chooseFirstCompanion("porcellino");
    assert.ok(fresh.isCompanionUnlocked("porcellino") && !fresh.isCompanionUnlocked("pianty") && fresh.firstCompanion === "porcellino");
    fresh.unlock(["pianty"]);
    const reopened = new Profile(dir);
    assert.ok(reopened.isCompanionUnlocked("pianty") && reopened.isCompanionUnlocked("porcellino") && !reopened.isCompanionUnlocked("ciccio"));
    assert.equal(reopened.firstCompanion, "porcellino");
    reopened.reset();
    assert.ok(new Profile(dir).unlocked === null && new Profile(dir).isCompanionUnlocked("ciccio"), "«Cancella tutto» ricomincia");
  });

  it("chi usava già l'app li tiene tutti", () => {
    const dir = tempDirectory();
    const user = new Profile(dir);
    user.setName("Anna");
    user.markIntroSeen();
    user.keepAllCompanions(pets);
    assert.ok(pets.every((id) => new Profile(dir).isCompanionUnlocked(id)));
    assert.deepEqual([...(new Profile(dir).unlocked ?? [])].sort(), [...pets].sort());
    user.chooseFirstCompanion("ciccio");
    assert.deepEqual([...(new Profile(dir).unlocked ?? [])].sort(), [...pets].sort(), "e la scelta iniziale non toglie niente");
  });

  it("modalità sviluppatore: tutto sbloccato senza toccare il profilo", () => {
    const dir = tempDirectory();
    let developer = false;
    const profile = new Profile(dir, { developer: () => developer });
    profile.chooseFirstCompanion("pianty");
    assert.ok(!profile.isCompanionUnlocked("gattino"));
    developer = true;
    assert.ok(pets.every((id) => profile.isCompanionUnlocked(id)) && profile.isCompanionUnlocked("gattino"));
    assert.deepEqual([...(profile.unlocked ?? [])], ["pianty"]);
    developer = false;
    assert.ok(!profile.isCompanionUnlocked("gattino"), "spenta, torna come prima");
  });

  it("un profilo di prima (senza questi campi) si legge", () => {
    const dir = tempDirectory();
    write(dir, '{"version": 1, "name": "Marco", "introSeen": true}');
    const profile = new Profile(dir);
    assert.ok(profile.name === "Marco" && profile.introSeen && profile.unlocked === null && profile.isCompanionUnlocked("ciccio"));
  });
});

describe("Profilo danneggiato", () => {
  it("rovinato: messo da parte, avvisato, e dopo si salva normalmente", () => {
    const dir = tempDirectory();
    write(dir, "{ non e' json");
    const messages: string[] = [];
    const profile = new Profile(dir);
    profile.onProblem = (message) => messages.push(message);
    assert.ok(profile.name === null && !profile.introSeen && readdirSync(dir).some((f) => f.startsWith("profilo.corrotto-")));
    assert.equal(messages.length, 1);
    profile.setName("Anna");
    assert.equal(new Profile(dir).name, "Anna");
  });
  it("file qualsiasi non json: si riparte senza errori", () => {
    const dir = tempDirectory();
    write(dir, "non e' json");
    const profile = new Profile(dir);
    assert.ok(profile.name === null && !profile.introSeen);
  });
});
