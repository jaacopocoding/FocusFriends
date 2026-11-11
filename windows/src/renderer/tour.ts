// Il giro guidato della prima apertura (GuidedTour.swift): dopo la scheda del nome e del compagno, o da «Fai il giro» nel menu.
// Il compagno freme e dice «Cliccami!!!»; un clic su di lui apre la scheda, che si scurisce tranne una parte alla volta, e un fumetto
// accanto spiega quella parte (per il giardino, le statistiche e l'album, con l'immagine di com'è fatto). Finché il giro va, la scheda
// non si chiude con un clic fuori e non risponde ai clic; «Salta» o Esc lo chiudono.

import type { MenuCard } from "./card/card.ts";
import { h } from "./card/dom.ts";
import type { Speaker } from "./speaker.ts";

export interface TourStep {
  section: "durations" | "today" | "garden" | "stats" | "album" | "avatars" | "settings";
  text: string;
  /** L'immagine di com'è fatto (in `assets/benvenuto/`), se c'è. */
  image?: string;
}

export const TOUR_CALL = "Cliccami!!!";
export const TOUR_STEPS: readonly TourStep[] = [
  { section: "durations", text: "Qui scegli la durata del focus. Il timer parte appena tocchi i minuti." },
  { section: "today", text: "Il tempo di studio di oggi, i focus fatti e i giorni di fila." },
  { section: "garden", text: "Il giardino: un'isola per ogni compagno da decorare come preferisci. Più studi, più decori!", image: "benvenuto/giardino.png" },
  { section: "stats", text: "Le statistiche: guarda quanto studi ogni giorno e per materia.", image: "benvenuto/statistiche.png" },
  { section: "album", text: "L'album raccoglie le figurine che trovi studiando. La barra indica quanto manca alla prossima.", image: "benvenuto/album.png" },
  { section: "avatars", text: "I compagni da sbloccare. La barra indica quanto manca al prossimo." },
  { section: "settings", text: "Qui sotto: da fare, suoni, musica e altre impostazioni." },
  { section: "durations", text: "Fine del giro. Scegli la durata e inizia il primo focus." },
];
export const TOUR_FINISHED = "Buono studio.";
export const TOUR_SKIPPED = "Il giro si può rivedere dal menu.";

export interface TourHost {
  container: HTMLElement;
  card: MenuCard;
  speaker: Speaker;
  /** Il disegno del compagno (freme mentre chiama). */
  petCanvas(): HTMLCanvasElement | null;
  petBox(): { left: number; top: number; width: number; height: number };
  scene(): { width: number; height: number };
  urlOf(path: string): string;
  openCard(): void;
}

const EDGE = 8;

export class GuidedTour {
  private readonly host: TourHost;
  private state: "off" | "calling" | "steps" = "off";
  private step = 0;
  private shade: HTMLElement | null = null;
  private tip: HTMLElement | null = null;
  private peek: HTMLImageElement | null = null;

  constructor(host: TourHost) {
    this.host = host;
  }

  get isRunning(): boolean { return this.state !== "off"; }
  /** Il compagno sta chiamando: un clic su di lui apre la scheda. */
  get isCalling(): boolean { return this.state === "calling"; }

  start(): void {
    if (this.state !== "off") return;
    this.state = "calling";
    this.host.card.close();
    this.host.speaker.stop();
    this.host.speaker.hold(TOUR_CALL);
    this.host.petCanvas()?.classList.add("tour-calling");
  }

  /** Un clic sul compagno mentre chiama. */
  petClicked(): void {
    if (this.state !== "calling") return;
    this.host.openCard();
  }

  /** La scheda si è aperta (dal clic sul compagno, o in un altro modo mentre chiama): comincia il giro. */
  cardOpened(): void {
    if (this.state !== "calling") return;
    this.state = "steps";
    this.host.petCanvas()?.classList.remove("tour-calling");
    this.host.speaker.dismissNow();
    const card = this.host.card;
    card.pinned = true;
    card.onPinnedEscape = () => this.finish(false);
    // la scheda appare in un attimo: il primo passo appena è al suo posto
    window.setTimeout(() => this.show(0), 200);
  }

  /** La scheda si è chiusa durante il giro (non dovrebbe: per sicurezza il giro finisce). */
  cardClosed(): void {
    if (this.state === "steps") this.finish(false, true);
  }

  private show(index: number): void {
    const card = this.host.card;
    const item = TOUR_STEPS[index];
    const root = card.element;
    const paper = root?.querySelector<HTMLElement>(".card") ?? null;
    if (this.state !== "steps" || !item || !root || !paper) { this.finish(false); return; }
    this.step = index;
    const isLast = index === TOUR_STEPS.length - 1;
    root.querySelector<HTMLElement>(`[data-tour="${item.section}"]`)?.scrollIntoView({ block: "nearest" });
    const target = card.sectionRect(item.section);
    if (!target) { this.finish(false); return; }
    const scene = this.host.scene();

    // il velo sulla carta, con il buco sulla parte giusta
    const sheet = paper.getBoundingClientRect();
    if (!this.shade) {
      this.shade = h("div", { class: "tour-shade", "aria-hidden": "true" }, h("div", { class: "tour-spot" }));
      this.host.container.append(this.shade);
    }
    Object.assign(this.shade.style, { left: `${sheet.left}px`, top: `${sheet.top}px`, width: `${sheet.width}px`, height: `${sheet.height}px` });
    const spot = this.shade.firstElementChild as HTMLElement;
    Object.assign(spot.style, {
      left: `${target.left - sheet.left - 5}px`, top: `${target.top - sheet.top - 5}px`, width: `${target.width + 10}px`, height: `${target.height + 10}px`,
    });

    // il fumetto, dal lato della scheda lontano dal compagno (se non c'è posto, dall'altro)
    this.tip?.remove();
    const next = h("button", { class: "tour-next" }, isLast ? "Inizia il primo focus" : "Avanti");
    const skip = h("button", { class: "tour-skip" }, "Salta");
    next.addEventListener("click", () => (isLast ? this.finish(true) : this.show(index + 1)));
    skip.addEventListener("click", () => this.finish(false));
    const tip = h("div", { class: "tour-tip", role: "dialog", "aria-label": "Giro guidato" },
      h("div", { class: "tour-text" }, item.text),
      h("div", { class: "tour-row" }, skip, h("span", { class: "tour-count" }, isLast ? "" : `${index + 1} di ${TOUR_STEPS.length}`), next));
    this.host.container.append(tip);
    this.tip = tip;
    const box = root.getBoundingClientRect();
    const size = { width: tip.offsetWidth, height: tip.offsetHeight };
    const pet = this.host.petBox();
    let onLeft = pet.left + pet.width / 2 > box.left + box.width / 2;
    if (onLeft && box.left - size.width - EDGE < 0) onLeft = false;
    if (!onLeft && box.right + size.width + EDGE > scene.width) onLeft = true;
    const left = onLeft ? box.left - size.width - 4 : box.right + 4;
    const mid = target.top + target.height / 2;
    const top = Math.min(Math.max(mid - 30, EDGE), scene.height - size.height - EDGE);
    tip.classList.add(onLeft ? "tail-right" : "tail-left");
    tip.style.setProperty("--tail", `${Math.min(Math.max(mid - top, 22), size.height - 22)}px`);
    Object.assign(tip.style, { left: `${Math.round(left)}px`, top: `${Math.round(top)}px` });
    requestAnimationFrame(() => tip.classList.add("visible"));
    next.focus();

    // l'immagine di com'è fatto, sopra il fumetto (o sotto, se sopra non c'è posto), larga quanto c'è posto da quel lato
    this.peek?.remove();
    this.peek = null;
    if (item.image) {
      const room = onLeft ? left + size.width - 10 - EDGE : scene.width - EDGE - (left + 10);
      const width = Math.min(item.section === "stats" ? 300 : 420, Math.max(room, 220));
      const peek = h("img", { class: "tour-peek", alt: "", src: this.host.urlOf(item.image) });
      peek.style.width = `${width}px`;
      this.host.container.append(peek);
      this.peek = peek;
      const place = (): void => {
        const height = peek.offsetHeight || width * 0.6;
        let y = top - 12 - height;
        if (y < EDGE) y = top + size.height + 12;
        const x = Math.min(Math.max(onLeft ? left + size.width - 10 - width : left + 10, EDGE), scene.width - width - EDGE);
        Object.assign(peek.style, { left: `${Math.round(x)}px`, top: `${Math.round(Math.max(y, EDGE))}px` });
        peek.classList.add("visible");
      };
      if (peek.complete) place(); else peek.addEventListener("load", place, { once: true });
    }
  }

  /** Fine del giro: dall'ultimo passo (`started`), da «Salta», o perché la scheda si è chiusa. */
  private finish(started: boolean, cardClosed = false): void {
    if (this.state === "off") return;
    this.state = "off";
    this.host.petCanvas()?.classList.remove("tour-calling");
    this.shade?.remove();
    this.tip?.remove();
    this.peek?.remove();
    this.shade = null;
    this.tip = null;
    this.peek = null;
    const card = this.host.card;
    card.pinned = false;
    card.onPinnedEscape = null;
    if (started) {
      this.host.speaker.say(TOUR_FINISHED);
    } else {
      if (!cardClosed) card.close();
      this.host.speaker.say(TOUR_SKIPPED);
    }
  }
}
