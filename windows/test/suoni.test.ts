// Le decisioni dei suoni (core/audioPlan.ts).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { AMBIENT_PREVIEW_MS, AMBIENT_STOP_AFTER_MS, FADE_SECONDS, MusicQueue, QUICK_FADE_SECONDS, musicWanted, planAmbient } from "../src/core/audioPlan.ts";

describe("Suono ambiente", () => {
  it("si sente solo durante un focus, e con un suono scelto", () => {
    assert.equal(planAmbient({ sound: "rain", volume: 0.25, focusActive: true, previewing: false }).wanted, true);
    assert.equal(planAmbient({ sound: "rain", volume: 0.25, focusActive: false, previewing: false }).wanted, false);
    assert.equal(planAmbient({ sound: "none", volume: 0.25, focusActive: true, previewing: true }).wanted, false);
  });
  it("acceso: volume scelto e dissolvenza di due secondi; un cambio di volume è rapido", () => {
    const on = planAmbient({ sound: "wind", volume: 0.4, focusActive: true, previewing: false });
    assert.deepEqual([on.kind, on.gain, on.fadeSeconds, on.previewMs, on.stopAfterMs], [3, 0.4, FADE_SECONDS, null, null]);
    assert.equal(planAmbient({ sound: "wind", volume: 0.4, focusActive: true, previewing: false, quick: true }).fadeSeconds, QUICK_FADE_SECONDS);
  });
  it("l'anteprima si spegne da sola dopo tre secondi", () => {
    const preview = planAmbient({ sound: "brown", volume: 0.25, focusActive: false, previewing: true });
    assert.deepEqual([preview.wanted, preview.kind, preview.previewMs], [true, 2, AMBIENT_PREVIEW_MS]);
  });
  it("spento: volume zero, dissolvenza, poi il motore si ferma", () => {
    const off = planAmbient({ sound: "rain", volume: 0.25, focusActive: false, previewing: false });
    assert.deepEqual([off.gain, off.fadeSeconds, off.stopAfterMs], [0, FADE_SECONDS, AMBIENT_STOP_AFTER_MS]);
  });
});

describe("Musica", () => {
  it("suona solo con una sorgente, durante un focus o in anteprima", () => {
    assert.ok(musicWanted("bundled", true, false) && musicWanted("folder", false, true));
    assert.ok(!musicWanted("off", true, true) && !musicWanted("bundled", false, false));
  });
  it("tutti i brani escono prima che uno si ripeta, e il primo del giro nuovo non è l'ultimo", () => {
    const tracks = ["a", "b", "c", "d"];
    let state = 7;
    const random = (): number => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 2 ** 32; };
    const queue = new MusicQueue(random);
    let previous: string | null = null;
    for (let round = 0; round < 20; round += 1) {
      const heard = tracks.map(() => queue.next(tracks)!);
      assert.deepEqual([...heard].sort(), tracks, `giro ${round}`);
      assert.notEqual(heard[0], previous, `il giro ${round} non riparte da ${previous}`);
      previous = heard.at(-1)!;
    }
  });
  it("senza brani non esce niente; reset ricomincia", () => {
    const queue = new MusicQueue();
    assert.equal(queue.next([]), null);
    assert.ok(queue.next(["x", "y"]) !== null && queue.remaining === 1);
    queue.reset();
    assert.equal(queue.remaining, 0);
  });
});
