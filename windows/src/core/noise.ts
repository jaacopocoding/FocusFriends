// Il generatore dei rumori (pioggia, rumore marrone, vento): rumore filtrato in tempo reale, niente file e niente licenze.
// È la classe NoiseSynth di AmbientPlayer.swift, passo per passo (stessi numeri, stesso generatore di numeri a caso, a 44100 Hz):
// la prova di contratto confronta quello che esce con le misure fatte dall'app per Mac (tests/genera-rumore.sh).
// Gira nel thread audio: niente allocazioni dentro `render`.

import type { AmbientSound } from "./rules.ts";

export const NOISE_KINDS: Record<AmbientSound, number> = { none: 0, rain: 1, brown: 2, wind: 3 };

export class NoiseSynth {
  /** 0 nessuno, 1 pioggia, 2 marrone, 3 vento. */
  kind = 0;
  targetGain = 0;
  fadeSeconds = 2;

  private gain = 0;
  private readonly sampleRate: number;
  private seedL = 0x1234ABCD;
  private seedR = 0x9E3779B9;
  private seedD = 0x2545F491;

  private brownL = 0; private brownR = 0;
  // Pioggia: un fondo morbido (rumore rosa), una grandine fitta di micro-impatti e rari «tonfi» bassi.
  private pinkL0 = 0; private pinkL1 = 0; private pinkL2 = 0;
  private pinkR0 = 0; private pinkR1 = 0; private pinkR2 = 0;
  private bedLowL = 0; private bedLowR = 0; private bedHighL = 0; private bedHighR = 0;
  private shotEnvL = 0; private shotEnvR = 0; private shotLpL = 0; private shotLpR = 0; private shotHpL = 0; private shotHpR = 0;
  private plopEnv = 0; private plopLow = 0; private plopCoef = 0.1; private plopPan = 0.5;
  private rainPhaseA = 0; private rainPhaseB = 0.7;
  private wind1L = 0; private wind2L = 0; private wind1R = 0; private wind2R = 0;
  private lfoA = 0; private lfoB = 1.3;

  constructor(sampleRate: number) {
    this.sampleRate = sampleRate;
  }

  // Tre generatori xorshift32 (uno per canale e uno per i micro-impatti): numeri tra -1 e 1.
  private whiteL(): number {
    let s = this.seedL;
    s = (s ^ (s << 13)) >>> 0;
    s = (s ^ (s >>> 17)) >>> 0;
    s = (s ^ (s << 5)) >>> 0;
    this.seedL = s;
    return (s | 0) / 2147483647;
  }

  private whiteR(): number {
    let s = this.seedR;
    s = (s ^ (s << 13)) >>> 0;
    s = (s ^ (s >>> 17)) >>> 0;
    s = (s ^ (s << 5)) >>> 0;
    this.seedR = s;
    return (s | 0) / 2147483647;
  }

  private whiteD(): number {
    let s = this.seedD;
    s = (s ^ (s << 13)) >>> 0;
    s = (s ^ (s >>> 17)) >>> 0;
    s = (s ^ (s << 5)) >>> 0;
    this.seedD = s;
    return (s | 0) / 2147483647;
  }

  render(frames: number, left: Float32Array, right: Float32Array, offset = 0): void {
    const step = 1 / (this.sampleRate * Math.max(this.fadeSeconds, 0.05));
    const twoPi = Math.PI * 2;
    for (let n = 0; n < frames; n += 1) {
      const i = offset + n;
      // Dissolvenza lineare verso il volume voluto
      if (this.gain < this.targetGain) this.gain = Math.min(this.gain + step, this.targetGain);
      else if (this.gain > this.targetGain) this.gain = Math.max(this.gain - step, this.targetGain);
      if (this.gain === 0 && this.targetGain === 0) {
        left[i] = 0;
        right[i] = 0;
        continue;
      }
      const wl = this.whiteL(), wr = this.whiteR();
      let l = 0, r = 0;
      switch (this.kind) {
        case 1: { // pioggia: fondo morbido + micro-impatti fitti + rari tonfi (niente toni puri)
          // Fondo: rumore rosa (Paul Kellet), tolto il rimbombo e addolcito in alto.
          this.pinkL0 = 0.99765 * this.pinkL0 + wl * 0.0990460;
          this.pinkL1 = 0.96300 * this.pinkL1 + wl * 0.2965164;
          this.pinkL2 = 0.57000 * this.pinkL2 + wl * 1.0526913;
          this.pinkR0 = 0.99765 * this.pinkR0 + wr * 0.0990460;
          this.pinkR1 = 0.96300 * this.pinkR1 + wr * 0.2965164;
          this.pinkR2 = 0.57000 * this.pinkR2 + wr * 1.0526913;
          const pl = (this.pinkL0 + this.pinkL1 + this.pinkL2 + wl * 0.1848) * 0.11;
          const pr = (this.pinkR0 + this.pinkR1 + this.pinkR2 + wr * 0.1848) * 0.11;
          this.bedLowL += 0.035 * (pl - this.bedLowL); this.bedLowR += 0.035 * (pr - this.bedLowR);       // taglia sotto ~240 Hz
          this.bedHighL += 0.55 * ((pl - this.bedLowL) - this.bedHighL); this.bedHighR += 0.55 * ((pr - this.bedLowR) - this.bedHighR);   // addolcisce sopra ~4 kHz
          // La pioggia si fa un po' più forte e un po' più debole, piano e senza un ritmo regolare.
          this.rainPhaseA += twoPi * 0.037 / this.sampleRate;
          this.rainPhaseB += twoPi * 0.091 / this.sampleRate;
          if (this.rainPhaseA > twoPi) this.rainPhaseA -= twoPi;
          if (this.rainPhaseB > twoPi) this.rainPhaseB -= twoPi;
          const intensity = 1 + 0.10 * Math.sin(this.rainPhaseA) + 0.06 * Math.sin(this.rainPhaseB);
          // Micro-impatti: tantissimi, molto brevi, ognuno un lampo di rumore (non una nota).
          if (Math.abs(this.whiteD()) < 0.004) this.shotEnvL += 0.15 + 0.35 * Math.abs(this.whiteD());
          if (Math.abs(this.whiteD()) < 0.004) this.shotEnvR += 0.15 + 0.35 * Math.abs(this.whiteD());
          this.shotEnvL *= 0.9965; this.shotEnvR *= 0.9965;
          this.shotLpL += 0.45 * (wl - this.shotLpL); this.shotLpR += 0.45 * (wr - this.shotLpR);            // niente acuti sibilanti
          this.shotHpL += 0.05 * (this.shotLpL - this.shotHpL); this.shotHpR += 0.05 * (this.shotLpR - this.shotHpR);  // niente rimbombo
          const shotL = (this.shotLpL - this.shotHpL) * this.shotEnvL, shotR = (this.shotLpR - this.shotHpR) * this.shotEnvR;
          // Tonfi: ogni tanto una goccia più grossa, un colpetto di rumore scuro e breve.
          if (Math.abs(this.whiteD()) < 0.00008) {
            this.plopEnv = 0.35 + 0.5 * Math.abs(this.whiteD());
            this.plopCoef = 0.04 + 0.16 * Math.abs(this.whiteD());
            this.plopPan = 0.5 + 0.4 * this.whiteD();
          }
          this.plopEnv *= 0.9988;
          this.plopLow += this.plopCoef * (this.whiteD() - this.plopLow);
          const plop = this.plopLow * this.plopEnv * 1.1;
          l = (this.bedHighL * 0.72 + shotL * 0.68) * intensity + plop * (1 - this.plopPan);
          r = (this.bedHighR * 0.72 + shotR * 0.68) * intensity + plop * this.plopPan;
          break;
        }
        case 2: // rumore marrone: voce bassa e avvolgente
          this.brownL = (this.brownL + 0.02 * wl) / 1.02;
          this.brownR = (this.brownR + 0.02 * wr) / 1.02;
          l = this.brownL * 3.2;
          r = this.brownR * 3.2;
          break;
        case 3: { // vento: rumore passa-basso che respira
          this.lfoA += twoPi * 0.07 / this.sampleRate;
          this.lfoB += twoPi * 0.19 / this.sampleRate;
          if (this.lfoA > twoPi) this.lfoA -= twoPi;
          if (this.lfoB > twoPi) this.lfoB -= twoPi;
          const swell = 0.55 + 0.35 * Math.sin(this.lfoA) + 0.10 * Math.sin(this.lfoB);
          const a = 0.03 + 0.07 * (0.5 + 0.5 * Math.sin(this.lfoB));      // la voce sale e scende tra ~200 e ~700 Hz
          this.wind1L += a * (wl - this.wind1L); this.wind2L += a * (this.wind1L - this.wind2L);
          this.wind1R += a * (wr - this.wind1R); this.wind2R += a * (this.wind1R - this.wind2R);
          l = this.wind2L * 3.2 * swell;
          r = this.wind2R * 3.2 * swell;
          break;
        }
        default:
          break;
      }
      const master = 0.8 * this.gain;
      left[i] = Math.max(-1, Math.min(1, l * master));
      right[i] = Math.max(-1, Math.min(1, r * master));
    }
  }
}
