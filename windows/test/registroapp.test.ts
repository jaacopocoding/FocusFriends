// Il registro dell'app (core/diagnostics.ts).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { AppLog, MAX_MESSAGE } from "../src/core/diagnostics.ts";
import { tempDirectory } from "./util.ts";

describe("Registro dell'app", () => {
  it("una riga per fatto, con l'ora e il livello", () => {
    const dir = tempDirectory();
    const log = new AppLog({ directory: dir, now: () => Date.UTC(2026, 9, 17, 10, 0, 0) });
    log.info("avvio 0.9.0");
    log.warn("processo della GPU caduto");
    assert.deepEqual(readFileSync(log.file, "utf8").trim().split("\n"), [
      "2026-10-17T10:00:00.000Z INFO avvio 0.9.0", "2026-10-17T10:00:00.000Z WARN processo della GPU caduto",
    ]);
  });

  it("toglie il percorso della cartella dell'utente, con una barra o con l'altra", () => {
    const log = new AppLog({ directory: tempDirectory(), home: "C:\\Users\\Marco" });
    assert.equal(log.sanitize("errore in C:\\Users\\Marco\\AppData\\x.js"), "errore in ~\\AppData\\x.js");
    assert.equal(log.sanitize("errore in c:/users/marco/AppData/x.js"), "errore in ~/AppData/x.js");
    const posix = new AppLog({ directory: tempDirectory(), home: "/Users/marco" });
    assert.equal(posix.sanitize("at /Users/marco/Documents/app.js:3"), "at ~/Documents/app.js:3");
    assert.equal(new AppLog({ directory: tempDirectory() }).sanitize("niente da togliere"), "niente da togliere");
  });

  it("un errore porta il suo nome e il suo percorso (senza l'utente)", () => {
    const dir = tempDirectory();
    const log = new AppLog({ directory: dir, home: process.env["HOME"] ?? "/Users/prova" });
    const error = new Error("non si legge");
    error.stack = `Error: non si legge\n    at f (${process.env["HOME"] ?? "/Users/prova"}/x.js:1:1)`;
    log.error("eccezione non gestita", error);
    const text = readFileSync(log.file, "utf8");
    assert.match(text, /ERROR eccezione non gestita: Error: non si legge/);
    assert.ok(!text.includes(process.env["HOME"] ?? "/Users/prova") && text.includes("~/x.js"));
  });

  it("i messaggi lunghissimi si accorciano", () => {
    const log = new AppLog({ directory: tempDirectory() });
    assert.equal(log.sanitize("x".repeat(10_000)).length, MAX_MESSAGE + 1);
  });

  it("oltre la dimensione massima il file passa al «.1» e se ne comincia uno nuovo", () => {
    const dir = tempDirectory();
    const log = new AppLog({ directory: dir, maxBytes: 300 });
    for (let i = 0; i < 30; i += 1) log.info(`riga numero ${i}`);
    assert.ok(existsSync(join(dir, "registro-app.1.log")));
    assert.ok(statSync(log.file).size <= 300 + 60);
    const all = readFileSync(join(dir, "registro-app.1.log"), "utf8") + readFileSync(log.file, "utf8");
    assert.ok(all.includes("riga numero 29"));
  });

  it("non fa mai cadere niente, nemmeno se non si può scrivere", () => {
    const dir = tempDirectory();
    const blocked = join(dir, "occupato");
    writeFileSync(blocked, "x");
    const log = new AppLog({ directory: join(blocked, "dentro") });
    assert.doesNotThrow(() => { log.info("a"); log.error("b", new Error("c")); });
  });
});
