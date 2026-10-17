// I dati dei compagni (data/pets.json, generato da Pet.swift) e le regole che ne ricavano gli stadi.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PETS, PET_IDS, finalStage, focusGrowthStage, growsWithTimer, iconImage, restImageIndex, restStage, stageCount, stageForProgress } from "../src/core/pets.ts";

const assets = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "assets");

describe("Compagni", () => {
  it("i quattro, nell'ordine dei personaggi", () => {
    assert.deepEqual(PET_IDS, ["pianty", "porcellino", "ciccio", "gattino"]);
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
