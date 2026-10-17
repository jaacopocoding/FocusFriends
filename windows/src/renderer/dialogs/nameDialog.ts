// «Il tuo nome»: cambia il nome con cui si personalizzano i titoli («Le statistiche di …»). Vuoto lo toglie. (editName in MenuController.swift)

import { NAME_MAX, cleanName } from "../../core/text.ts";
import { button, h } from "../card/dom.ts";
import type { ModalHost } from "./modal.ts";

export function openNameDialog(host: ModalHost, options: { current: string | null; onSave(name: string | null): void }): void {
  host.open({
    label: "Il tuo nome",
    offsetY: -40,
    onCancel: () => undefined,
    initialFocus: (content) => content.querySelector<HTMLElement>("input"),
    build(close) {
      const input = h("input", { type: "text", class: "text-field", placeholder: "Il tuo nome", "aria-label": "Il tuo nome", maxlength: NAME_MAX * 2 });
      input.value = options.current ?? "";
      const save = (): void => { close(); options.onSave(cleanName(input.value)); };
      input.addEventListener("keydown", (event) => { if (event.key === "Enter") { event.preventDefault(); save(); } });
      return h("div", { class: "dialog" },
        h("div", { class: "dialog-title" }, "Il tuo nome"),
        h("div", { class: "dialog-subtitle" }, "Compare nei titoli, per esempio «Le statistiche di …». Lascia vuoto per toglierlo."),
        input,
        h("div", { class: "dialog-buttons" },
          button("text-button", "Annulla", close, "Annulla"),
          button("pill-action", "Salva", save, "Salva")));
    },
  });
}
