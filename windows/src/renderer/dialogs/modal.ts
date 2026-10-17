// Una finestra di dialogo al centro dello schermo (la carta di «Cosa studi adesso?» e quella di benvenuto): sta dentro la finestra
// trasparente, che mentre c'è riceve tutti i clic e la tastiera. Un clic fuori non la chiude: si esce dai pulsanti o con Esc.

import { h } from "../card/dom.ts";

export interface ModalOptions {
  label: string;
  /** Costruisce il contenuto; `close` chiude la finestra (senza chiamare `onCancel`). */
  build(close: () => void): HTMLElement;
  /** Esc. */
  onCancel(): void;
  /** Quanto sta più in alto o in basso del centro, in pixel. */
  offsetY?: number;
  /** Cosa prende la tastiera all'inizio. */
  initialFocus?(content: HTMLElement): HTMLElement | null;
}

export class ModalHost {
  private readonly container: HTMLElement;
  private readonly onOpenChange: (open: boolean) => void;
  private backdrop: HTMLElement | null = null;
  private current: { element: HTMLElement; options: ModalOptions } | null = null;
  private readonly onKey = (event: KeyboardEvent): void => {
    if (event.key === "Escape" && this.current) { event.preventDefault(); const { options } = this.current; this.close(); options.onCancel(); }
  };

  constructor(container: HTMLElement, onOpenChange: (open: boolean) => void) {
    this.container = container;
    this.onOpenChange = onOpenChange;
  }

  get isOpen(): boolean { return this.current !== null; }
  get element(): HTMLElement | null { return this.current?.element ?? null; }

  open(options: ModalOptions): void {
    if (this.current) return;
    const content = options.build(() => this.close());
    const element = h("div", { class: "modal", role: "dialog", "aria-modal": "true", "aria-label": options.label }, content);
    element.style.setProperty("--offset", `${options.offsetY ?? 0}px`);
    this.backdrop = h("div", { class: "modal-backdrop" });
    this.container.append(this.backdrop, element);
    this.current = { element, options };
    window.addEventListener("keydown", this.onKey, true);
    this.onOpenChange(true);
    requestAnimationFrame(() => {
      element.classList.add("visible");
      (options.initialFocus?.(content) ?? content.querySelector<HTMLElement>("input, button"))?.focus({ preventScroll: true });
    });
  }

  close(): void {
    const current = this.current;
    if (!current) return;
    this.current = null;
    window.removeEventListener("keydown", this.onKey, true);
    this.backdrop?.remove();
    this.backdrop = null;
    current.element.classList.remove("visible");
    window.setTimeout(() => current.element.remove(), 160);
    this.onOpenChange(false);
  }
}
