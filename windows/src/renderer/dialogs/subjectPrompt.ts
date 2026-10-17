// «Cosa studi adesso?»: la scheda che compare quando si avvia un focus, per scrivere la materia (o toccare una di quelle usate di
// recente). Si può anche saltare. (SubjectPrompt.swift)

import { subjectColor } from "../../core/colors.ts";
import { cleanSubject, SUBJECT_MAX } from "../../core/text.ts";
import { button, h, icon } from "../card/dom.ts";
import type { ModalHost } from "./modal.ts";

export type SubjectChoice = { kind: "start"; subject: string | null } | { kind: "cancel" } | { kind: "back" };

const CHIPS_PER_ROW = 3;
const MAX_CHIPS = 6;

export function openSubjectPrompt(host: ModalHost, options: {
  minutes: number;
  recent: readonly string[];
  lastNote: { subject: string | null; note: string } | null;
  onChoice(choice: SubjectChoice): void;
}): void {
  const decide = (choice: SubjectChoice) => (close: () => void): void => { close(); options.onChoice(choice); };
  host.open({
    label: "Cosa studi adesso?",
    offsetY: -60,
    onCancel: () => options.onChoice({ kind: "cancel" }),
    initialFocus: (content) => content.querySelector<HTMLElement>("input"),
    build(close) {
      const input = h("input", { type: "text", class: "text-field", placeholder: "La materia, per esempio Anatomia", "aria-label": "La materia", maxlength: SUBJECT_MAX * 2 });
      const start = (): void => decide({ kind: "start", subject: cleanSubject(input.value) })(close);
      input.addEventListener("keydown", (event) => { if (event.key === "Enter") { event.preventDefault(); start(); } });

      const recent = options.recent.slice(0, MAX_CHIPS);
      const rows: HTMLElement[] = [];
      for (let i = 0; i < recent.length; i += CHIPS_PER_ROW) {
        rows.push(h("div", { class: "chip-row" }, ...recent.slice(i, i + CHIPS_PER_ROW).map((name) => {
          const color = subjectColor(name);
          const chip = button("subject-chip", name, () => decide({ kind: "start", subject: cleanSubject(name) })(close), name);
          chip.style.setProperty("--subject", color);
          return chip;
        })));
      }
      const note = options.lastNote;
      return h("div", { class: "dialog" },
        h("div", { class: "dialog-title-row" },
          button("back", "Torna al menu", decide({ kind: "back" }).bind(null, close), icon("back", 20)),
          h("div", { class: "dialog-title" }, "Cosa studi adesso?")),
        h("div", { class: "dialog-subtitle" }, `Focus da ${options.minutes} minuti`),
        input,
        recent.length > 0 ? h("div", { class: "dialog-hint" }, "Tocca una materia recente per iniziare subito") : null,
        ...rows,
        note ? h("div", { class: "dialog-last" }, (note.subject !== null ? `L'ultima volta su ${note.subject}: ` : "L'ultima volta: ") + note.note) : null,
        h("div", { class: "dialog-buttons" },
          button("text-button", "Senza materia", () => decide({ kind: "start", subject: null })(close), "Senza materia"),
          button("pill-action", "Inizia", start, "Inizia")),
      );
    },
  });
}
