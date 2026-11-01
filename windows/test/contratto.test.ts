// Il contratto con la versione per Mac: da ogni cartella di dati di esempio (tests/fixtures/) questo codice deve
// ricavare esattamente quello che ne ricava Swift (tests/fixtures/attesi/, generati da tests/genera-attesi.sh).
// Il giardino senza una cartella di dati (tiri, sentieri, terreno, ponti, luce, angoli, ospiti, un giardino passo per passo) sta in `_giardino.json`.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { anniversariesJson, derive, fixtureNames, gridsJson, syntheticYearJson } from "./atteso.ts";
import { gardenSyntheticJson } from "./giardino.ts";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "tests", "fixtures");

describe("contratto con la versione per Mac", () => {
  for (const name of fixtureNames(fixtures)) {
    it(name, () => {
      const expected = JSON.parse(readFileSync(join(fixtures, "attesi", `${name}.json`), "utf8")) as Record<string, unknown>;
      // Le cartelle senza sessioni né in corso non hanno il pezzo `registro`, e così via: `derive` produce le stesse chiavi.
      const actual = JSON.parse(JSON.stringify(derive(fixtures, name))) as Record<string, unknown>;
      assert.deepEqual(actual, expected);
    });
  }

  it("gli anniversari («un mese insieme»…) su date inventate", () => {
    const expected = JSON.parse(readFileSync(join(fixtures, "attesi", "_contesto-anniversari.json"), "utf8")) as unknown;
    assert.deepEqual(JSON.parse(JSON.stringify(anniversariesJson())), expected);
  });

  it("la mappa dell'anno: le griglie di 41 anni (bisestili, che cominciano di domenica…)", () => {
    const expected = JSON.parse(readFileSync(join(fixtures, "attesi", "_anno-griglie.json"), "utf8")) as unknown;
    assert.deepEqual(JSON.parse(JSON.stringify(gridsJson())), expected);
  });

  it("la scheda «Anno» su un anno e mezzo di studio inventato (materie scritte in modi diversi)", () => {
    const expected = JSON.parse(readFileSync(join(fixtures, "attesi", "_anno-sintetico.json"), "utf8")) as unknown;
    assert.deepEqual(JSON.parse(JSON.stringify(syntheticYearJson())), expected);
  });

  describe("il giardino", () => {
    // Swift scrive «-0» per i numeri piccolissimi arrotondati da sotto lo zero, JSON.stringify scrive «0»: qui sono la stessa cosa
    const expected = JSON.parse(readFileSync(join(fixtures, "attesi", "_giardino.json"), "utf8"), (_, value: unknown) => (Object.is(value, -0) ? 0 : value)) as Record<string, unknown>;
    const actual = JSON.parse(JSON.stringify(gardenSyntheticJson())) as Record<string, unknown>;
    for (const section of Object.keys(expected)) {
      it(section, () => assert.deepEqual(actual[section], expected[section]));
    }
  });
});
