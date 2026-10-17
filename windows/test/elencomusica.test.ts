// L'elenco dei brani che il processo principale dà alla pagina (main/music.ts).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createMusicService } from "../src/main/music.ts";
import { tempDirectory } from "./util.ts";

const assets = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "assets");

describe("Elenco dei brani", () => {
  it("quelli inclusi: i cinque dell'app, in ordine di nome, con un titolo leggibile", () => {
    const service = createMusicService({ assets, folder: () => null });
    const list = service.list("bundled");
    assert.deepEqual(list.tracks.map((t) => t.title), ["boredom", "love", "night driving", "old age", "opinions"]);
    assert.deepEqual(list.tracks.map((t) => t.id), [0, 1, 2, 3, 4]);
    assert.ok(service.file(list.version, 3)?.endsWith("old-age.m4a"));
  });

  it("un elenco nuovo invalida i numeri di quello vecchio", () => {
    const service = createMusicService({ assets, folder: () => null });
    const first = service.list("bundled");
    const second = service.list("bundled");
    assert.ok(second.version > first.version);
    assert.equal(service.file(first.version, 0), null);
    assert.ok(service.file(second.version, 0) !== null);
    assert.equal(service.file(second.version, 99), null);
  });

  it("la cartella dell'utente: anche nelle sottocartelle, senza i file che non sono audio", () => {
    const dir = tempDirectory();
    mkdirSync(join(dir, "sotto"), { recursive: true });
    for (const name of ["a.mp3", "sotto/b.flac", "nota.txt"]) writeFileSync(join(dir, name), "\0");
    const service = createMusicService({ assets, folder: () => dir });
    assert.deepEqual(service.list("folder").tracks.map((t) => t.title), ["a", "b"]);
    assert.ok(service.folderHasTracks());
    writeFileSync(join(dir, "nuovo.wav"), "\0");
    assert.equal(service.list("folder").tracks.length, 3, "la cartella è cambiata: l'elenco si rifà");
  });

  it("senza sorgente, senza cartella o con una cartella che non c'è: nessun brano", () => {
    const none = createMusicService({ assets, folder: () => null });
    assert.deepEqual(none.list("off").tracks, []);
    assert.deepEqual(none.list("folder").tracks, []);
    assert.equal(none.folderHasTracks(), false);
    const missing = createMusicService({ assets, folder: () => join(tempDirectory(), "non-esiste") });
    assert.deepEqual(missing.list("folder").tracks, []);
    assert.equal(missing.folderHasTracks(), false);
  });
});
