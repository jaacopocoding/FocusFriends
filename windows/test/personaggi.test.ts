// I dati dei compagni (data/pets.json, generato da Pet.swift) e le regole che ne ricavano gli stadi.

import { CALL_CYCLE, callPose } from "../src/core/callHop.ts";
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PETS, PET_IDS, finalStage, focusGrowthStage, growsWithTimer, iconImage, restImageIndex, restStage, stageCount, stageForProgress } from "../src/core/pets.ts";

const assets = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "assets");

describe("Compagni", () => {
  it("i sei, nell'ordine dei personaggi", () => {
    assert.deepEqual(PET_IDS, ["pianty", "porcellino", "ciccio", "gattino", "riccio", "tartaruga"]);
  });

  it("tutte le immagini esistono in assets/", () => {
    for (const pet of PETS) {
      const files = [...pet.images, ...pet.focusGrowthImages, ...(pet.picked ? [pet.picked.image] : [])];
      for (const file of files) assert.ok(existsSync(join(assets, file)), `${pet.id}: manca ${file}`);
    }
  });

  it("i fotogrammi indicati esistono tra le immagini", () => {
    for (const pet of PETS) {
      const lists = [pet.walkFrames, pet.eatFrames, pet.sleepFrames, pet.popcornFrames];
      for (const index of [...lists.flat(), ...[pet.talkFrame, pet.sleepIntroFrame].filter((i): i is number => i !== null)]) {
        const limit = pet.framesPerStage ?? pet.images.length;
        assert.ok(index >= 0 && index < limit, `${pet.id}: fotogramma ${index} fuori dalle ${limit} pose`);
      }
    }
  });

  it("gli stadi ricavati dai dati sono uguali a quelli che ricava l'app per Mac", () => {
    for (const pet of PETS) {
      assert.equal(stageCount(pet), pet.stageCount, pet.id);
      assert.equal(finalStage(pet), pet.finalStage, pet.id);
      assert.equal(restStage(pet), pet.restStage, pet.id);
      assert.equal(restImageIndex(pet), pet.restImageIndex, pet.id);
      assert.equal(growsWithTimer(pet), pet.growsWithTimer, pet.id);
      assert.equal(iconImage(pet), pet.iconImage, pet.id);
      assert.deepEqual(Array.from({ length: 11 }, (_, i) => stageForProgress(pet, i / 10)), pet.stages, pet.id);
      assert.deepEqual(Array.from({ length: 11 }, (_, i) => focusGrowthStage(pet, i / 10)), pet.focusGrowthStages, pet.id);
    }
  });

  it("gli estremi dell'avanzamento", () => {
    const pianty = PETS[0]!;
    assert.equal(stageForProgress(pianty, -1), 0);
    assert.equal(stageForProgress(pianty, 2), 4);
    assert.equal(stageForProgress(pianty, 1), 4);
    const ciccio = PETS.find((p) => p.id === "ciccio")!;
    assert.equal(focusGrowthStage(ciccio, 5), 4);
    assert.equal(focusGrowthStage(PETS.find((p) => p.id === "gattino")!, 0.5), 0, "il Gattino cammina e basta");
  });
});

describe("Il compagno che chiama (giro guidato)", () => {
  it("fermo per metà del giro, poi due salti (18 e 7 punti), mai sotto terra; si ripete uguale", () => {
    const at = (p: number) => callPose(p * CALL_CYCLE);
    assert.deepEqual(at(0), { lift: 0, scaleX: 1, scaleY: 1 });
    assert.deepEqual(at(0.3), { lift: 0, scaleX: 1, scaleY: 1 });
    let top = 0, second = 0;
    for (let i = 0; i <= 1000; i++) {
      const pose = at(i / 1000);
      assert.ok(pose.lift >= 0 && pose.scaleX > 0.9 && pose.scaleX < 1.1 && pose.scaleY > 0.88 && pose.scaleY < 1.1, `posa strana a ${i / 1000}`);
      if (i / 1000 < 0.8) top = Math.max(top, pose.lift); else second = Math.max(second, pose.lift);
    }
    assert.ok(Math.abs(top - 18) < 0.1 && Math.abs(second - 7) < 0.1, `${top} ${second}`);
    assert.deepEqual(callPose(CALL_CYCLE * 3 + 0.4), callPose(0.4));
  });

  it("si muove con dolcezza: niente scatti da un istante all'altro", () => {
    for (let i = 0; i < 1800; i++) {
      const a = callPose(i / 1000), b = callPose((i + 1) / 1000);
      assert.ok(Math.abs(a.lift - b.lift) < 0.5 && Math.abs(a.scaleX - b.scaleX) < 0.02 && Math.abs(a.scaleY - b.scaleY) < 0.02, `scatto a ${i} ms`);
    }
  });
});
