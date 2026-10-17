// «Com'è andata?»: la scheda che compare a fine focus. Un tocco su una faccia salva e chiude; la riga «cosa hai fatto» è facoltativa.
// Non ruba la tastiera (a fine focus potresti stare scrivendo altrove) e non blocca niente: se la ignori la sessione resta com'è, e la
// scheda sparisce da sola a fine pausa. (ReflectionCard.swift)

import type { Rating, StudySession } from "../../core/log.ts";
import { NOTE_MAX } from "../../core/text.ts";
import { button, h } from "../card/dom.ts";
import { RATING_TITLE, faceIcon } from "../card/widgets.ts";

const GAP_FROM_PET = 12;
const EDGE = 8;

export interface ReflectionHost {
  container: HTMLElement;
  petBox(): { left: number; top: number; width: number; height: number };
  scene(): { width: number; height: number };
  /** La scheda è sparita: i clic sotto di lei devono tornare a passare. */
  onClosed(): void;
  /** Il campo di testo prende o lascia la tastiera. */
  onKeyboard(needed: boolean): void;
  /** Il voto scelto (o null) e la nota: da salvare. */
  onSave(sessionId: string, rating: Rating | null, note: string | null): void;
  /** Una faccia scelta: il compagno risponde. */
  onRated(rating: Rating): void;
}

export class ReflectionCard {
  private readonly host: ReflectionHost;
  private element: HTMLElement | null = null;
  private sessionId: string | null = null;
  private box = { left: 0, top: 0, width: 0, height: 0 };

  constructor(host: ReflectionHost) {
    this.host = host;
  }

  get isShowing(): boolean { return this.element !== null; }

  contains(x: number, y: number): boolean {
    return this.element !== null && x >= this.box.left && x < this.box.left + this.box.width && y >= this.box.top && y < this.box.top + this.box.height;
  }

  ask(session: StudySession): void {
    this.dismiss();
    this.sessionId = session.id;
    const minutes = Math.trunc((session.seconds + 30) / 60);
    const subtitle = [session.subject, `${minutes} minuti`].filter((part): part is string => part !== undefined).join(" · ");
    const input = h("input", { type: "text", class: "text-field", placeholder: "Cosa hai fatto? (facoltativo)", "aria-label": "Cosa hai fatto", maxlength: NOTE_MAX * 2 });
    input.addEventListener("focus", () => this.host.onKeyboard(true));
    input.addEventListener("blur", () => this.host.onKeyboard(false));
    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter") { event.preventDefault(); this.close(true, null, input.value); }
      if (event.key === "Escape") { event.preventDefault(); this.close(false, null, ""); }
    });
    const faces = h("div", { class: "reflection-faces" });
    for (const rating of ["good", "soso", "poor"] as Rating[]) {
      faces.append(button("face-button", RATING_TITLE[rating], () => this.close(true, rating, input.value), faceIcon(rating, 44), h("span", {}, RATING_TITLE[rating])));
    }
    this.element = h("div", { class: "reflection", role: "group", "aria-label": "Com'è andata?" },
      h("div", { class: "dialog-title small" }, "Com'è andata?"),
      h("div", { class: "dialog-subtitle" }, subtitle),
      faces,
      input,
      h("div", { class: "dialog-buttons" },
        button("text-button", "Salta", () => this.close(false, null, ""), "Salta"),
        button("pill-action", "Fatto", () => this.close(true, null, input.value), "Fatto")),
    );
    this.host.container.append(this.element);
    this.place();
    requestAnimationFrame(() => this.element?.classList.add("visible"));
  }

  /** Accanto al compagno (a sinistra, o a destra se non c'è posto), senza coprirlo. */
  private place(): void {
    const element = this.element;
    if (!element) return;
    const width = element.offsetWidth, height = element.offsetHeight;
    const pet = this.host.petBox();
    const scene = this.host.scene();
    let left = pet.left - width - GAP_FROM_PET;
    if (left < EDGE) left = pet.left + pet.width + GAP_FROM_PET;
    left = Math.min(Math.max(left, EDGE), Math.max(scene.width - width - EDGE, EDGE));
    const top = Math.min(Math.max(pet.top + pet.height - height, EDGE), Math.max(scene.height - height - EDGE, EDGE));
    element.style.transform = `translate(${Math.round(left)}px, ${Math.round(top)}px)`;
    this.box = { left, top, width, height };
  }

  /** Chiude senza salvare (fine pausa, nuovo focus). */
  dismiss(): void {
    this.close(false, null, "", false);
  }

  private close(save: boolean, rating: Rating | null, note: string, notify = true): void {
    const element = this.element, id = this.sessionId;
    if (!element) return;
    this.element = null;
    this.sessionId = null;
    this.host.onKeyboard(false);
    element.classList.remove("visible");
    window.setTimeout(() => element.remove(), 200);
    this.host.onClosed();
    if (!notify || !save || id === null) return;
    this.host.onSave(id, rating, note);
    if (rating !== null) this.host.onRated(rating);
  }
}
