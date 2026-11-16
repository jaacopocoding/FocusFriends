// I dati della scheda (core/card.ts) e le regole del sottofondo.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildCardData, companionLocks, musicLabel } from "../src/core/card.ts";
import type { CardInput } from "../src/core/card.ts";
import { Profile } from "../src/core/profile.ts";
import {
  avatarCountLine, avatarEntries, avatarProgress, hoursText, HIDDEN_NAME, nextAvatar, nextAvatarLine, remainingText,
} from "../src/core/rewards.ts";
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
    assert.deepEqual(data.avatars.map((c) => [c.id, c.lock, c.unlocked]), [
      ["pianty", null, true], ["porcellino", null, true], ["ciccio", null, true], ["gattino", null, true], ["riccio", null, true], ["tartaruga", null, true],
    ]);
    assert.equal(data.focusesDone, 0);
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
    assert.equal(data.avatars.find((c) => c.id === "ciccio")?.lock, "si sblocca a 50 focus: ne hai 12");
    assert.equal(data.avatars.find((c) => c.id === "pianty")?.lock, null);
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

describe("Avatar (la riga e la pagina della scheda)", () => {
  const pets = ["pianty", "porcellino", "ciccio"];

  it("gli avatar nell'ordine di sblocco, con quanto serve e chi c'è già; il prossimo è il primo bloccato", () => {
    const roster = avatarEntries("ciccio", pets, (id) => id === "ciccio" || id === "pianty");
    assert.deepEqual(roster.map((e) => [e.id, e.need, e.unlocked]), [["ciccio", 0, true], ["pianty", 20, true], ["porcellino", 50, false]]);
    assert.equal(nextAvatar(roster)?.id, "porcellino");
    assert.equal(nextAvatar(roster.map((e) => ({ ...e, unlocked: true }))), null);
  });

  it("i testi: quanto manca (mai zero), le ore, la strada fatta, le righe della scheda", () => {
    assert.deepEqual([remainingText(50, 32), remainingText(50, 49), remainingText(50, 80)], ["ancora 18 focus pieni", "ancora 1 focus pieno", "ancora 1 focus pieno"]);
    assert.deepEqual([hoursText(50, 32), hoursText(50, 49)], ["circa 15 h", "circa 1 h"]);
    assert.deepEqual([avatarProgress(50, 32), avatarProgress(50, 90), avatarProgress(0, 0)], [0.64, 1, 1]);
    assert.equal(nextAvatarLine(20, 12), "Prossimo compagno: ancora 8 focus pieni");
    assert.deepEqual([avatarCountLine(2, 2), avatarCountLine(4, 0)], ["2 con te · 2 da sbloccare", "4 con te"]);
  });

  it("chi non c'è ancora non ha nome: né nei testi né nei dati della scheda", () => {
    const texts = [nextAvatarLine(20, 12), remainingText(50, 32), hoursText(50, 32), avatarCountLine(2, 2)];
    assert.equal(HIDDEN_NAME, "???");
    assert.ok(!texts.some((t) => ["Pianty", "Porcellino", "Ciccio", "Gattino"].some((name) => t.includes(name))));
    const profile = new Profile(tempDirectory());
    profile.chooseFirstCompanion("gattino");
    const twelve = [session({ start: date(2026, 10, 1, 9), seconds: 12 * 3000 + 100 })];
    const data = buildCardData(input({ profile, sessions: twelve }));
    assert.equal(data.avatars[0]?.id, "gattino", "prima quello scelto");
    assert.deepEqual(data.avatars.map((e) => e.name), ["Gattino", "???", "???", "???", "???", "???"]);
    assert.equal(data.avatars[1]?.need, 20);
    assert.equal(data.focusesDone, 12);
    assert.ok(data.avatars.every((e) => e.islandThings > 0), "ogni isola ha le sue cose da trovare");
  });
});
