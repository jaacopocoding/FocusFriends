// Il contratto al contrario: i file SCRITTI dalla versione per Windows li deve leggere la versione per Mac (Swift) e ricavarne
// gli stessi risultati. Chi usa tutte e due le app sugli stessi dati (una cartella condivisa, un backup copiato da un
// computer all'altro) non deve trovare differenze.
//
// Serve il compilatore Swift (`swiftc`, quindi solo su un Mac): senza, le prove si saltano. La prima volta si compila il
// generatore degli attesi (lo stesso di tests/genera-attesi.sh), poi si riusa quello in build/fixtures/.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { SessionLog } from "../src/core/log.ts";
import { Profile } from "../src/core/profile.ts";
import { ToDoList } from "../src/core/todoList.ts";
import { derive, NOW, ZONE } from "./atteso.ts";
import { date } from "./util.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const fixtures = join(root, "tests", "fixtures");
const generator = join(root, "build", "fixtures", "genera-attesi");
// I sorgenti Swift sono quelli di tests/genera-attesi.sh (una sola lista: se se ne dimentica uno qui, la CI sul Mac lo scopre solo a generatore da rifare).
const swiftSources = [...readFileSync(join(root, "tests", "genera-attesi.sh"), "utf8").matchAll(/Sources\/FocusFriends\/(\w+)\.swift/g)]
  .map((match) => join(root, "Sources", "FocusFriends", `${match[1]}.swift`));
const swiftMain = join(root, "tests", "genera-attesi", "main.swift");

const hasSwift = process.platform === "darwin" && spawnSync("swiftc", ["--version"], { stdio: "ignore" }).status === 0;

function generatorIsFresh(): boolean {
  if (!existsSync(generator)) return false;
  const built = statSync(generator).mtimeMs;
  return [...swiftSources, swiftMain].every((file) => statSync(file).mtimeMs <= built);
}

function buildGenerator(): void {
  mkdirSync(dirname(generator), { recursive: true });
  const result = spawnSync("swiftc", ["-O", "-o", generator, ...swiftSources, swiftMain], { encoding: "utf8" });
  assert.equal(result.status, 0, `swiftc: ${result.stderr}`);
}

/** Le cartelle dei dati come le lascia l'app per Windows, ognuna dopo qualcosa che si fa davvero. */
function writeScenarios(into: string): string[] {
  const names: string[] = [];
  const make = (name: string): string => {
    const directory = join(into, name);
    mkdirSync(directory, { recursive: true });
    names.push(name);
    return directory;
  };
  let clock = date(2026, 10, 14, 19, 0);

  // 1. Un file di una versione vecchia che l'app per Windows ha letto e riscritto, più sessioni nuove, un voto, una modifica,
  //    una materia rinominata e una sessione tolta: tutto con testi che mettono alla prova la codifica.
  {
    const directory = make("ritorno-registro");
    cpSync(join(fixtures, "v2-voti"), directory, { recursive: true });
    const log = new SessionLog(directory, { now: () => clock, zone: ZONE });
    const first = log.add({ start: date(2026, 10, 14, 9, 0), seconds: 3000, plannedMinutes: 50, completed: true, subject: "Anatomia",
      pet: "pianty", notes: ["chiedere al prof", "\"nervi\" cranici \\ ripasso: è così", "📚 emoji e tab\tdentro"] });
    log.add({ start: date(2026, 10, 14, 11, 0), seconds: 720, plannedMinutes: 25, completed: false, subject: "anatomia", pet: "ciccio" });
    const second = log.add({ start: date(2026, 10, 14, 14, 30), seconds: 1500, plannedMinutes: 25, completed: true,
      subject: "Fisiologia – è già l'una", pet: "porcellino" });
    log.add({ start: date(2026, 10, 14, 16, 0), seconds: 1800, plannedMinutes: 30, completed: true });
    const gone = log.add({ start: date(2026, 10, 14, 17, 0), seconds: 600, plannedMinutes: 10, completed: true, subject: "Da togliere" });
    if (first) log.setReflection(first.id, "good", "capito il circolo di Willis");
    if (second) log.setReflection(second.id, "soso", "=SOMMA(A1:A9) e più \"virgolette\"");
    if (gone) log.remove(gone.id);
    log.renameSubject("Fisica", "Fisica 1");
    clock += 60_000;
  }

  // 2. Un focus in corso, con una pausa già fatta, note e il segno «ancora vivo» venti minuti dopo l'inizio.
  {
    const directory = make("ritorno-in-corso");
    const start = date(2026, 10, 14, 18, 0);
    const log = new SessionLog(directory, { now: () => start, zone: ZONE });
    log.beginInProgress({ start, plannedMinutes: 50, subject: "Chimica organica", pet: "gattino", notes: ["alcani", "alcheni — è tardi"] });
    log.updateInProgressPause(180, null);
    log.heartbeat(start + 20 * 60_000);
  }

  // 3. Un focus in corso, fermo da due minuti nel momento in cui l'app si è chiusa.
  {
    const directory = make("ritorno-in-corso-fermo");
    const start = date(2026, 10, 14, 17, 30);
    const log = new SessionLog(directory, { now: () => start, zone: ZONE });
    log.beginInProgress({ start, plannedMinutes: 30, subject: "Storia" });
    log.updateInProgressPause(60, start + 10 * 60_000);
    log.heartbeat(start + 12 * 60_000);
  }

  // 4. Il profilo: un nome lungo con accenti ed emoji (si accorcia), la scelta del primo compagno e gli sblocchi; con le sessioni di un'altra serie.
  {
    const directory = make("ritorno-profilo");
    cpSync(join(fixtures, "v3-completo"), directory, { recursive: true });
    const profile = new Profile(directory, { now: () => clock });
    profile.setName("  Giulia   Èmilia 🌿 Maria Beatrice Tuttolunga  ");
    profile.markIntroSeen();
    profile.chooseFirstCompanion("ciccio");
    profile.unlock(["gattino"]);
  }

  // 5. Le cose da fare: voci con e senza scadenza e materia, testi con accenti, virgolette, emoji e caratteri di controllo,
  //    una fatta, una tolta, una con una data che non esiste (si toglie), una fatta da più di 7 giorni (alla lettura sparisce).
  {
    const directory = make("ritorno-dafare");
    let now = date(2026, 10, 2, 9, 0);
    const list = new ToDoList(directory, { now: () => now });
    const old = list.add("Voce fatta tanto tempo fa");
    if (old.kind === "added") list.toggleDone(old.item.id);
    now = date(2026, 10, 12, 8, 30);
    list.add("Consegnare il modulo", "2026-10-13");
    list.add("  Riassunto   del capitolo 7 ", "2026-10-14", " Anatomia ");
    now += 60_000;
    list.add("Prenotare l'esame «orale» \"di giugno\"", "2026-10-14", "Fisiologia – è già l'una");
    list.add("Esercizi 4–6 📚\tcon\u0007 tab", "2026-10-15", "Analisi");
    list.add("Data sbagliata", "2026-02-30");
    list.add("Senza data né materia");
    const gone = list.add("Da togliere", "2026-10-20");
    if (gone.kind === "added") list.remove(gone.item.id);
    // Una voce corretta dopo averla scritta: nuovo testo (con accenti), un'altra scadenza, un'altra materia.
    const fixed = list.add("Esercizi 1–3", "2026-10-16", "Analisi");
    if (fixed.kind === "added") list.update(fixed.item.id, "Esercizi 4–6 (è già l'una)", "2026-10-21", "Analisi due");
    now = date(2026, 10, 13, 18, 0);
    const done = list.add("Mandare la mail al prof", null, "Chimica");
    if (done.kind === "added") list.toggleDone(done.item.id);
  }

  return names;
}

describe("contratto al contrario: Windows scrive, il Mac legge", { skip: !hasSwift ? "serve swiftc (solo su un Mac)" : false }, () => {
  it("le cartelle scritte dal codice per Windows danno al Mac gli stessi risultati", { timeout: 600_000 }, () => {
    if (!generatorIsFresh()) buildGenerator();
    const work = mkdtempSync(join(tmpdir(), "ff-ritorno-"));
    try {
      const scenarios = join(work, "cartelle");
      const names = writeScenarios(scenarios);
      const output = join(work, "attesi");
      const run = spawnSync(generator, [scenarios, output], { encoding: "utf8" });
      assert.equal(run.status, 0, `generatore Swift: ${run.stderr}`);
      assert.deepEqual(names.length, 5);
      for (const name of names) {
        const swift = JSON.parse(readFileSync(join(output, `${name}.json`), "utf8")) as Record<string, unknown>;
        delete swift["giardino"];
        const windows = JSON.parse(JSON.stringify(derive(scenarios, name))) as Record<string, unknown>;
        assert.deepEqual(windows, swift, name);
      }
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });
});

export { NOW };
