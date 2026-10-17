// Le prove del registro (windows/src/core/log.ts): le stesse della versione per Mac (tests/main.swift).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { chmodSync, existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { SessionLog, BACKUPS_TO_KEEP, FORMAT_VERSION } from "../src/core/log.ts";
import { csv } from "../src/core/csv.ts";
import { date, tempDirectory, ZONE } from "./util.ts";

const json = (path: string): any => JSON.parse(readFileSync(path, "utf8"));
const write = (dir: string, name: string, text: string): void => writeFileSync(join(dir, name), text, "utf8");
const input = (start: number, seconds: number, plannedMinutes: number, completed: boolean, subject: string | null = null, extra: object = {}) =>
  ({ start, seconds, plannedMinutes, completed, subject, ...extra });

describe("Registro", () => {
  it("aggiunge, riordina, ricorda le materie e si rilegge", () => {
    const dir = tempDirectory();
    const log = new SessionLog(dir, { zone: ZONE });
    assert.equal(log.add(input(date(2026, 10, 12, 9), 59, 30, false, "X")), null, "sotto il minuto non conta");
    assert.equal(log.sessions.length, 0);
    const a = log.add(input(date(2026, 10, 12, 15), 3000, 50, true, "Anatomia"));
    log.add(input(date(2026, 10, 12, 9), 1800, 30, true, "Fisiologia"));
    const c = log.add(input(date(2026, 10, 13, 10), 600, 25, false, null));
    log.add(input(date(2026, 10, 14, 10), 1500, 25, true, " anatomia "));
    assert.equal(log.sessions.length, 4);
    const starts = log.sessions.map((s) => s.start);
    assert.deepEqual(starts, [...starts].sort((x, y) => x - y), "in ordine di tempo");
    assert.deepEqual(log.recentSubjects(), ["Anatomia", "Fisiologia"]);
    assert.equal(log.recentSubjects(1).length, 1);

    const reopened = new SessionLog(dir, { zone: ZONE });
    assert.deepEqual(reopened.sessions, log.sessions, "riletto dal file uguale");
    reopened.setSubject(a!.id, "  Biochimica ");
    assert.equal(reopened.sessions.find((s) => s.id === a!.id)?.subject, "Biochimica");
    reopened.remove(c!.id);
    assert.equal(reopened.sessions.length, 3);
  });

  it("un file rovinato si mette da parte", () => {
    const dir = tempDirectory();
    write(dir, "sessioni.json", "questo non è json");
    const bad = new SessionLog(dir);
    assert.equal(bad.sessions.length, 0);
    const files = readdirSync(dir);
    assert.ok(files.some((f) => f.startsWith("sessioni.corrotto-")));
    assert.ok(!files.includes("sessioni.json"));
  });
});

describe("Focus in corso (app chiusa di colpo)", () => {
  it("si recupera una volta sola, come interrotto", () => {
    const dir = tempDirectory();
    const log = new SessionLog(dir);
    assert.equal(log.recoverInterrupted(), null);
    log.beginInProgress({ start: Date.now() - 20 * 60_000, plannedMinutes: 50, subject: "Chimica" });
    const again = new SessionLog(dir);
    const recovered = again.recoverInterrupted();
    assert.ok(recovered);
    assert.equal(recovered.completed, false);
    assert.equal(recovered.subject, "Chimica");
    assert.ok(recovered.seconds <= 50 * 60);
    assert.ok(Math.abs(recovered.seconds - 20 * 60) <= 2, `circa venti minuti (${recovered.seconds} s)`);
    assert.equal(again.recoverInterrupted(), null, "una volta sola");
    log.beginInProgress({ start: Date.now() - 600_000, plannedMinutes: 25 });
    log.finishInProgress();
    assert.equal(new SessionLog(dir).recoverInterrupted(), null, "chi finisce bene non lascia tracce");
  });

  it("il personaggio sopravvive al recupero", () => {
    const dir = tempDirectory();
    new SessionLog(dir).beginInProgress({ start: Date.now() - 300_000, plannedMinutes: 25, pet: "porcellino" });
    assert.equal(new SessionLog(dir).recoverInterrupted()?.pet, "porcellino");
  });

  it("le note del focus in corso si recuperano", () => {
    const dir = tempDirectory();
    const log = new SessionLog(dir, { now: () => date(2026, 10, 14, 9, 20), zone: ZONE });
    log.beginInProgress({ start: date(2026, 10, 14, 9), plannedMinutes: 50, subject: "Segnali", pet: "ciccio" });
    log.updateInProgressNotes(["chiedere al prof"]);
    const recovered = new SessionLog(dir, { now: () => date(2026, 10, 14, 9, 30), zone: ZONE }).recoverInterrupted();
    assert.deepEqual(recovered?.notes, ["chiedere al prof"]);
  });
});

describe("Recupero con il timer fermo", () => {
  const nine = date(2026, 10, 14, 9);
  const seconds = (dir: string): number | undefined => new SessionLog(dir, { zone: ZONE }).recoverInterrupted()?.seconds;

  it("fermo quando si chiude: 10 minuti di studio", () => {
    const dir = tempDirectory();
    const log = new SessionLog(dir, { now: () => date(2026, 10, 14, 9, 10), zone: ZONE });
    log.beginInProgress({ start: nine, plannedMinutes: 50, subject: "Segnali" });
    log.updateInProgressPause(0, date(2026, 10, 14, 9, 10));
    log.heartbeat(date(2026, 10, 14, 9, 25));
    assert.equal(seconds(dir), 600);
  });

  it("ripartito: 20 minuti di studio", () => {
    const dir = tempDirectory();
    const log = new SessionLog(dir, { now: () => date(2026, 10, 14, 9, 20), zone: ZONE });
    log.beginInProgress({ start: nine, plannedMinutes: 50, subject: "Segnali" });
    log.updateInProgressPause(0, date(2026, 10, 14, 9, 10));
    log.updateInProgressPause(600, null);
    log.heartbeat(date(2026, 10, 14, 9, 30));
    assert.equal(seconds(dir), 1200);
  });

  it("dopo «+5 minuti» il tempo fermo non si perde, e un focus nuovo parte da zero", () => {
    const dir = tempDirectory();
    const log = new SessionLog(dir, { now: () => date(2026, 10, 14, 9, 20), zone: ZONE });
    log.beginInProgress({ start: nine, plannedMinutes: 50, subject: "Segnali" });
    log.updateInProgressPause(600, null);
    log.beginInProgress({ start: nine + 430, plannedMinutes: 55, subject: "Segnali" });
    log.heartbeat(date(2026, 10, 14, 9, 30));
    assert.equal(seconds(dir), 1200);
    log.beginInProgress({ start: date(2026, 10, 14, 10), plannedMinutes: 25, subject: "Altro" });
    log.heartbeat(date(2026, 10, 14, 10, 20));
    assert.equal(seconds(dir), 1200);
  });

  it("un file «in corso» di prima si recupera come sempre", () => {
    const dir = tempDirectory();
    write(dir, "in-corso.json", '{"start": "2026-10-14T07:00:00Z", "plannedMinutes": 50, "subject": "Segnali", "lastSeen": "2026-10-14T07:20:00Z"}');
    assert.equal(seconds(dir), 1200);
  });
});

describe("Formato versionato e migrazione", () => {
  it("il file ha la versione, la lista e l'ora locale", () => {
    const dir = tempDirectory();
    new SessionLog(dir, { zone: ZONE }).add(input(date(2026, 10, 14, 9, 30), 1800, 30, true, "Anatomia", { pet: "pianty" }));
    const raw = json(join(dir, "sessioni.json"));
    assert.equal(raw.version, FORMAT_VERSION);
    assert.equal(raw.sessions.length, 1);
    assert.equal(raw.sessions[0].localStart, "2026-10-14T09:30");
  });

  it("un file di prima del personaggio si legge", () => {
    const dir = tempDirectory();
    write(dir, "sessioni.json", `[{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000001", "plannedMinutes": 25,
      "seconds": 1500, "start": "2026-10-12T08:00:00Z", "subject": "Anatomia"}]`);
    const log = new SessionLog(dir);
    assert.equal(log.sessions.length, 1);
    assert.equal(log.sessions[0]?.pet, undefined);
    assert.equal(log.sessions[0]?.subject, "Anatomia");
  });

  it("il vecchio formato (solo la lista) si migra, con la copia intatta", () => {
    const dir = tempDirectory();
    write(dir, "sessioni.json", `[{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000001", "plannedMinutes": 25, "seconds": 1500,
      "start": "2026-10-12T08:00:00Z", "subject": "anatomia"},
     {"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000002", "plannedMinutes": 25, "seconds": 1500,
      "start": "2026-10-13T08:00:00Z", "subject": "Anatomia"},
     {"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000003", "plannedMinutes": 25, "seconds": 1500,
      "start": "2026-10-14T08:00:00Z", "subject": "FISIOLOGIA"}]`);
    const log = new SessionLog(dir, { zone: ZONE });
    assert.equal(log.sessions.length, 3, "nessuna sessione persa");
    assert.ok(log.sessions.every((s) => s.localStart !== undefined), "ora locale aggiunta");
    assert.equal(log.sessions[0]?.subject, "Anatomia");
    assert.equal(log.sessions[1]?.subject, "Anatomia");
    assert.equal(json(join(dir, "sessioni.json")).version, FORMAT_VERSION, "riscritto nel formato nuovo");
    assert.ok(existsSync(join(dir, "backup", "sessioni-formato0.json")), "copia intatta del vecchio file");
  });

  it("un file di una versione più nuova si legge e non si riscrive", () => {
    const dir = tempDirectory();
    const newer = `{"version": 99, "sessions": [{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000009", "plannedMinutes": 25,
     "seconds": 1500, "start": "2026-10-12T08:00:00Z", "subject": "Futuro", "campoNuovo": 1}]}`;
    write(dir, "sessioni.json", newer);
    const log = new SessionLog(dir, { zone: ZONE });
    assert.equal(log.sessions.length, 1);
    assert.ok(log.isReadOnly);
    assert.equal(log.add(input(date(2026, 10, 14, 9), 600, 10, true)), null, "e non si scrive");
    assert.equal(readFileSync(join(dir, "sessioni.json"), "utf8"), newer, "il file è rimasto identico");
  });

  it("il formato 1 (senza voto né nota) si migra con la copia intatta", () => {
    const dir = tempDirectory();
    const v1 = `{"version": 1, "sessions": [{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000010", "plannedMinutes": 25,
     "seconds": 1500, "start": "2026-10-12T08:00:00Z", "subject": "Anatomia", "localStart": "2026-10-12T10:00"}]}`;
    write(dir, "sessioni.json", v1);
    const log = new SessionLog(dir, { zone: ZONE });
    assert.ok(log.sessions.length === 1 && log.sessions[0]?.rating === undefined && !log.isReadOnly);
    assert.equal(json(join(dir, "sessioni.json")).version, FORMAT_VERSION);
    assert.equal(readFileSync(join(dir, "backup", "sessioni-formato1.json"), "utf8"), v1);
  });

  it("il formato 2 (senza note) si migra con la copia intatta", () => {
    const dir = tempDirectory();
    const v2 = `{"version": 2, "sessions": [{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000020", "plannedMinutes": 25,
     "seconds": 1500, "start": "2026-10-12T08:00:00Z", "subject": "Anatomia", "rating": "good", "note": "nervi"}]}`;
    write(dir, "sessioni.json", v2);
    const log = new SessionLog(dir, { zone: ZONE });
    assert.ok(log.sessions.length === 1 && log.sessions[0]?.notes === undefined && log.sessions[0]?.rating === "good");
    assert.equal(readFileSync(join(dir, "backup", "sessioni-formato2.json"), "utf8"), v2);
  });

  it("un voto sconosciuto non rende illeggibile il file", () => {
    const dir = tempDirectory();
    write(dir, "sessioni.json", `{"version": 2, "sessions": [{"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000011", "plannedMinutes": 25,
     "seconds": 1500, "start": "2026-10-12T08:00:00Z", "rating": "ottimo", "note": "ok"}]}`);
    const log = new SessionLog(dir, { zone: ZONE });
    assert.ok(log.sessions.length === 1 && log.sessions[0]?.rating === undefined && log.sessions[0]?.note === "ok");
  });
});

describe("Materie unite", () => {
  it("una nuova scrittura prende quella già usata; rinomina e unione", () => {
    const dir = tempDirectory();
    const log = new SessionLog(dir, { zone: ZONE });
    const add = (day: number, hour: number, subject: string | null) => log.add(input(date(2026, 10, day, hour), 1800, 30, true, subject));
    const s1 = add(12, 9, "Anatomia"), s2 = add(13, 9, "anatomia"), s3 = add(14, 9, "ANATOMIA ");
    assert.deepEqual([s1?.subject, s2?.subject, s3?.subject], ["Anatomia", "Anatomia", "Anatomia"]);
    add(14, 11, "Fisica");
    assert.equal(add(14, 13, "fisíca")?.subject, "Fisica", "senza distinguere gli accenti");
    assert.equal(log.renameSubject("fisica", "Fisica generale"), 2);
    assert.equal(log.sessions.filter((s) => s.subject === "Fisica generale").length, 2);
    assert.ok(add(15, 9, "Chimica"));
    assert.equal(log.renameSubject("Chimica", "anatomia"), 1);
    assert.equal(log.sessions.at(-1)?.subject, "Anatomia", "l'unione usa la scrittura che c'è già");
    assert.equal(log.renameSubject("Anatomia", null), 4);
    assert.ok(log.sessions.every((s) => s.subject !== "Anatomia"), "rinominare in vuoto toglie la materia");
  });
});

describe("Copie di sicurezza e cancellazione", () => {
  it("tiene le ultime sette, una al giorno, e cancella tutto", () => {
    const dir = tempDirectory();
    let fakeNow = date(2026, 10, 1, 12);
    const log = new SessionLog(dir, { now: () => fakeNow, zone: ZONE });
    for (let day = 1; day <= 10; day += 1) {
      fakeNow = date(2026, 10, day, 12);
      log.add(input(fakeNow, 600, 10, true, `G${day}`));
    }
    const backups = readdirSync(join(dir, "backup")).sort();
    assert.equal(backups.length, BACKUPS_TO_KEEP);
    assert.equal(backups[0], "sessioni-2026-10-04.json");
    assert.equal(backups.at(-1), "sessioni-2026-10-10.json");
    assert.equal(json(join(dir, "backup", "sessioni-2026-10-10.json")).sessions.length, 9, "la copia del giorno è lo stato di prima");
    fakeNow = date(2026, 10, 10, 18);
    log.add(input(fakeNow, 600, 10, true, "G10b"));
    assert.equal(readdirSync(join(dir, "backup")).length, BACKUPS_TO_KEEP, "una sola copia al giorno");

    let notified = 0;
    log.addObserver(() => { notified += 1; });
    log.beginInProgress({ start: Date.now(), plannedMinutes: 10 });
    log.deleteAll();
    assert.ok(log.sessions.length === 0 && notified === 1);
    assert.deepEqual(readdirSync(dir), [], "nessun file rimasto");
    assert.equal(new SessionLog(dir, { zone: ZONE }).sessions.length, 0);
  });
});

describe("Com'è andata e cosa hai fatto", () => {
  it("voto e nota si salvano, si rileggono e si tolgono", () => {
    const dir = tempDirectory();
    const log = new SessionLog(dir, { zone: ZONE });
    const made = log.add(input(date(2026, 10, 14, 9), 1500, 25, true, "Anatomia"))!;
    assert.ok(made.rating === undefined && made.note === undefined);
    assert.equal(log.lastNote(), null);
    log.setReflection(made.id, "poor", "  nervi   cranici ");
    const saved = new SessionLog(dir, { zone: ZONE }).sessions[0];
    assert.ok(saved?.rating === "poor" && saved.note === "nervi cranici");
    assert.deepEqual(log.lastNote(), { subject: "Anatomia", note: "nervi cranici" });
    log.setReflection(made.id, null, "");
    assert.ok(log.sessions[0]?.rating === undefined && log.sessions[0]?.note === undefined);
    assert.equal("rating" in json(join(dir, "sessioni.json")).sessions[0], false, "senza voto il campo non c'è nel file");
  });
});

describe("Note del focus", () => {
  it("si salvano pulite, si rileggono, si tolgono", () => {
    const dir = tempDirectory();
    const log = new SessionLog(dir, { zone: ZONE });
    const made = log.add(input(date(2026, 10, 14, 9), 1800, 30, true, "Segnali", { notes: ["rivedere la trasformata", "  ", "esercizio 4"] }))!;
    assert.deepEqual(made.notes, ["rivedere la trasformata", "esercizio 4"]);
    assert.deepEqual(new SessionLog(dir, { zone: ZONE }).sessions[0]?.notes, ["rivedere la trasformata", "esercizio 4"]);
    log.setNotes(made.id, []);
    assert.equal(log.sessions[0]?.notes, undefined);
  });
  it("nel CSV, separate da |", () => {
    const text = csv([{ id: "x", start: date(2026, 10, 14, 9), seconds: 600, plannedMinutes: 10, completed: true, subject: "X", notes: ["uno", "due"] }]);
    assert.ok(text.includes('"uno | due"'));
  });
});

describe("Personaggio", () => {
  it("si salva e si rilegge", () => {
    const dir = tempDirectory();
    const made = new SessionLog(dir).add(input(date(2026, 10, 14, 9), 1800, 30, true, "Anatomia", { pet: "ciccio" }));
    assert.equal(made?.pet, "ciccio");
    assert.equal(new SessionLog(dir).sessions[0]?.pet, "ciccio");
  });
});

describe("Dati danneggiati", () => {
  it("una sola sessione rovinata: le altre restano, il file com'era resta come copia", () => {
    const dir = tempDirectory();
    write(dir, "sessioni.json", `{"version": 3, "sessions": [
     {"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000031", "plannedMinutes": 25, "seconds": 1500, "start": "2026-10-12T08:00:00Z", "subject": "Buona"},
     {"completed": true, "id": "9F6C1A2B-0000-4000-8000-000000000032", "plannedMinutes": 25, "start": "2026-10-12T09:00:00Z"},
     {"completed": false, "id": "9F6C1A2B-0000-4000-8000-000000000033", "plannedMinutes": 30, "seconds": 600, "start": "2026-10-13T08:00:00Z"}
    ]}`);
    const messages: string[] = [];
    const log = new SessionLog(dir, { zone: ZONE });
    log.onProblem = (message) => messages.push(message);
    assert.ok(log.sessions.length === 2 && !log.isReadOnly);
    assert.ok(messages.length === 1 && messages[0]!.includes("non erano leggibili"), "avvisato anche se ci si registra dopo");
    assert.ok(readdirSync(dir).some((f) => f.startsWith("sessioni.corrotto-")), "il file com'era resta come copia");
    assert.equal(new SessionLog(dir, { zone: ZONE }).sessions.length, 2, "il file riscritto ha le sessioni buone");
  });

  it("un file che c'è ma non si legge non si sovrascrive", { skip: process.platform === "win32" || process.getuid?.() === 0 }, () => {
    const dir = tempDirectory();
    const file = join(dir, "sessioni.json");
    writeFileSync(file, '{"version": 3, "sessions": []}');
    chmodSync(file, 0o000);
    const log = new SessionLog(dir, { zone: ZONE });
    assert.ok(log.isReadOnly);
    assert.equal(log.add(input(date(2026, 10, 14, 9), 600, 10, true)), null);
    chmodSync(file, 0o644);
    assert.equal(readFileSync(file, "utf8"), '{"version": 3, "sessions": []}');
  });

  it("versione più nuova: avvisato, e il focus interrotto non va perso", () => {
    const dir = tempDirectory();
    write(dir, "sessioni.json", '{"version": 99, "sessions": []}');
    new SessionLog(dir, { now: () => date(2026, 10, 14, 9, 20), zone: ZONE })
      .beginInProgress({ start: date(2026, 10, 14, 9), plannedMinutes: 50, subject: "Segnali" });
    const messages: string[] = [];
    const reader = new SessionLog(dir, { now: () => date(2026, 10, 14, 9, 30), zone: ZONE });
    reader.onProblem = (message) => messages.push(message);
    assert.ok(reader.isReadOnly && messages.length === 1 && messages[0]!.includes("più nuova"));
    assert.equal(reader.recoverInterrupted(), null, "in sola lettura il focus interrotto non si può salvare");
    assert.ok(readFileSync(join(dir, "in-corso.json")).length > 0, "ma il segno «in corso» resta");
  });

  it("una scrittura che non riesce non passa inosservata", () => {
    const blocker = join(tempDirectory(), "occupato");
    writeFileSync(blocker, "x");       // la cartella dei dati è un file: non si può creare
    const log = new SessionLog(blocker, { zone: ZONE });
    const messages: string[] = [];
    log.onProblem = (message) => messages.push(message);
    const first = log.add(input(date(2026, 10, 14, 9), 600, 10, true, "X"));
    log.add(input(date(2026, 10, 14, 10), 600, 10, true, "X"));
    assert.ok(first !== null && log.sessions.length === 2, "la sessione resta in memoria");
    assert.ok(log.hasUnsavedChanges, "e si sa che non è sul disco");
    assert.ok(messages.length === 1 && messages[0]!.includes("Non riesco a salvare"), `avvisato una volta sola (${messages.length})`);
    const progress: string[] = [];
    log.onProblem = (message) => progress.push(message);
    log.beginInProgress({ start: Date.now(), plannedMinutes: 25 });
    assert.ok(progress.length === 1 && progress[0]!.includes("focus in corso"));
    assert.equal(new SessionLog(tempDirectory(), { zone: ZONE }).hasUnsavedChanges, false);
  });
});

