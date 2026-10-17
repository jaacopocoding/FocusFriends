// La scheda di benvenuto, alla prima apertura: come ti chiami e chi ti fa compagnia. (IntroCard.swift)

import { PETS } from "../../core/pets.ts";
import { NAME_MAX, cleanName } from "../../core/text.ts";
import { avatarCircle } from "../avatar.ts";
import { button, h } from "../card/dom.ts";
import type { ModalHost } from "./modal.ts";

export function openIntroCard(host: ModalHost, options: {
  currentPetId: string;
  urlOf(path: string): string;
  /** Il nome (o null) e il compagno scelto. Esc e «Salta» valgono «nessun nome», con il compagno che c'era. */
  onDone(name: string | null, petId: string): void;
}): void {
  let selected = options.currentPetId;
  const finish = (name: string | null, petId: string) => (close: () => void): void => { close(); options.onDone(name, petId); };
  host.open({
    label: "Benvenuto in FocusFriends",
    offsetY: -50,
    onCancel: () => options.onDone(null, options.currentPetId),
    initialFocus: (content) => content.querySelector<HTMLElement>("input"),
    build(close) {
      const input = h("input", { type: "text", class: "text-field", placeholder: "Il tuo nome", "aria-label": "Il tuo nome", maxlength: NAME_MAX * 2 });
      const start = (): void => finish(cleanName(input.value), selected)(close);
      input.addEventListener("keydown", (event) => { if (event.key === "Enter") { event.preventDefault(); start(); } });

      const row = h("div", { class: "companion-picker", role: "radiogroup", "aria-label": "Chi ti fa compagnia?" });
      const buttons = PETS.map((pet) => {
        const choice = button(`companion-choice${pet.id === selected ? " selected" : ""}`, pet.name, () => {
          selected = pet.id;
          buttons.forEach((b, i) => { b.classList.toggle("selected", PETS[i]!.id === selected); b.setAttribute("aria-checked", String(PETS[i]!.id === selected)); });
        }, avatarCircle(pet, 68, options.urlOf, "avatar-image choice-image"), h("span", { class: "choice-name" }, pet.name));
        choice.setAttribute("role", "radio");
        choice.setAttribute("aria-checked", String(pet.id === selected));
        return choice;
      });
      row.append(...buttons);

      return h("div", { class: "dialog wide" },
        h("div", { class: "dialog-title" }, "Ciao! Benvenuto in FocusFriends"),
        h("div", { class: "dialog-question" }, "Come ti chiami?"),
        input,
        h("div", { class: "dialog-question" }, "Chi ti fa compagnia?"),
        row,
        h("div", { class: "dialog-hint" }, "Puoi cambiarli quando vuoi dal menu."),
        h("div", { class: "dialog-buttons" },
          button("text-button", "Salta", () => finish(null, options.currentPetId)(close), "Salta"),
          button("pill-action big", "Iniziamo!", start, "Iniziamo!")),
      );
    },
  });
}
