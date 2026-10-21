// Le impostazioni, i timer personalizzati, il quadrante e il ciclo della pausa lunga (windows/src/core/settings.ts).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { cpSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Settings } from "../src/core/settings.ts";
import { AMBIENT_DEFAULT_VOLUME, BreakCycle, CHATTINESS, MUSIC_DEFAULT_VOLUME, chattinessInterval, clampVolume,
  dialFilledFraction, dialMinutes, FOCUSES_PER_CYCLE, LONG_BREAK_MINUTES } from "../src/core/rules.ts";
import { tempDirectory } from "./util.ts";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "tests", "fixtures");
const copyOf = (name: string): string => {
  const dir = tempDirectory();
  cpSync(join(fixtures, name), dir, { recursive: true });
  return dir;
};

describe("Impostazioni", () => {
  it("i predefiniti", () => {
    const s = new Settings(tempDirectory());
    assert.deepEqual(
      [s.pet, s.phraseFrequency, s.movement, s.askHowItWent, s.longBreakEnabled, s.ambientSound, s.ambientVolume, s.musicSource,
        s.musicFolder, s.musicVolume, s.developerMode, s.customTimers("focus"), s.customTimers("rest")],
      ["pianty", "sometimes", true, true, true, "none", 0.25, "off", null, 0.3, false, [], []]);
    assert.ok(AMBIENT_DEFAULT_VOLUME === 0.25 && MUSIC_DEFAULT_VOLUME === 0.3);
  });

  it("le preferenze valide dell'esempio si leggono", () => {
    const s = new Settings(copyOf("impostazioni-esempio"));
    assert.deepEqual(
      [s.pet, s.phraseFrequency, s.movement, s.askHowItWent, s.longBreakEnabled, s.ambientSound, s.ambientVolume, s.musicSource,
        s.musicFolder, s.musicVolume, s.developerMode, s.customTimers("focus"), s.customTimers("rest")],
      ["gattino", "rarely", false, true, true, "rain", 0.4, "folder", "C:\\Musica\\Studio", 0.3, false, [40, 90], [15]]);
  });

  it("i valori sbagliati valgono i predefiniti", () => {
    const s = new Settings(copyOf("impostazioni-sbagliate"));
    assert.equal(s.pet, "pianty", "un compagno sconosciuto vale Pianty");
    assert.equal(s.phraseFrequency, "sometimes");
    assert.equal(s.movement, true, "un testo al posto di vero/falso");
    assert.equal(s.ambientVolume, 1, "un volume oltre il massimo si riporta a 1");
    assert.equal(s.musicVolume, 0.3, "un testo al posto di un numero");
    assert.deepEqual(s.customTimers("focus"), [45], "fuori misura, di serie e ripetuti si ignorano");
    assert.deepEqual(s.customTimers("rest"), [], "un testo al posto dell'elenco");
  });

  it("un file che non è un oggetto vale come vuoto, e il salvataggio lo sostituisce", () => {
    for (const text of ["non e' json", "[1, 2]", "42", ""]) {
      const dir = tempDirectory();
      writeFileSync(join(dir, "impostazioni.json"), text);
      const s = new Settings(dir);
      assert.equal(s.pet, "pianty", text);
      s.movement = false;
      assert.equal(new Settings(dir).movement, false, text);
    }
  });

  it("si salva e si rilegge, nel formato piatto con le chiavi in ordine", () => {
    const dir = tempDirectory();
    const s = new Settings(dir);
    let changes = 0;
    s.addObserver(() => { changes += 1; });
    s.pet = "ciccio";
    s.phraseFrequency = "never";
    s.ambientSound = "wind";
    s.ambientVolume = 9;
    s.musicFolder = "/Users/x/Lofi";
    s.addCustomTimer(40, "focus");
    assert.equal(changes, 6);
    const again = new Settings(dir);
    assert.deepEqual([again.pet, again.phraseFrequency, again.ambientSound, again.ambientVolume, again.musicFolder, again.customTimers("focus")],
      ["ciccio", "never", "wind", 1, "/Users/x/Lofi", [40]]);
    const text = readFileSync(join(dir, "impostazioni.json"), "utf8");
    assert.deepEqual(Object.keys(JSON.parse(text)), [...Object.keys(JSON.parse(text))].sort());
    assert.ok(text.includes('"customTimers.focus" : ['), text);
    s.musicFolder = null;
    assert.ok(!("musicFolder" in JSON.parse(readFileSync(join(dir, "impostazioni.json"), "utf8"))), "togliere la cartella toglie la chiave");
  });

  it("il riepilogo della settimana già detto si ricorda (e un valore sbagliato vale «mai detto»)", () => {
    const dir = tempDirectory();
    const s = new Settings(dir);
    assert.equal(s.lastWeeklyRecap, null);
    s.lastWeeklyRecap = "2026-10-12";
    assert.equal(new Settings(dir).lastWeeklyRecap, "2026-10-12");
    assert.equal(JSON.parse(readFileSync(join(dir, "impostazioni.json"), "utf8")).lastWeeklyRecap, "2026-10-12");
    writeFileSync(join(dir, "impostazioni.json"), '{"lastWeeklyRecap": 7}');
    assert.equal(new Settings(dir).lastWeeklyRecap, null, "un numero al posto del testo");
    writeFileSync(join(dir, "impostazioni.json"), '{"lastWeeklyRecap": ""}');
    assert.equal(new Settings(dir).lastWeeklyRecap, null, "un testo vuoto");
  });

  it("le chiavi che non conosce restano", () => {
    const dir = tempDirectory();
    writeFileSync(join(dir, "impostazioni.json"), '{"cosaDelFuturo": 7}');
    new Settings(dir).movement = false;
    assert.equal(JSON.parse(readFileSync(join(dir, "impostazioni.json"), "utf8")).cosaDelFuturo, 7);
  });

  it("una scrittura che non riesce si segnala una volta sola", () => {
    const blocker = join(tempDirectory(), "occupato");
    writeFileSync(blocker, "x");
    const s = new Settings(blocker);
    const messages: string[] = [];
    s.onProblem = (message) => messages.push(message);
    s.movement = false;
    s.movement = true;
    assert.ok(messages.length === 1 && messages[0]!.startsWith("Non riesco a salvare le impostazioni"), String(messages));
  });

  it("il volume", () => {
    assert.ok(clampVolume(-1) === 0 && clampVolume(2) === 1 && clampVolume(0.4) === 0.4);
    assert.equal(clampVolume(Number.NaN), 0.25, "non valido: torna al valore di partenza");
    assert.equal(clampVolume(Infinity), 0.25);
  });
});

describe("Frequenza delle frasi", () => {
  it("le pause tra una frase e l'altra", () => {
    assert.deepEqual(CHATTINESS, ["often", "sometimes", "rarely", "never"]);
    assert.deepEqual(chattinessInterval("sometimes", false), { min: 40, max: 110 });
    assert.deepEqual(chattinessInterval("often", true), { min: 120, max: 240 });
    assert.deepEqual(chattinessInterval("rarely", true), { min: 600, max: 900 });
    assert.equal(chattinessInterval("never", false), null);
    assert.equal(chattinessInterval("never", true), null);
    for (const c of CHATTINESS) {
      const a = chattinessInterval(c, false), b = chattinessInterval(c, true);
      if (a && b) assert.ok(b.min > a.min && b.max > a.max, "durante un focus parla di meno");
    }
  });
});

describe("Timer personalizzati", () => {
  it("quelli di serie, quelli aggiunti, i limiti", () => {
    const dir = tempDirectory();
    const s = new Settings(dir);
    assert.deepEqual(s.allTimers("focus"), [30, 50]);
    assert.deepEqual(s.allTimers("rest"), [5, 10]);
    assert.deepEqual(s.addCustomTimer(90, "focus"), { result: "added" });
    assert.deepEqual(s.addCustomTimer(40, "focus"), { result: "added" });
    assert.deepEqual(s.allTimers("focus"), [30, 40, 50, 90], "in ordine crescente");
    assert.ok(s.isCustomTimer(40, "focus") && !s.isCustomTimer(30, "focus"));
    assert.deepEqual(s.addCustomTimer(40, "focus"), { result: "alreadyExists" });
    assert.deepEqual(s.addCustomTimer(30, "focus"), { result: "alreadyExists" }, "uno di serie");
    assert.deepEqual(s.addCustomTimer(0, "focus"), { result: "outOfRange", min: 1, max: 180 });
    assert.deepEqual(s.addCustomTimer(181, "focus"), { result: "outOfRange", min: 1, max: 180 });
    assert.deepEqual(s.addCustomTimer(61, "rest"), { result: "outOfRange", min: 1, max: 60 });
    assert.deepEqual(s.addCustomTimer(2.5, "rest"), { result: "outOfRange", min: 1, max: 60 });
    for (const m of [41, 42, 43, 44]) s.addCustomTimer(m, "focus");
    assert.deepEqual(s.addCustomTimer(45, "focus"), { result: "tooMany", max: 6 });
    s.removeCustomTimer(90, "focus");
    assert.deepEqual(s.addCustomTimer(45, "focus"), { result: "added" });
    assert.deepEqual(s.allTimers("rest"), [5, 10], "gli altri tipi non cambiano");
    assert.deepEqual(new Settings(dir).customTimers("focus"), [40, 41, 42, 43, 44, 45]);
  });
});

describe("Quadrante dei timer", () => {
  it("dal punto trascinato ai minuti", () => {
    assert.equal(dialMinutes(0.5, 50, 120, 5), 60, "mezzo giro = 60 minuti");
    assert.equal(dialMinutes(0.33, 30, 120, 5), 40, "si arrotonda ai 5 minuti (39,6 → 40)");
    assert.equal(dialMinutes(0.999, 110, 120, 5), 120, "in fondo al giro: il massimo");
    assert.equal(dialMinutes(0.001, 5, 120, 5), 5, "all'inizio: mai sotto il minimo");
    assert.equal(dialMinutes(0.02, 115, 120, 5), 120, "passando per mezzogiorno non torna a zero");
    assert.equal(dialMinutes(0.98, 5, 120, 5), 5, "e non salta al massimo");
    assert.equal(dialMinutes(0.5, 150, 120, 5), 60, "un timer tuo oltre il giro si riporta dentro");
    assert.equal(dialMinutes(0.5, 5, 30, 1), 15, "pausa: mezzo giro = 15 minuti");
  });
  it("la parte colorata", () => {
    assert.equal(dialFilledFraction(60, 120), 0.5);
    assert.equal(dialFilledFraction(150, 120), 1, "al massimo un giro");
    assert.equal(dialFilledFraction(-5, 120), 0);
  });
});

describe("Pausa lunga", () => {
  const base = Date.UTC(2026, 9, 14, 9);
  const at = (minutes: number): number => base + minutes * 60_000;

  it("al quarto focus la pausa è lunga, poi si riparte", () => {
    const cycle = new BreakCycle();
    assert.ok(!cycle.focusCompleted(at(50)) && cycle.completed === 1, "il primo focus: pausa normale");
    assert.ok(!cycle.focusCompleted(at(105)) && !cycle.focusCompleted(at(160)), "secondo e terzo: pausa normale");
    assert.equal(cycle.completed, 3);
    assert.ok(cycle.focusCompleted(at(215)), "il quarto: pausa lunga");
    assert.ok(cycle.completed === 0 && !cycle.focusCompleted(at(270)), "dopo la pausa lunga si riparte");
  });
  it("una lunga assenza azzera il ciclo", () => {
    const away = new BreakCycle();
    away.focusCompleted(at(50)); away.focusCompleted(at(105)); away.focusCompleted(at(160));
    assert.ok(!away.focusCompleted(at(160 + 3 * 60)), "dopo 3 ore il ciclo ricomincia (era il 4°, ora è il 1°)");
    assert.equal(away.completed, 1);
  });
  it("una pausa di un'ora e mezza non lo azzera", () => {
    const pauses = new BreakCycle();
    for (let i = 0; i < 3; i += 1) pauses.focusCompleted(at(i * 90));
    assert.ok(pauses.focusCompleted(at(3 * 90)));
    assert.equal(pauses.done(at(3 * 90)), 0, "fatto il quarto: il ciclo è già ripartito");
  });
  it("quanti ne risultano fatti, e il reset", () => {
    const counting = new BreakCycle();
    counting.focusCompleted(at(50)); counting.focusCompleted(at(105));
    assert.equal(counting.done(at(110)), 2);
    assert.equal(counting.done(at(105 + 3 * 60)), 0, "dopo troppo tempo risultano zero");
    assert.equal(counting.completed, 2, "il conteggio interno non cambia leggendo");
    const manual = new BreakCycle();
    manual.focusCompleted(at(50)); manual.reset();
    assert.equal(manual.completed, 0);
    assert.ok(FOCUSES_PER_CYCLE === 4 && LONG_BREAK_MINUTES === 15);
  });
});
