// Il generatore dei rumori (core/noise.ts): il contratto con l'app per Mac (tests/fixtures/rumore.json, fatto da tests/genera-rumore.sh)
// e qualche proprietà (silenzio a volume zero, dissolvenza, niente oltre ±1).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { NOISE_KINDS, NoiseSynth } from "../src/core/noise.ts";

interface Measures {
  rmsSinistra: number; rmsDestra: number; picco: number; rmsPerSecondo: number[];
  campioniSinistra: number[]; campioniDestra: number[]; primiCampioni: number[];
}
const reference = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "..", "tests", "fixtures", "rumore.json"), "utf8")) as
  { frequenza: number; secondi: number; suoni: Record<string, Measures> };

const peak = (a: Float32Array): number => {
  let max = 0;
  for (let i = 0; i < a.length; i += 1) max = Math.max(max, Math.abs(a[i]!));
  return max;
};

const rms = (a: Float32Array, from: number, to: number): number => {
  let sum = 0;
  for (let i = from; i < to; i += 1) sum += a[i]! * a[i]!;
  return Math.sqrt(sum / Math.max(to - from, 1));
};

function renderTen(kind: number): { left: Float32Array; right: Float32Array } {
  const frames = reference.frequenza * reference.secondi;
  const synth = new NoiseSynth(reference.frequenza);
  synth.kind = kind;
  synth.targetGain = 1;
  synth.fadeSeconds = 0.05;
  const left = new Float32Array(frames), right = new Float32Array(frames);
  for (let offset = 0; offset < frames; offset += 128) synth.render(Math.min(128, frames - offset), left, right, offset);   // a blocchi da 128 campioni
  return { left, right };
}

describe("Rumori: contratto con il Mac", () => {
  const names: Array<[string, number]> = [["pioggia", NOISE_KINDS.rain], ["marrone", NOISE_KINDS.brown], ["vento", NOISE_KINDS.wind]];
  for (const [name, kind] of names) {
    it(name, () => {
      const expected = reference.suoni[name]!;
      const { left, right } = renderTen(kind);
      // Il Mac calcola in Float32 e qui in Double: i filtri ricorsivi si scostano un poco, ma il suono è lo stesso.
      const close = (actual: number, want: number, relative: number, absolute: number, what: string): void =>
        assert.ok(Math.abs(actual - want) <= Math.max(absolute, Math.abs(want) * relative), `${what}: ${actual} contro ${want}`);
      close(rms(left, 0, left.length), expected.rmsSinistra, 0.01, 1e-5, "rms sinistra");
      close(rms(right, 0, right.length), expected.rmsDestra, 0.01, 1e-5, "rms destra");
      close(peak(left), expected.picco, 0.02, 1e-4, "picco");
      // Nel vento il Mac somma la fase dell'oscillatore in Float32 (a ogni campione, 1e-5 su un numero intorno a 6): la sua frequenza
      // si scosta un poco e col tempo il respiro del vento va un po' fuori fase. Qui la somma è in Double: tolleranza più larga.
      const perSecond = name === "vento" ? 0.03 : 0.01;
      expected.rmsPerSecondo.forEach((want, second) => close(rms(left, second * 44100, (second + 1) * 44100), want, perSecond, 1e-5, `rms al secondo ${second}`));
      expected.primiCampioni.forEach((want, i) => close(left[i]!, want, 0.01, 2e-6, `campione ${i}`));
      // (nel vento, dopo due secondi, i singoli campioni dipendono dalla fase dell'oscillatore: si confrontano solo gli altri)
      if (name !== "vento") {
        expected.campioniSinistra.forEach((want, i) => close(left[44100 * 2 + i]!, want, 0.01, 2e-5, `campione sinistro ${i}`));
        expected.campioniDestra.forEach((want, i) => close(right[44100 * 2 + i]!, want, 0.01, 2e-5, `campione destro ${i}`));
      }
    });
  }
  it("nessuno è silenzio", () => {
    const { left, right } = renderTen(NOISE_KINDS.none);
    assert.ok(left.every((x) => x === 0) && right.every((x) => x === 0));
  });
});

describe("Rumori: proprietà", () => {
  it("a volume zero è silenzio e non costa nulla", () => {
    const synth = new NoiseSynth(44100);
    synth.kind = NOISE_KINDS.rain;
    const left = new Float32Array(1000).fill(9), right = new Float32Array(1000).fill(9);
    synth.render(1000, left, right);
    assert.ok(left.every((x) => x === 0) && right.every((x) => x === 0));
  });
  it("accende e spegne con una dissolvenza lineare (due secondi per il volume pieno)", () => {
    const synth = new NoiseSynth(44100);
    synth.kind = NOISE_KINDS.brown;
    synth.targetGain = 1;
    synth.fadeSeconds = 2;
    const length = 44100 * 4;
    const left = new Float32Array(length), right = new Float32Array(length);
    synth.render(length, left, right);
    const level = (second: number): number => rms(left, Math.floor(second * 44100), Math.floor((second + 0.25) * 44100));
    assert.ok(level(0) < level(0.75) && level(0.75) < level(1.5), "sale piano");
    assert.ok(Math.abs(level(3.5) - level(3.0)) / level(3.5) < 0.3, "poi resta lì");
    synth.targetGain = 0;
    const more = new Float32Array(length), moreRight = new Float32Array(length);
    synth.render(length, more, moreRight);
    assert.ok(rms(more, 0, 11025) > rms(more, 44100, 44100 + 11025), "scende");
    assert.equal(rms(more, 44100 * 2 + 10, 44100 * 4), 0, "e dopo due secondi è spento del tutto");
  });
  it("un cambio di volume con la dissolvenza breve si sente subito", () => {
    const synth = new NoiseSynth(44100);
    synth.kind = NOISE_KINDS.brown;
    synth.targetGain = 0.2;
    synth.fadeSeconds = 0.25;
    const left = new Float32Array(44100), right = new Float32Array(44100);
    synth.render(44100, left, right);
    synth.targetGain = 0.6;
    const next = new Float32Array(44100), nextRight = new Float32Array(44100);
    synth.render(44100, next, nextRight);
    assert.ok(rms(next, 22050, 44100) > 2 * rms(left, 22050, 44100));
  });
  it("non supera mai ±1, anche a volume massimo", () => {
    for (const kind of [1, 2, 3]) {
      const { left, right } = renderTen(kind);
      assert.ok(peak(left) <= 1 && peak(right) <= 1);
    }
  });
  it("i due canali non sono uguali (stereo)", () => {
    const { left, right } = renderTen(NOISE_KINDS.rain);
    let same = 0;
    for (let i = 0; i < 1000; i += 1) if (left[44100 + i] === right[44100 + i]) same += 1;
    assert.ok(same < 10);
  });
});
