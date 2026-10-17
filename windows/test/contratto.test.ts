// Il contratto con la versione per Mac: da ogni cartella di dati di esempio (tests/fixtures/) questo codice deve
// ricavare esattamente quello che ne ricava Swift (tests/fixtures/attesi/, generati da tests/genera-attesi.sh).
// Il giardino non c'è ancora: le cartelle «giardino-*» e la parte `giardino` degli altri file si saltano.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { derive, fixtureNames } from "./atteso.ts";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "tests", "fixtures");

describe("contratto con la versione per Mac", () => {
  for (const name of fixtureNames(fixtures)) {
    if (name.startsWith("giardino")) continue;
    it(name, () => {
      const expected = JSON.parse(readFileSync(join(fixtures, "attesi", `${name}.json`), "utf8")) as Record<string, unknown>;
      delete expected["giardino"];
      // Le cartelle senza sessioni né in corso non hanno il pezzo `registro`, e così via: `derive` produce le stesse chiavi.
      const actual = JSON.parse(JSON.stringify(derive(fixtures, name))) as Record<string, unknown>;
      assert.deepEqual(actual, expected);
    });
  }
});
