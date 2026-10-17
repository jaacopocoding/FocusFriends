// Le frasi dei compagni e il mazzo mischiato (windows/src/core/phrases.ts).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PhraseDeck, loadPhrases, parsePhrases } from "../src/core/phrases.ts";
import { PETS, PET_IDS } from "../src/core/pets.ts";
import { tempDirectory } from "./util.ts";

const assets = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "assets");

/** Un generatore di numeri a caso che si può rifare uguale (le prove non devono dipendere dalla fortuna). */
function seeded(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 2 ** 32;
  };
}

describe("File delle frasi", () => {
  it("una frase per riga, senza righe vuote né commenti", () => {
    assert.deepEqual(parsePhrases("  uno \n\n# un commento\ndue\r\n\t\ttre\t\r\n   \n#altro"), ["uno", "due", "tre"]);
    assert.deepEqual(parsePhrases(""), []);
    assert.deepEqual(parsePhrases("a\rb\u2028c"), ["a", "b", "c"]);
  });

  it("il file dell'utente ha la precedenza su quello incluso", () => {
    const user = tempDirectory(), bundled = tempDirectory();
    writeFileSync(join(bundled, "frasi_gattino.txt"), "incluso uno\nincluso due\n");
    assert.deepEqual(loadPhrases("gattino", { userDirectory: user, bundledDirectory: bundled }), ["incluso uno", "incluso due"]);
    writeFileSync(join(user, "frasi_gattino.txt"), "# le mie\nmia frase\n");
    assert.deepEqual(loadPhrases("gattino", { userDirectory: user, bundledDirectory: bundled }), ["mia frase"]);
  });

  it("un file dell'utente senza frasi lascia passare quello incluso; senza nessuna, la frase di riserva", () => {
    const user = tempDirectory(), bundled = tempDirectory();
    writeFileSync(join(user, "frasi_ciccio.txt"), "# solo un commento\n\n");
    writeFileSync(join(bundled, "frasi_ciccio.txt"), "dal file incluso");
    assert.deepEqual(loadPhrases("ciccio", { userDirectory: user, bundledDirectory: bundled }), ["dal file incluso"]);
    const empty = tempDirectory();
    for (const pet of PETS) {
      assert.deepEqual(loadPhrases(pet.id, { userDirectory: empty, bundledDirectory: empty }), [pet.fallbackQuote]);
    }
  });

  it("il file con il segno dell'ordine dei byte all'inizio si legge", () => {
    const user = tempDirectory();
    writeFileSync(join(user, "frasi_pianty.txt"), "\uFEFFprima\nseconda\n");
    assert.deepEqual(loadPhrases("pianty", { userDirectory: user, bundledDirectory: user }), ["prima", "seconda"]);
  });

  it("i file inclusi nell'app ci sono per tutti i compagni e hanno frasi", () => {
    const empty = tempDirectory();
    for (const id of PET_IDS) {
      const phrases = loadPhrases(id, { userDirectory: empty, bundledDirectory: assets });
      assert.ok(phrases.length > 1, `${id}: ${phrases.length} frasi`);
      assert.ok(new Set(phrases).size === phrases.length, `${id}: nessuna frase ripetuta nel file`);
    }
  });
});

describe("Mazzo di frasi", () => {
  const phrases = ["a", "b", "c", "d", "e"];

  it("escono tutte prima che una si ripeta, giro dopo giro", () => {
    const deck = new PhraseDeck(seeded(1));
    for (let round = 0; round < 6; round += 1) {
      const drawn = phrases.map(() => deck.draw(phrases));
      assert.deepEqual([...drawn].sort(), phrases, `giro ${round}`);
    }
  });

  it("la prima del mazzo nuovo non è l'ultima uscita", () => {
    for (let seed = 1; seed <= 200; seed += 1) {
      const deck = new PhraseDeck(seeded(seed));
      let previous: string | null = null;
      for (let i = 0; i < 30; i += 1) {
        const next = deck.draw(["x", "y", "z"]);
        assert.notEqual(next, previous, `seme ${seed}, estrazione ${i}`);
        previous = next;
      }
    }
  });

  it("con una sola frase esce sempre quella; senza frasi, niente", () => {
    const deck = new PhraseDeck(seeded(3));
    assert.deepEqual([deck.draw(["sola"]), deck.draw(["sola"]), deck.draw(["sola"])], ["sola", "sola", "sola"]);
    assert.equal(new PhraseDeck().draw([]), null);
  });

  it("le frasi doppie contano una volta", () => {
    const deck = new PhraseDeck(seeded(4));
    const drawn = [deck.draw(["a", "a", "b"]), deck.draw(["a", "a", "b"])];
    assert.deepEqual([...drawn].sort(), ["a", "b"]);
  });

  it("se il file cambia a metà mazzo, le tolte spariscono e le nuove entrano senza far ripetere le già uscite", () => {
    const deck = new PhraseDeck(seeded(5));
    const first = deck.draw(["a", "b", "c", "d"])!;
    const rest = ["a", "b", "c", "d"].filter((p) => p !== first);
    // via una non ancora uscita, dentro una nuova
    const removed = rest[0]!;
    const edited = ["a", "b", "c", "d", "nuova"].filter((p) => p !== removed);
    const seenInRound: string[] = [first];
    for (let i = 0; i < edited.length - 1; i += 1) seenInRound.push(deck.draw(edited)!);
    assert.ok(!seenInRound.includes(removed), "la frase tolta non esce più");
    assert.ok(seenInRound.includes("nuova"), "la nuova esce nel giro in corso");
    assert.equal(new Set(seenInRound).size, seenInRound.length, "nessuna ripetizione nel giro");
  });
});

