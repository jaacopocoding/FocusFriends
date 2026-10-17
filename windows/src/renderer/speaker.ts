// Fa comparire ogni tanto un fumetto con una frase sopra la testa del compagno (Speaker.swift).

import { createBubble, TAIL_TIP_FRACTION } from "./bubble.ts";
import type { Size } from "../core/pets.ts";

/** Quanto scende al massimo il fumetto ogni secondo: sale subito, scende piano (se il personaggio si abbassa il fumetto non rimbalza). */
const DESCEND_SPEED = 140;
const FADE_MS = 250;
const FIRST_PHRASE_AFTER = 5;

export interface SpeakerHost {
  /** Dove sta la scatola del compagno (angolo in alto a sinistra e dimensioni). */
  box(): { left: number; top: number; width: number; height: number };
  /** Altezza, dal bordo basso della scatola, a cui arriva tutto ciò che si vede del compagno. */
  visibleTop(): number;
  /** Lo spazio a disposizione: tutta la scena. */
  stage(): { width: number; height: number };
  /** La prossima frase del mazzo. */
  nextPhrase(): Promise<string>;
  /** Quanto aspettare tra una frase spontanea e la successiva, in secondi; null = non parla da sé. */
  interval(): { min: number; max: number } | null;
  container: HTMLElement;
}

export class Speaker {
  private readonly host: SpeakerHost;
  private bubble: { element: HTMLDivElement; size: Size } | null = null;
  private nextTimer: number | undefined;
  private hideTimer: number | undefined;
  private heightAbove: number | null = null;
  private lastFollow = performance.now();

  constructor(host: SpeakerHost) {
    this.host = host;
  }

  /** C'è un fumetto sullo schermo in questo momento. */
  get isSpeaking(): boolean { return this.bubble !== null; }

  private randomDelay(): number | null {
    const range = this.host.interval();
    return range === null ? null : range.min + Math.random() * (range.max - range.min);
  }

  /** Prima frase dopo qualche secondo, poi a intervalli casuali (salvo «Mai»). */
  start(): void {
    if (this.host.interval() !== null) this.scheduleNext(FIRST_PHRASE_AFTER);
  }

  /** Dopo un cambio di frequenza: riparte il conto con il nuovo intervallo, oppure tace. */
  reschedule(): void {
    window.clearTimeout(this.nextTimer);
    this.nextTimer = undefined;
    const delay = this.randomDelay();
    if (delay === null || this.bubble !== null) return;
    this.scheduleNext(delay);
  }

  /** Toglie subito il fumetto (per «Mai»: il silenzio parte subito). */
  dismissNow(): void {
    window.clearTimeout(this.hideTimer);
    this.hideTimer = undefined;
    this.dismiss(true);
  }

  stop(): void {
    window.clearTimeout(this.nextTimer);
    window.clearTimeout(this.hideTimer);
    this.dismiss(false);
  }

  /** Dice la prossima frase del mazzo. */
  async sayRandom(): Promise<void> {
    this.say(await this.host.nextPhrase());
  }

  say(text: string): void {
    window.clearTimeout(this.nextTimer);
    window.clearTimeout(this.hideTimer);
    this.dismiss(false);

    const bubble = createBubble(text);
    this.bubble = bubble;
    this.heightAbove = null;
    this.lastFollow = performance.now();
    this.host.container.append(bubble.element);
    this.place(null);
    // Un fotogramma dopo, perché la dissolvenza parta da zero.
    requestAnimationFrame(() => bubble.element.classList.add("visible"));

    const visibleFor = Math.max(4.5, 2.5 + Array.from(text).length * 0.06);
    this.hideTimer = window.setTimeout(() => {
      this.dismiss(true);
      const delay = this.randomDelay();
      if (delay !== null) this.scheduleNext(delay);
    }, visibleFor * 1000);
  }

  private scheduleNext(seconds: number): void {
    window.clearTimeout(this.nextTimer);
    this.nextTimer = window.setTimeout(() => { void this.sayRandom(); }, seconds * 1000);
  }

  /** Da chiamare a ogni passo dell'animazione: il fumetto segue il compagno. */
  follow(now: number): void {
    if (this.bubble === null) return;
    const dt = Math.min((now - this.lastFollow) / 1000, 0.1);
    this.lastFollow = now;
    this.place(dt);
  }

  /** Dove mettere il fumetto: sopra tutto ciò che si vede del compagno, con la punta della codina sulla sua testa. Se sopra non c'è posto sta di fianco, mai sopra il disegno. */
  private place(dt: number | null): void {
    const bubble = this.bubble;
    if (bubble === null) return;
    const box = this.host.box();
    const stage = this.host.stage();
    const size = bubble.size;

    const wanted = this.host.visibleTop() - 6;
    let height = wanted;
    if (this.heightAbove !== null && dt !== null && wanted < this.heightAbove) {
      height = Math.max(wanted, this.heightAbove - DESCEND_SPEED * dt);
    }
    this.heightAbove = height;

    let x = box.left + box.width / 2 - size.width * TAIL_TIP_FRACTION;
    x = Math.min(Math.max(x, 6), stage.width - size.width - 6);
    const top = box.top + box.height - height - size.height;
    if (top >= 4) {
      this.move(bubble.element, x, top);
      return;
    }
    // Di fianco, dal lato con più spazio, all'altezza più alta che lo schermo permette.
    const onLeft = box.left + box.width / 2 > stage.width / 2;
    let sideX = onLeft ? box.left - size.width - 2 : box.left + box.width + 2;
    sideX = Math.min(Math.max(sideX, 6), stage.width - size.width - 6);
    this.move(bubble.element, sideX, Math.max(4, 0));
  }

  private move(element: HTMLElement, x: number, y: number): void {
    element.style.transform = `translate(${Math.round(x * 4) / 4}px, ${Math.round(y * 4) / 4}px)`;
  }

  private dismiss(animated: boolean): void {
    const bubble = this.bubble;
    if (bubble === null) return;
    this.bubble = null;
    if (animated) {
      bubble.element.classList.remove("visible");
      window.setTimeout(() => bubble.element.remove(), FADE_MS + 50);
    } else {
      bubble.element.remove();
    }
  }
}
