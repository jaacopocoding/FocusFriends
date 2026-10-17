// Più schermi e posizione della scheda rispetto all'icona (core/displays.ts), con schermi inventati.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { cardPlacement, currentOrPrimary, displayAt, displayToFollow, relativeTo } from "../src/core/displays.ts";
import type { DisplayInfo } from "../src/core/displays.ts";

// Due schermi affiancati: il principale 1920×1080 con la barra in basso (40), il secondo 2560×1440 a destra, più in alto.
const primary: DisplayInfo = { id: 1, primary: true, bounds: { x: 0, y: 0, width: 1920, height: 1080 }, workArea: { x: 0, y: 0, width: 1920, height: 1040 } };
const second: DisplayInfo = { id: 2, primary: false, bounds: { x: 1920, y: -360, width: 2560, height: 1440 }, workArea: { x: 1920, y: -360, width: 2560, height: 1400 } };
const displays = [primary, second];

describe("Schermi", () => {
  it("quale schermo ha un punto", () => {
    assert.equal(displayAt(displays, 100, 100)?.id, 1);
    assert.equal(displayAt(displays, 2000, -300)?.id, 2);
    assert.equal(displayAt(displays, 1919, 1060)?.id, 1, "nella barra delle applicazioni: è dello schermo");
  });
  it("un punto fuori da tutti va allo schermo più vicino", () => {
    assert.equal(displayAt(displays, -50, 500)?.id, 1);
    assert.equal(displayAt(displays, 5000, 0)?.id, 2);
    assert.equal(displayAt([], 0, 0), null);
  });
  it("trascinando, si segue il cursore sull'altro schermo", () => {
    assert.equal(displayToFollow(displays, 1, { x: 500, y: 500 }), null);
    assert.equal(displayToFollow(displays, 1, { x: 2500, y: 100 })?.id, 2);
    assert.equal(displayToFollow(displays, 2, { x: 1900, y: 800 })?.id, 1);
  });
  it("se lo schermo del compagno sparisce torna sul principale", () => {
    assert.equal(currentOrPrimary(displays, 2)?.id, 2);
    assert.equal(currentOrPrimary([primary], 2)?.id, 1);
    assert.equal(currentOrPrimary([second], 9)?.id, 2, "senza principale, il primo che c'è");
    assert.equal(currentOrPrimary([], null), null);
  });
  it("un rettangolo nelle coordinate della finestra", () => {
    assert.deepEqual(relativeTo({ x: 2000, y: 1030, width: 24, height: 24 }, second.workArea), { x: 80, y: 1390, width: 24, height: 24 });
  });
});

describe("Posizione della scheda rispetto all'icona", () => {
  const scene = { width: 1920, height: 1040 };
  const card = { width: 300, height: 520 };
  it("barra in basso: la scheda sta sopra l'icona, vicino al bordo", () => {
    assert.deepEqual(cardPlacement({ x: 1800, y: 1050, width: 24, height: 24 }, scene, card), { left: 1612, top: 512 });
  });
  it("barra in alto: sotto l'icona", () => {
    assert.deepEqual(cardPlacement({ x: 1800, y: -30, width: 24, height: 24 }, scene, card), { left: 1612, top: 8 });
  });
  it("barra a destra: la scheda sta contro il bordo destro, all'altezza dell'icona", () => {
    assert.deepEqual(cardPlacement({ x: 1930, y: 500, width: 24, height: 24 }, scene, card), { left: 1612, top: 252 });
  });
  it("barra a sinistra: contro il bordo sinistro", () => {
    assert.deepEqual(cardPlacement({ x: -40, y: 900, width: 24, height: 24 }, scene, card), { left: 8, top: 512 });
  });
  it("senza uscire dall'area di lavoro, anche con una scheda più alta", () => {
    const tall = cardPlacement({ x: 10, y: 1050, width: 24, height: 24 }, { width: 800, height: 400 }, card);
    assert.deepEqual(tall, { left: 8, top: 8 });
  });
  it("un'icona dentro l'area di lavoro: la scheda le sta sopra", () => {
    assert.deepEqual(cardPlacement({ x: 900, y: 900, width: 24, height: 24 }, scene, card), { left: 762, top: 374 });
  });
});
