// Il giardino su Windows: quello che il contratto con il Mac non copre (il file, gli interruttori, le regole del catalogo). I tiri, i sentieri,
// il terreno, il mondo e un giardino passo per passo sono confrontati con il Mac in contratto.test.ts.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Garden, GARDEN_FORMAT_VERSION } from "../src/core/garden.ts";
import { GARDEN_ITEMS, itemNumber, itemWithId, nameWithArticle, rarityOf, RETIRED_ITEMS } from "../src/core/gardenCatalog.ts";
import { DropStream, giftLine, hash, mixedHash, noneFoundYet, startingDropState } from "../src/core/gardenDrops.ts";
import { BRIDGES, bridgeId, ISLANDS, pathTiles } from "../src/core/gardenGrid.ts";
import { GARDEN_INTERACTIONS, interactionImage } from "../src/core/gardenInteractions.ts";
import type { StudySession } from "../src/core/log.ts";
import { tempDirectory } from "./util.ts";

const focus = (n: number, seconds: number, completed = true): StudySession =>
  ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, start: 0, seconds, plannedMinutes: 50, completed });

describe("Giardino: il catalogo", () => {
  it("54 oggetti, numeri dalla posizione, nessun oggetto tolto rimasto", () => {
    assert.equal(GARDEN_ITEMS.length, 54);
    assert.equal(new Set(GARDEN_ITEMS.map((x) => x.id)).size, 54);
    assert.equal(itemNumber("margherite"), 1);
    assert.equal(itemNumber("tana-foglie"), 47);
    assert.equal(itemNumber("sasso-sole"), 48);
    assert.equal(itemNumber("rifugio-paglia"), 54);
    for (const id of RETIRED_ITEMS) assert.equal(itemWithId(id), undefined);
  });
  it("rarità: 19 comuni, 29 rari, 6 leggendari", () => {
    const count = (r: string) => GARDEN_ITEMS.filter((x) => rarityOf(x) === r).length;
    assert.deepEqual([count("common"), count("rare"), count("legendary")], [19, 29, 6]);
  });
  it("gli articoli delle cose degli animali", () => {
    assert.equal(nameWithArticle(itemWithId("casetta-gatto")!), "la casa del gatto");
    assert.equal(nameWithArticle(itemWithId("annaffiatoio")!), "l'annaffiatoio");
    assert.equal(nameWithArticle(itemWithId("hotel-insetti")!), "l'hotel degli insetti");
    assert.equal(nameWithArticle(itemWithId("cesto-carote")!), "il cesto di carote");
    assert.equal(nameWithArticle(itemWithId("bandiera-traguardo")!), "la bandierina del traguardo");
    assert.equal(nameWithArticle(itemWithId("aiuola-fragole")!), "l'aiuola di fragole");
  });
  it("ogni cosa di un animale sta sulla sua isola, e ogni isola ne ha", () => {
    for (const x of GARDEN_ITEMS) if (x.island !== null) assert.ok(ISLANDS.includes(x.island), x.id);
    for (const island of ISLANDS) assert.ok(GARDEN_ITEMS.some((x) => x.island === island), island);
  });
});

describe("Giardino: i numeri a 32 bit", () => {
  it("FNV-1a e Mulberry32 sui valori noti", () => {
    assert.equal(hash(""), 2_166_136_261);
    assert.equal(hash("a"), 0xE40C292C);
    assert.ok(mixedHash("a") >= 0 && mixedHash("a") < 2 ** 32);
    const s = new DropStream(0xFFFF_FFFF);
    for (let i = 0; i < 1000; i++) { const x = s.next(); assert.ok(x >= 0 && x < 1); }
  });
});

describe("Giardino: il mondo", () => {
  it("sette ponti, e ogni sentiero tocca i suoi approdi", () => {
    assert.deepEqual(BRIDGES.map(bridgeId), ["pianty-porcellino", "pianty-ciccio", "porcellino-gattino", "porcellino-tartaruga", "ciccio-gattino", "gattino-riccio", "tartaruga-riccio"]);
    for (const island of ISLANDS) for (const size of [8, 9, 10]) {
      const path = pathTiles(island, size);
      assert.ok(path.length > 0);
      assert.ok(path.every((t) => !(t.col < 3 && t.row < 3)), `${island} ${size}: il sentiero passa dalla casa`);
    }
  });
});

describe("Giardino: il file", () => {
  it("un giardino nuovo si scrive solo al primo cambiamento, nel formato del Mac", () => {
    const dir = tempDirectory();
    const g = new Garden(dir);
    assert.equal(existsSync(join(dir, "giardino.json")), false);
    assert.equal(g.placements.length, 3);
    g.adoptHome("riccio");
    const text = readFileSync(join(dir, "giardino.json"), "utf8");
    assert.match(text, /^\{\n  "companions" : \{\},\n  "drops" : \{/);
    const saved = JSON.parse(text) as { version: number; home: string; placements: Array<{ id: string; island: string }> };
    assert.equal(saved.version, GARDEN_FORMAT_VERSION);
    assert.equal(saved.home, "riccio");
    assert.ok(saved.placements.every((p) => p.id === p.id.toUpperCase() && p.island === "riccio"));
  });
  it("un file rovinato si mette da parte e si riparte", () => {
    const dir = tempDirectory();
    writeFileSync(join(dir, "giardino.json"), "{ non è json");
    const problems: string[] = [];
    const g = new Garden(dir, { now: () => 1_700_000_000_000 });
    g.onProblem = (m) => problems.push(m);
    assert.deepEqual(problems, ["Il file del giardino era rovinato: l'ho messo da parte come giardino.corrotto-1700000000.json."]);
    assert.ok(readdirSync(dir).includes("giardino.corrotto-1700000000.json"));
    assert.equal(g.placements.length, 3);
  });
  it("un campo del tipo sbagliato rende rovinato tutto il file, come in Swift", () => {
    const dir = tempDirectory();
    writeFileSync(join(dir, "giardino.json"), JSON.stringify({ version: 4, placements: [], companions: {}, corners: "te" }));
    new Garden(dir);
    assert.ok(readdirSync(dir).some((name) => name.startsWith("giardino.corrotto-")));
  });
  it("un file di una versione più nuova si legge e non si riscrive", () => {
    const dir = tempDirectory();
    const text = JSON.stringify({ version: 9, placements: [], companions: {}, drops: { found: { lavanda: 1 }, sinceRare: 0, sinceLegendary: 0 } });
    writeFileSync(join(dir, "giardino.json"), text);
    const g = new Garden(dir);
    assert.equal(g.isReadOnly, true);
    assert.equal(g.has("lavanda"), true);
    g.adoptHome("gattino");
    assert.equal(readFileSync(join(dir, "giardino.json"), "utf8"), text);
  });
  it("«Cancella tutto» toglie il file e riparte dalla dotazione", () => {
    const dir = tempDirectory();
    const g = new Garden(dir);
    g.adoptHome("gattino");
    g.reset();
    assert.equal(existsSync(join(dir, "giardino.json")), false);
    assert.equal(g.home, null);
    assert.equal(g.foundCount, 3);
  });
});

describe("Giardino: le prime volte", () => {
  it("la prima figurina: quanto manca, e dove trovarla", () => {
    assert.equal(giftLine({ kind: "progress" }, 35, true), "Mancano 35 minuti di studio alla prima figurina.");
    assert.equal(giftLine({ kind: "found", drop: { item: "tulipani", rarity: "common" } }, 68, true),
      "Nuova figurina: Tulipani (n. 4). La trovi nell'album e puoi metterla nel giardino.");
  });
  it("all'inizio non si è trovato niente (la dotazione non conta); dopo una figurina sì", () => {
    const state = startingDropState();
    assert.ok(noneFoundYet(state));
    state.found["tulipani"] = 1;
    assert.ok(!noneFoundYet(state));
  });
});

describe("Giardino: i regali", () => {
  it("un focus interrotto o corto non conta, e lo stesso focus non tira due volte", () => {
    const g = new Garden(tempDirectory());
    assert.equal(g.rollGift(focus(1, 3000, false), 1).kind, "notEligible");
    assert.equal(g.rollGift(focus(2, 1199), 1).kind, "notEligible");
    assert.equal(g.rollGift(focus(3, 1800), 1).kind, "progress");
    assert.equal(g.rollGift(focus(3, 1800), 1).kind, "notEligible");
    assert.equal(g.drops.studyBank, 1800);
    assert.equal(g.minutesToNextGift, 30);
  });
  it("con `quickGifts` un focus da un minuto conta e ogni minuto vale un'ora", () => {
    const g = new Garden(tempDirectory(), { quickGifts: () => true });
    const gift = g.rollGift(focus(4, 60), 1);
    assert.equal(gift.kind, "found");
    assert.equal(g.unseen.size, 1);
  });
  it("le cose degli animali escono solo dalle isole aperte", () => {
    const g = new Garden(tempDirectory(), { quickGifts: () => true });
    g.isIslandOpen = (id) => id === "pianty";
    for (let n = 0; n < 60; n++) g.rollGift(focus(100 + n, 600), 1);
    const found = Object.keys(g.drops.found).map((id) => itemWithId(id)!);
    assert.ok(found.every((x) => x.island === null || x.island === "pianty"));
    assert.equal(g.minutesToNextGift, null);
    assert.equal(g.rollGift(focus(999, 600), 1).kind, "complete");
  });
  it("in modalità sviluppatore l'album è pieno ma i regali no", () => {
    const g = new Garden(tempDirectory(), { developer: () => true });
    assert.ok(GARDEN_ITEMS.every((x) => g.isFound(x.id)));
    assert.equal(g.foundCount, 3);
    assert.equal(g.islandSize, 10);
  });
});

describe("Giardino: i compagni usano le cose", () => {
  it("ventiquattro scene, ognuna con la sua immagine in assets/interazioni e una cosa che può stare sull'isola del compagno", () => {
    assert.equal(GARDEN_INTERACTIONS.length, 24);
    for (const i of GARDEN_INTERACTIONS) {
      assert.ok(existsSync(join(import.meta.dirname, "..", "..", "assets", interactionImage(i) + ".png")), interactionImage(i));
      const item = itemWithId(i.item);
      assert.ok(item && (item.island === null || item.island === i.pet), i.item);
    }
  });
});
