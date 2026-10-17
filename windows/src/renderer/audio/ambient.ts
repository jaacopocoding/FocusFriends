// Il suono ambiente del focus (AmbientPlayer.swift): parte con il focus, si spegne a fine focus con una dissolvenza, a volume basso.
// Il rumore lo genera un AudioWorklet; qui si decide quando acceso, a che volume e con che dissolvenza (core/audioPlan.ts).

import { planAmbient } from "../../core/audioPlan.ts";
import type { AmbientPlan } from "../../core/audioPlan.ts";
import { clampVolume } from "../../core/rules.ts";
import type { AmbientSound } from "../../core/rules.ts";

/** Il rumore è calcolato per 44100 Hz (come sul Mac): il contesto audio gira a quella frequenza e il sistema ricampiona. */
const SAMPLE_RATE = 44100;

export interface AmbientOptions {
  workletUrl: string;
  /** Il motore audio non parte (nessuna uscita disponibile, errore di sistema): il suono non si sente. */
  onStartFailure: () => void;
  sound: AmbientSound;
  volume: number;
  /** Solo nelle prove: un analizzatore sull'uscita, per sapere se esce davvero qualcosa. */
  analyser?: boolean;
}

export class AmbientPlayer {
  private readonly options: AmbientOptions;
  private context: AudioContext | null = null;
  private node: AudioWorkletNode | null = null;
  private analyser: AnalyserNode | null = null;
  private starting: Promise<boolean> | null = null;
  private stopTimer: number | undefined;
  private previewTimer: number | undefined;
  private targetGain = 0;
  sound: AmbientSound;
  volume: number;
  /** C'è un focus in corso (con il suono acceso si sente). */
  focusActive = false;

  constructor(options: AmbientOptions) {
    this.options = options;
    this.sound = options.sound;
    this.volume = clampVolume(options.volume);
  }

  // ---- comandi

  /** Il focus comincia o finisce (o si ferma e riprende). */
  setFocusActive(active: boolean): void {
    this.focusActive = active;
    this.apply(false, false);
  }

  setSound(sound: AmbientSound, preview: boolean): void {
    this.sound = sound;
    this.apply(preview && !this.focusActive, false);
  }

  setVolume(volume: number, preview: boolean): void {
    this.volume = clampVolume(volume);
    this.apply(preview && !this.focusActive, true);
  }

  // ---- motore

  /** Mette il motore nello stato giusto. */
  private apply(previewing: boolean, quick: boolean): void {
    window.clearTimeout(this.previewTimer);
    this.previewTimer = undefined;
    const plan = planAmbient({ sound: this.sound, volume: this.volume, focusActive: this.focusActive, previewing, quick });
    if (plan.wanted) {
      window.clearTimeout(this.stopTimer);
      this.stopTimer = undefined;
      void this.start().then((ok) => {
        if (!ok) { this.options.onStartFailure(); return; }
        this.send(plan);
      });
      // Qualche secondo di anteprima, poi si spegne da solo.
      if (plan.previewMs !== null) this.previewTimer = window.setTimeout(() => this.apply(false, false), plan.previewMs);
    } else {
      this.send(plan);
      // Dopo la dissolvenza il motore si ferma del tutto (niente processore per un suono che non c'è).
      window.clearTimeout(this.stopTimer);
      if (plan.stopAfterMs !== null && this.context) {
        this.stopTimer = window.setTimeout(() => {
          if (this.targetGain === 0) void this.context?.suspend();
        }, plan.stopAfterMs);
      }
    }
  }

  private send(plan: AmbientPlan): void {
    this.targetGain = plan.gain;
    this.node?.port.postMessage({ kind: plan.kind, gain: plan.gain, fadeSeconds: plan.fadeSeconds });
  }

  /** Accende il motore audio (la prima volta lo crea); false se non parte. */
  private start(): Promise<boolean> {
    this.starting ??= this.create().then(async (ok) => {
      if (!ok || !this.context) return false;
      try {
        if (this.context.state !== "running") await this.context.resume();
        return this.context.state === "running";
      } catch {
        return false;
      }
    }).finally(() => { this.starting = null; });
    return this.starting;
  }

  private async create(): Promise<boolean> {
    if (this.context && this.node) return true;
    try {
      const context = new AudioContext({ sampleRate: SAMPLE_RATE, latencyHint: "playback" });
      await context.audioWorklet.addModule(this.options.workletUrl);
      const node = new AudioWorkletNode(context, "ff-noise", { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2] });
      if (this.options.analyser) {
        this.analyser = context.createAnalyser();
        this.analyser.fftSize = 2048;
        node.connect(this.analyser);
        this.analyser.connect(context.destination);
      } else {
        node.connect(context.destination);
      }
      this.context = context;
      this.node = node;
      return true;
    } catch {
      return false;
    }
  }

  // ---- per le prove

  /** Il livello (rms) di quello che esce adesso; solo con `analyser`. */
  level(): number {
    if (!this.analyser) return -1;
    const data = new Float32Array(this.analyser.fftSize);
    this.analyser.getFloatTimeDomainData(data);
    let sum = 0;
    for (const x of data) sum += x * x;
    return Math.sqrt(sum / data.length);
  }

  get state(): string { return this.context?.state ?? "non creato"; }
}
