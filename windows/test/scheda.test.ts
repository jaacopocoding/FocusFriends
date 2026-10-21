// I dati della scheda (core/card.ts) e le regole del sottofondo.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildCardData, companionLocks, musicLabel } from "../src/core/card.ts";
import type { CardInput } from "../src/core/card.ts";
import { Profile } from "../src/core/profile.ts";
import { ambientOfChoice, backgroundCurrent, nearestStep, nextAmbient, BACKGROUND_CHOICES, BACKGROUND_TITLES } from "../src/core/rules.ts";
import { date, session, tempDirectory, ZONE } from "./util.ts";

const NOW = date(2026, 10, 14, 20, 0);

function input(overrides: Partial<CardInput> = {}): CardInput {
  return {
    now: NOW, zone: ZONE, sessions: [],
    profile: new Profile(tempDirectory()),
    petVisible: true,
    timers: { focus: [30, 50], rest: [5, 10], customFocus: [], customRest: [] },
    chattiness: "sometimes", movementOn: true, askOn: true,
    ambient: "none", ambientVolume: 0.25, music: "off", musicFolder: null, musicVolume: 0.3,
    lastSessionId: null, recentSubjects: [], lastNote: null, todoItems: [],
    ...overrides,
  };
}

describe("Sottofondo", () => {
  it("la scelta corrente: il suono vince, poi la musica, poi niente", () => {
    assert.equal(backgroundCurrent("none", "off"), "none");
    assert.equal(backgroundCurrent("rain", "off"), "rain");
    assert.equal(backgroundCurrent("wind", "off"), "wind");
    assert.equal(backgroundCurrent("none", "bundled"), "music");
    assert.equal(backgroundCurrent("none", "folder"), "music");
    assert.equal(backgroundCurrent("brown", "folder"), "brown", "se per errore sono accesi entrambi vince il suono");
  });
  it("il suono di ogni scelta e i nomi, nell'ordine della schermata", () => {
    assert.deepEqual(BACKGROUND_CHOICES.map((c) => ambientOfChoice(c)), ["none", "rain", "wind", "brown", null]);
    assert.deepEqual(BACKGROUND_CHOICES.map((c) => BACKGROUND_TITLES[c]), ["Nessuno", "Pioggia", "Vento", "Marrone", "Musica"]);
  });
  it("il ciclo dei suoni torna a Nessuno", () => {
    assert.deepEqual((["none", "rain", "brown", "wind"] as const).map(nextAmbient), ["rain", "brown", "wind", "none"]);
  });
  it("il livello di volume più vicino", () => {
    assert.equal(nearestStep(0.27), 0.25);
    assert.equal(nearestStep(0.55), 0.6);
    assert.equal(nearestStep(0), 0.1);
  });
});

describe("Scheda: i dati", () => {
  it("senza sessioni: oggi è vuoto", () => {
    const data = buildCardData(input());
    assert.deepEqual([data.todaySeconds, data.todayFocusCount, data.streak, data.streakFrozen, data.userName, data.background], [0, 0, 0, false, null, "none"]);
    assert.deepEqual(data.companions.map((c) => [c.id, c.lock]), [["pianty", null], ["porcellino", null], ["ciccio", null], ["gattino", null]]);
  });

  it("oggi: minuti, focus e serie (con un giorno di ghiaccio)", () => {
    const sessions = [
      session({ start: date(2026, 10, 12, 10), seconds: 1500 }),
      session({ start: date(2026, 10, 14, 9), seconds: 1800 }),
      session({ start: date(2026, 10, 14, 15), seconds: 1200 }),
      session({ start: date(2026, 10, 13, 10), seconds: 600 }),
    ];
    const data = buildCardData(input({ sessions }));
    assert.deepEqual([data.todaySeconds, data.todayFocusCount, data.streak, data.streakFrozen], [3000, 2, 3, false]);
    const yesterday = buildCardData(input({ sessions: [sessions[3]!, sessions[1]!], now: date(2026, 10, 15, 8) }));
    assert.deepEqual([yesterday.todaySeconds, yesterday.streak, yesterday.streakFrozen], [0, 2, false], "ieri studiato: niente ghiaccio");
    const frozen = buildCardData(input({ sessions: [sessions[0]!, sessions[3]!], now: date(2026, 10, 15, 8) }));
    assert.deepEqual([frozen.streak, frozen.streakFrozen], [2, true], "ieri saltato, oggi ancora vuoto: ghiacciata");
  });

  it("compagni bloccati: cosa manca, e quanti ne hai", () => {
    const dir = tempDirectory();
    const profile = new Profile(dir);
    profile.chooseFirstCompanion("pianty");
    const ids = ["pianty", "porcellino", "ciccio", "gattino"];
    assert.deepEqual([...companionLocks(profile, [], ids)], [
      ["porcellino", "si sblocca a 20 focus: ne hai 0"], ["ciccio", "si sblocca a 50 focus: ne hai 0"], ["gattino", "si sblocca a 100 focus: ne hai 0"],
    ]);
    const twelve = [session({ start: date(2026, 10, 1, 9), seconds: 12 * 3000 + 100 })];
    const locks = companionLocks(profile, twelve, ids);
    assert.equal(locks.get("porcellino"), "si sblocca a 20 focus: ne hai 12");
    const data = buildCardData(input({ profile, sessions: twelve }));
    assert.equal(data.companions.find((c) => c.id === "ciccio")?.lock, "si sblocca a 50 focus: ne hai 12");
    assert.equal(data.companions.find((c) => c.id === "pianty")?.lock, null);
    assert.deepEqual([...companionLocks(new Profile(tempDirectory()), [], ids)], [], "chi non ha scelto non ha niente di bloccato");
  });

  it("la modalità sviluppatore non lascia niente di bloccato", () => {
    const profile = new Profile(tempDirectory(), { developer: () => true });
    profile.chooseFirstCompanion("pianty");
    assert.equal([...companionLocks(profile, [], ["pianty", "ciccio"])].length, 0);
  });

  it("sottofondo e volume: quello della musica, se è la musica", () => {
    const rain = buildCardData(input({ ambient: "rain", ambientVolume: 0.4, musicVolume: 0.3 }));
    assert.deepEqual([rain.background, rain.backgroundVolume], ["rain", 0.4]);
    const music = buildCardData(input({ music: "folder", musicFolder: "C:\\Musica\\Studio", musicVolume: 0.3 }));
    assert.deepEqual([music.background, music.backgroundVolume, music.musicLabel], ["music", 0.3, "Cartella: Studio"]);
  });

  it("l'etichetta della musica", () => {
    assert.equal(musicLabel("off", null), "Spenta");
    assert.equal(musicLabel("bundled", null), "Brani inclusi");
    assert.equal(musicLabel("folder", null), "La mia cartella");
    assert.equal(musicLabel("folder", "/Users/x/Lofi/"), "Cartella: Lofi");
  });

  it("l'ultimo focus: il voto, se dato", () => {
    const withRating = session({ start: date(2026, 10, 14, 9), seconds: 1500, rating: "good" });
    const without = session({ start: date(2026, 10, 14, 11), seconds: 1500 });
    assert.deepEqual(
      [buildCardData(input({ sessions: [withRating, without], lastSessionId: withRating.id })).lastRating,
       buildCardData(input({ sessions: [withRating, without], lastSessionId: without.id })).lastRating,
       buildCardData(input({ sessions: [withRating, without], lastSessionId: "inesistente" })).hasLastSession],
      ["good", null, false]);
  });
});
