import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { SUBJECT_COLORS, subjectColor, subjectColorIndex } from "../src/core/colors.ts";

describe("Colori delle materie", () => {
  it("lo stesso indice che calcola l'app per Mac (valori misurati con Swift)", () => {
    const expected: Array<[string, number]> = [
      ["Anatomia", 7], ["fisica", 4], ["FISICA", 4], ["Chimica organica", 7], ["Matematica", 3], ["Storia dell'arte", 5],
      ["😀 Latino", 4], ["Biochimica", 5], ["A", 6], ["Fisiologia umana ".repeat(6), 3], ["Èsame", 3], ["Senza materia", 1], ["İstanbul", 6],
    ];
    for (const [name, index] of expected) assert.equal(subjectColorIndex(name), index, name);
  });
  it("maiuscole e minuscole non cambiano il colore; il colore è uno degli otto", () => {
    assert.equal(subjectColor("Fisica"), subjectColor("FISICA"));
    assert.equal(SUBJECT_COLORS.length, 8);
    assert.match(subjectColor("Anatomia"), /^rgb\(\d+, \d+, \d+\)$/);
  });
});
