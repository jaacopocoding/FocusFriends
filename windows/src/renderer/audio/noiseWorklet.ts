// Il generatore dei rumori nel thread audio della pagina (AudioWorklet): riceve «che rumore, che volume, con che dissolvenza» e
// riempie i blocchi di campioni. Il calcolo è quello di core/noise.ts.

import { NoiseSynth } from "../../core/noise.ts";

// I tipi del contesto dei worklet non sono nelle definizioni della pagina: qui solo quel che serve.
declare const sampleRate: number;
declare class AudioWorkletProcessor {
  readonly port: MessagePort;
  constructor();
}
declare function registerProcessor(name: string, processor: new () => AudioWorkletProcessor): void;

interface NoiseMessage {
  kind: number;
  gain: number;
  fadeSeconds: number;
}

class FriendsNoise extends AudioWorkletProcessor {
  private readonly synth = new NoiseSynth(sampleRate);

  constructor() {
    super();
    this.port.onmessage = (event: MessageEvent<NoiseMessage>) => {
      this.synth.kind = event.data.kind;
      this.synth.targetGain = event.data.gain;
      this.synth.fadeSeconds = event.data.fadeSeconds;
    };
  }

  process(_inputs: Float32Array[][], outputs: Float32Array[][]): boolean {
    const channels = outputs[0];
    const left = channels?.[0], right = channels?.[1];
    if (left && right) this.synth.render(left.length, left, right);
    return true;
  }
}

registerProcessor("ff-noise", FriendsNoise);
