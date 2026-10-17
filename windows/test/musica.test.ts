// La musica del focus (core/music.ts): le stesse prove della versione per Mac.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { hasTracks, isAudio, shuffled, titleOf, tracksIn } from "../src/core/music.ts";
import { tempDirectory } from "./util.ts";

function sequence(seed: number): () => number {
  let state = seed >>> 0;
  return () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 2 ** 32; };
}

describe("Musica", () => {
  it("quali file sono audio", () => {
    assert.ok(isAudio("/m/brano.MP3") && isAudio("/m/a.flac"));
    assert.ok(!isAudio("/m/nota.txt") && !isAudio("/m/.nascosto.mp3"));
  });

  it("i brani trovati: prima quelli della cartella (ordine naturale), poi le sottocartelle", () => {
    const dir = tempDirectory();
    for (const name of ["10 b.mp3", "2 a.m4a", "copertina.jpg", ".DS_Store", "Sub/3 c.wav", ".nascosta/4 d.mp3"]) {
      const path = join(dir, name);
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, "\0");
    }
    assert.deepEqual(tracksIn(dir).map((p) => basename(p)), ["2 a.m4a", "10 b.mp3", "3 c.wav"]);
    assert.deepEqual(tracksIn(tempDirectory()), [], "cartella vuota: nessun brano");
    assert.deepEqual(tracksIn(join(dir, "non-esiste")), []);
    assert.ok(hasTracks(dir) && !hasTracks(tempDirectory()));
    const covers = tempDirectory();
    writeFileSync(join(covers, "copertina.jpg"), "\0");
    assert.ok(!hasTracks(covers), "una cartella senza audio non conta");
  });

  it("l'ordine casuale non comincia dal brano appena suonato", () => {
    const three = ["/a.mp3", "/b.mp3", "/c.mp3"];
    for (let seed = 1; seed <= 100; seed += 1) {
      for (const last of three) {
        const order = shuffled(three, last, sequence(seed));
        assert.ok(order.length === 3 && new Set(order).size === 3 && order[0] !== last);
      }
    }
    assert.deepEqual(shuffled(["/a.mp3"], "/a.mp3"), ["/a.mp3"], "con un solo brano suona quello");
    assert.deepEqual(shuffled([], null), []);
  });

  it("il titolo leggibile", () => {
    assert.equal(titleOf("/m/music_01_dreamy_night-owl.m4a"), "dreamy night owl");
    assert.equal(titleOf("/m/2. Rain Walk.mp3"), "Rain Walk");
  });
});
