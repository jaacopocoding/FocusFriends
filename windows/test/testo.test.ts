import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { cleanFocusNote, cleanFocusNotes, cleanName, cleanNote, cleanSubject, subjectKey,
  FOCUS_NOTE_MAX, FOCUS_NOTES_COUNT, NAME_MAX, NOTE_MAX, SUBJECT_MAX } from "../src/core/text.ts";

describe("Materie", () => {
  it("si puliscono", () => {
    assert.equal(cleanSubject("  Anatomia  "), "Anatomia");
    assert.equal(cleanSubject("Fisica   generale"), "Fisica generale");
    assert.equal(cleanSubject("   "), null);
    assert.equal(cleanSubject(null), null);
    assert.equal(Array.from(cleanSubject("a".repeat(80)) ?? "").length, SUBJECT_MAX);
  });
  it("la chiave ignora accenti e maiuscole", () => {
    assert.equal(subjectKey("Èsame"), subjectKey("esame"));
    assert.equal(subjectKey("FISICA"), subjectKey("Física"));
  });
  it("conta i caratteri, non le unità di UTF-16", () => {
    const emoji = "🌱".repeat(50);
    assert.equal(Array.from(cleanSubject(emoji) ?? "").length, SUBJECT_MAX);
  });
});

describe("Nome", () => {
  it("si pulisce", () => {
    assert.equal(cleanName("  Marco  "), "Marco");
    assert.equal(cleanName("Anna   Maria"), "Anna Maria");
    assert.equal(cleanName("marco"), "marco");
    assert.equal(cleanName("   "), null);
    assert.equal(cleanName(null), null);
    assert.equal(cleanName(""), null);
    assert.equal(cleanName("Ma\u0000rco\u0007"), "Marco");
    assert.equal(Array.from(cleanName("x".repeat(60)) ?? "").length, NAME_MAX);
    assert.equal(cleanName("Zoë 🌱"), "Zoë 🌱");
  });
});

describe("Note", () => {
  it("la nota «cosa hai fatto»", () => {
    assert.equal(cleanNote("  cap. 4,   nervi\tcranici "), "cap. 4, nervi cranici");
    assert.equal(cleanNote("   "), null);
    assert.equal(cleanNote(null), null);
    assert.equal(Array.from(cleanNote("x".repeat(200)) ?? "").length, NOTE_MAX);
  });
  it("le note del focus", () => {
    assert.equal(cleanFocusNote("  chiedere   al prof \t la trasformata "), "chiedere al prof la trasformata");
    assert.equal(cleanFocusNote("   "), null);
    assert.equal(cleanFocusNote(null), null);
    assert.equal(Array.from(cleanFocusNote("x".repeat(500)) ?? "").length, FOCUS_NOTE_MAX);
    assert.deepEqual(cleanFocusNotes(["  a ", "", "  ", "b"]), ["a", "b"]);
    assert.equal(cleanFocusNotes([]), null);
    assert.equal(cleanFocusNotes(["   "]), null);
    assert.equal(cleanFocusNotes(Array.from({ length: 100 }, (_, i) => `n${i}`))?.length, FOCUS_NOTES_COUNT);
  });
});
