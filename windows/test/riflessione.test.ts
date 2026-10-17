// «Com'è andata?» (core/reflection.ts).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ALL_REPLIES, reflectionReply, saveReflection } from "../src/core/reflection.ts";
import { SessionLog } from "../src/core/log.ts";
import { date, tempDirectory, ZONE } from "./util.ts";

describe("Com'è andata", () => {
  it("una parolina per ogni risposta, tre varianti ciascuna", () => {
    for (const rating of ["good", "soso", "poor"] as const) {
      assert.equal(ALL_REPLIES[rating].length, 3);
      const seen = new Set([0, 0.4, 0.8].map((r) => reflectionReply(rating, () => r)));
      assert.equal(seen.size, 3, rating);
    }
    assert.equal(reflectionReply("good", () => 0), "Che bello! Segnato nel diario.");
  });

  it("si salva il voto e la nota; con la sola nota il voto già dato resta; senza niente non si scrive", () => {
    const log = new SessionLog(tempDirectory(), { zone: ZONE });
    const made = log.add({ start: date(2026, 10, 14, 9), seconds: 1500, plannedMinutes: 25, completed: true, subject: "Anatomia" })!;
    assert.equal(saveReflection(log, made.id, null, "   "), false);
    assert.ok(log.sessions[0]?.rating === undefined && log.sessions[0]?.note === undefined);
    assert.equal(saveReflection(log, made.id, "poor", "  nervi   cranici "), true);
    assert.deepEqual([log.sessions[0]?.rating, log.sessions[0]?.note], ["poor", "nervi cranici"]);
    saveReflection(log, made.id, null, "solo una nota nuova");
    assert.deepEqual([log.sessions[0]?.rating, log.sessions[0]?.note], ["poor", "solo una nota nuova"]);
    saveReflection(log, made.id, "good", null);
    assert.deepEqual([log.sessions[0]?.rating, log.sessions[0]?.note], ["good", undefined], "un nuovo voto senza nota toglie la nota (come sul Mac)");
  });
});
