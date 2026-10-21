import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  addDays, cleanToDoText, daysBetween, dueLabel, isValidDay, reminderMessage, sections, TODO_MAX_ITEMS, TODO_TEXT_MAX, todayOf,
} from "../src/core/todo.ts";
import type { ToDoItem } from "../src/core/todo.ts";
import { ToDoList } from "../src/core/todoList.ts";
import { date, tempDirectory, ZONE } from "./util.ts";

const TODAY = "2026-10-20";         // un martedì

describe("Da fare: giorni e testi", () => {
  it("i giorni che esistono e quelli no", () => {
    assert.ok(isValidDay("2026-10-23") && isValidDay("2028-02-29"));
    for (const day of ["2026-02-30", "2026-13-01", "2027-02-29", "0000-01-01", "26-10-23", "2026-1-3", "2026/10/23", "", "abcd-ef-gh"]) {
      assert.equal(isValidDay(day), false, day);
    }
  });
  it("distanze e somme di giorni, anche a cavallo d'anno e di febbraio", () => {
    assert.equal(daysBetween(TODAY, "2026-10-23"), 3);
    assert.equal(daysBetween(TODAY, "2026-10-19"), -1);
    assert.equal(daysBetween("2026-12-30", "2027-01-02"), 3);
    assert.equal(daysBetween("2028-02-28", "2028-03-01"), 2);
    assert.equal(daysBetween(TODAY, "boh"), null);
    assert.equal(addDays(TODAY, 7), "2026-10-27");
    assert.equal(addDays("2026-12-25", 12), "2027-01-06");
  });
  it("il giorno è quello sull'orologio, non in UTC", () => {
    assert.equal(todayOf(date(2026, 10, 20, 23, 30), ZONE), "2026-10-20");
    assert.equal(todayOf(date(2026, 10, 21, 0, 30), ZONE), "2026-10-21");
  });
  it("le etichette", () => {
    assert.equal(dueLabel("2026-10-19", TODAY), "ieri");
    assert.equal(dueLabel(TODAY, TODAY), "oggi");
    assert.equal(dueLabel("2026-10-21", TODAY), "domani");
    assert.equal(dueLabel("2026-10-23", TODAY), "ven 23");
    assert.equal(dueLabel("2026-10-26", TODAY), "lun 26");
    assert.equal(dueLabel("2026-10-27", TODAY), "27 ott");
    assert.equal(dueLabel("2026-10-18", TODAY), "18 ott");
    assert.equal(dueLabel("2027-01-05", TODAY), "5 gen 2027");
  });
  it("il testo si pulisce", () => {
    assert.equal(cleanToDoText("  comprare   il libro \t\n di anatomia "), "comprare il libro di anatomia");
    assert.equal(cleanToDoText("   "), null);
    assert.equal(cleanToDoText(null), null);
    assert.equal(Array.from(cleanToDoText("è".repeat(300)) ?? "").length, TODO_TEXT_MAX);
  });
});

describe("Da fare: la lista", () => {
  it("aggiungere, raggruppare, segnare, togliere, rileggere", () => {
    const directory = tempDirectory();
    let clock = date(2026, 10, 20, 9, 0);
    const list = new ToDoList(directory, { now: () => clock });
    assert.equal(list.items.length, 0);
    assert.equal(existsSync(join(directory, "dafare.json")), false, "all'inizio non scrive niente");
    assert.deepEqual(list.add("   "), { kind: "empty" });

    const first = list.add("  Esercizi di analisi  4–6 ", "2026-10-21", " Analisi ");
    assert.equal(first.kind, "added");
    const firstItem = first.kind === "added" ? first.item : null;
    assert.deepEqual([firstItem?.text, firstItem?.due, firstItem?.subject, firstItem?.doneAt], ["Esercizi di analisi 4–6", "2026-10-21", "Analisi", null]);
    const second = list.add("Cercare un libro per Storia", "2026-02-30", "   ");
    assert.ok(second.kind === "added" && second.item.due === null && second.item.subject === null, "data che non esiste e materia vuota: tolte");
    clock += 60_000; list.add("Consegnare il modulo", "2026-10-19");
    clock += 60_000; list.add("Riassunto del capitolo 7", TODAY, "Anatomia");
    clock += 60_000; list.add("Relazione di laboratorio", "2026-10-26", "Fisica");
    clock += 60_000; list.add("Prenotare l'esame", TODAY, "Fisiologia");
    assert.equal(list.openCount, 6);

    const groups = list.sections(TODAY);
    assert.deepEqual(groups.map((g) => g.group), ["overdue", "today", "upcoming", "noDate"]);
    assert.deepEqual(groups.map((g) => g.items.map((i) => i.text)), [
      ["Consegnare il modulo"], ["Riassunto del capitolo 7", "Prenotare l'esame"],
      ["Esercizi di analisi 4–6", "Relazione di laboratorio"], ["Cercare un libro per Storia"],
    ]);
    assert.deepEqual(list.sections("2026-10-25").map((g) => g.items.length), [4, 1, 1], "con un altro giorno cambia tutto");

    const reloaded = new ToDoList(directory, { now: () => clock });
    assert.deepEqual(reloaded.items, list.items.map((item) => ({ ...item, createdAt: Math.floor(item.createdAt / 1000) * 1000 })));
    const text = readFileSync(join(directory, "dafare.json"), "utf8");
    assert.ok(text.includes('"version" : 1') && text.includes('"due" : "2026-10-21"') && text.includes('"createdAt" : "2026-10-20T07:00:00Z"'));
    assert.ok(!text.includes('"doneAt"'), "senza «fatta» il campo non c'è");

    const id = firstItem!.id;
    list.toggleDone(id);
    assert.equal(list.openCount, 5);
    assert.deepEqual(list.doneItems.map((i) => i.id), [id]);
    assert.equal(new ToDoList(directory, { now: () => clock }).doneItems[0]?.doneAt, clock);
    list.toggleDone(id);
    assert.equal(list.doneItems.length, 0);
    list.remove(second.kind === "added" ? second.item.id : "");
    assert.equal(list.openCount, 5);
    list.remove("non-c-e");
    assert.equal(list.openCount, 5);

    // le voci fatte spariscono dopo una settimana
    list.toggleDone(id);
    clock += 6 * 86_400_000;
    assert.equal(new ToDoList(directory, { now: () => clock }).doneItems.length, 1);
    clock += 2 * 86_400_000;
    const purged = new ToDoList(directory, { now: () => clock });
    assert.equal(purged.doneItems.length, 0);
    assert.equal(purged.openCount, 4);
  });

  it("al massimo 200 voci", () => {
    const list = new ToDoList(tempDirectory());
    for (let i = 0; i < TODO_MAX_ITEMS; i += 1) list.add(`voce ${i}`);
    assert.deepEqual(list.add("una di troppo"), { kind: "full" });
  });

  it("file più nuovo: si legge e non si riscrive", () => {
    const directory = tempDirectory();
    const original = '{ "version": 9, "items": [ { "id": "00000000-0000-4000-8000-000000000001", "text": "dal futuro", "createdAt": "2026-10-14T07:00:00Z" } ] }';
    writeFileSync(join(directory, "dafare.json"), original);
    const problems: string[] = [];
    const list = new ToDoList(directory);
    list.onProblem = (message) => problems.push(message);
    list.add("non deve scrivere");
    assert.ok(list.isReadOnly && list.items.length === 2 && problems.length === 1);
    assert.equal(readFileSync(join(directory, "dafare.json"), "utf8"), original);
  });

  it("file rovinato: messo da parte, si riparte da vuoto", () => {
    const directory = tempDirectory();
    writeFileSync(join(directory, "dafare.json"), "questo non è json");
    const problems: string[] = [];
    const list = new ToDoList(directory);
    list.onProblem = (message) => problems.push(message);
    assert.equal(list.items.length, 0);
    assert.equal(problems.length, 1);
    assert.ok(readdirSync(directory).some((name) => name.startsWith("dafare.corrotto-")));
    list.add("di nuovo");
    assert.equal(new ToDoList(directory).items.length, 1);
  });
});

describe("Da fare: il compagno ricorda le scadenze", () => {
  const item = (text: string, due: string | null, n = 0, done = false): ToDoItem => ({
    id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, text, due, subject: null, createdAt: 1_760_000_000_000 + n * 1000, doneAt: done ? 1 : null,
  });
  it("solo oggi e domani", () => {
    assert.equal(reminderMessage([], TODAY), null);
    assert.equal(reminderMessage([item("Scaduta", "2026-10-19"), item("Senza data", null), item("Lontana", "2026-10-27")], TODAY), null);
    assert.equal(reminderMessage([item("Esercizi di analisi", "2026-10-21")], TODAY), "Domani scade «Esercizi di analisi». Un focus adesso?");
    assert.equal(reminderMessage([item("Prenotare l'esame", TODAY)], TODAY), "Oggi scade «Prenotare l'esame». Un focus adesso?");
    assert.equal(reminderMessage([item("Per domani", "2026-10-21"), item("Per oggi", TODAY)], TODAY), "Oggi scade «Per oggi». Un focus adesso?");
    assert.equal(reminderMessage([item("Fatta", TODAY, 0, true)], TODAY), null);
    assert.equal(reminderMessage([item("Ultimo dell'anno", "2027-01-01")], "2026-12-31"), "Domani scade «Ultimo dell'anno». Un focus adesso?");
  });
  it("più voci: la più vecchia, e «un'altra» o «altre N»", () => {
    assert.equal(reminderMessage([item("Prima", TODAY, 1), item("Seconda", TODAY, 2)], TODAY), "Oggi scadono 2 cose: «Prima» e un'altra.");
    assert.equal(reminderMessage([item("A", "2026-10-21", 3), item("B", "2026-10-21", 1), item("C", "2026-10-21", 2)], TODAY),
      "Domani scadono 3 cose: «B» e altre 2.");
  });
  it("un testo lungo si accorcia a una parola intera", () => {
    assert.equal(reminderMessage([item("parola ".repeat(20).trim(), TODAY)], TODAY), "Oggi scade «parola parola parola parola parola…». Un focus adesso?");
  });
  it("i gruppi senza voci non ci sono", () => {
    assert.deepEqual(sections([item("Solo una", null)], TODAY).map((g) => g.group), ["noDate"]);
  });
});
