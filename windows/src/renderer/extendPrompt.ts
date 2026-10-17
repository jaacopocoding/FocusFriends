// Il pulsante «+5 minuti» che compare accanto al compagno quando il focus è finito: se lo tocchi il focus continua, altrimenti
// (dopo pochi secondi) parte la pausa. Una piccola carta con una barretta che si svuota (ExtendPrompt.swift).

import type { Size } from "../core/pets.ts";

export const PROMPT_SIZE: Size = { width: 206, height: 60 };
const EXTRA_MINUTES = 5;

export class ExtendPrompt {
  readonly element: HTMLDivElement;
  private readonly fill: HTMLDivElement;
  private startedAt = 0;
  private duration = 10_000;
  private showing = false;
  private left = 0;
  private top = 0;
  onClick: (() => void) | null = null;

  constructor(parent: HTMLElement) {
    const card = document.createElement("div");
    card.className = "extend";
    card.setAttribute("role", "button");
    card.setAttribute("aria-label", `Aggiungi ${EXTRA_MINUTES} minuti al focus`);
    card.innerHTML = `
      <div class="badge">+${EXTRA_MINUTES}</div>
      <div class="line1">Ancora ${EXTRA_MINUTES} minuti?</div>
      <div class="line2">Tocca per continuare</div>
      <div class="track"><div class="fill"></div></div>`;
    this.element = card;
    this.fill = card.querySelector(".fill") as HTMLDivElement;
    card.addEventListener("click", () => this.onClick?.());
    parent.append(card);
  }

  get isShowing(): boolean { return this.showing; }

  show(seconds: number, now: number): void {
    this.startedAt = now;
    this.duration = seconds * 1000;
    this.showing = true;
    this.fill.style.width = "100%";
    this.element.classList.add("visible");
  }

  hide(): void {
    this.showing = false;
    this.element.classList.remove("visible");
  }

  /** Fa scendere la barretta. */
  update(now: number): void {
    if (!this.showing) return;
    const remaining = Math.max(0, 1 - (now - this.startedAt) / this.duration);
    this.fill.style.width = `${(remaining * 100).toFixed(1)}%`;
  }

  /** La posizione in cui sta adesso (per capire se il mouse è sopra). */
  get rect(): { left: number; top: number; width: number; height: number } {
    return { left: this.left, top: this.top, width: PROMPT_SIZE.width, height: PROMPT_SIZE.height };
  }

  contains(x: number, y: number): boolean {
    return this.showing && x >= this.left && x < this.left + PROMPT_SIZE.width && y >= this.top && y < this.top + PROMPT_SIZE.height;
  }

  move(left: number, top: number): void {
    this.left = left;
    this.top = top;
    this.element.style.transform = `translate(${Math.round(left * 4) / 4}px, ${Math.round(top * 4) / 4}px)`;
  }
}
