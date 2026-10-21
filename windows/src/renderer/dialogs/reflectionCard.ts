// «Com'è andata?»: la scheda che compare a fine focus. Un tocco su una faccia salva e chiude; la riga «cosa hai fatto» è facoltativa.
// Non ruba la tastiera (a fine focus potresti stare scrivendo altrove) e non blocca niente: se la ignori la sessione resta com'è, e la
// scheda sparisce da sola a fine pausa. Se il focus era partito da una voce di «Da fare», c'è anche «Hai finito «…»?» con Fatta e Non ancora;
// con «Chiedi com'è andata» spento la scheda ha solo quella domanda. (ReflectionCard.swift)

import type { Rating, StudySession } from "../../core/log.ts";
import { NOTE_MAX } from "../../core/text.ts";
import { finishedQuestion } from "../../core/todo.ts";
import type { ToDoItem } from "../../core/todo.ts";
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
  /** La risposta a «Hai finito?»: `finished` vero per «Fatta», falso per «Non ancora». */
  onTodoAnswer(item: ToDoItem, finished: boolean): void;
}

export interface ReflectionOptions {
  /** La voce di «Da fare» da cui era partito il focus (ancora da fare), se c'è. */
  todo: ToDoItem | null;
  /** Le facce e la nota (se no, la scheda ha solo «Hai finito?»). */
  askHowItWent: boolean;
}

export class ReflectionCard {
  private readonly host: ReflectionHost;
  private element: HTMLElement | null = null;
  private sessionId: string | null = null;
  private todoBox: HTMLElement | null = null;
  private hasReflection = true;
  private box = { left: 0, top: 0, width: 0, height: 0 };

  constructor(host: ReflectionHost) {
    this.host = host;
  }

  get isShowing(): boolean { return this.element !== null; }

  contains(x: number, y: number): boolean {
    return this.element !== null && x >= this.box.left && x < this.box.left + this.box.width && y >= this.box.top && y < this.box.top + this.box.height;
  }

  ask(session: StudySession, options: ReflectionOptions = { todo: null, askHowItWent: true }): void {
    this.dismiss();
    if (!options.askHowItWent && options.todo === null) return;
    this.sessionId = session.id;
    this.hasReflection = options.askHowItWent;
    const minutes = Math.trunc((session.seconds + 30) / 60);
    const subtitle = [session.subject, `${minutes} minuti`].filter((part): part is string => part !== undefined).join(" · ");
    const children: Array<HTMLElement> = [
      h("div", { class: "dialog-title small" }, options.askHowItWent ? "Com'è andata?" : "Hai finito?"),
      h("div", { class: "dialog-subtitle" }, subtitle),
    ];
    if (options.todo !== null) {
      const item = options.todo;
      const box = h("div", { class: "reflection-todo", role: "group", "aria-label": "Hai finito?" },
        h("div", { class: "reflection-todo-question" }, finishedQuestion(item)),
        h("div", { class: "reflection-todo-buttons" },
          button("text-button", "Non ancora", () => this.answerTodo(item, false), "Non ancora"),
          button("pill-action", "Fatta", () => this.answerTodo(item, true), "Fatta")));
      this.todoBox = box;
      children.push(box);
    }
    if (options.askHowItWent) {
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
      children.push(faces, input, h("div", { class: "dialog-buttons" },
        button("text-button", "Salta", () => this.close(false, null, ""), "Salta"),
        button("pill-action", "Fatto", () => this.close(true, null, input.value), "Fatto")));
    }
    this.element = h("div", { class: "reflection", role: "group", "aria-label": options.askHowItWent ? "Com'è andata?" : "Hai finito?" }, ...children);
    this.host.container.append(this.element);
    this.place();
    requestAnimationFrame(() => this.element?.classList.add("visible"));
  }

  /** La risposta a «Hai finito?»: si comunica subito e il riquadro sparisce; se non c'è altro, la scheda si chiude. */
  private answerTodo(item: ToDoItem, finished: boolean): void {
    const box = this.todoBox;
    if (box === null) return;
    this.todoBox = null;
    this.host.onTodoAnswer(item, finished);
    if (!this.hasReflection) { this.close(false, null, "", false); return; }
    box.remove();
    this.place();
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
    this.todoBox = null;
    this.host.onKeyboard(false);
    element.classList.remove("visible");
    window.setTimeout(() => element.remove(), 200);
    this.host.onClosed();
    if (!notify || !save || id === null) return;
    this.host.onSave(id, rating, note);
    if (rating !== null) this.host.onRated(rating);
  }
}
