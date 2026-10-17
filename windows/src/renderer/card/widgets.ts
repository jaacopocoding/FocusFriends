// I disegni della scheda: il quadrante da girare, il pomodoro con l'arco, le tre facce, i puntini del ciclo, il foglietto delle note.

import type { Rating } from "../../core/log.ts";
import { dialFilledFraction, dialMinutes } from "../../core/rules.ts";
import { button, h, s } from "./dom.ts";

// I colori sono quelli di PaperUI.swift e FocusScreenViews.swift.
export const INK = "rgb(41, 26, 15)";
export const INK_LIGHT = "rgb(102, 77, 51)";
export const ACCENT = "rgb(217, 120, 56)";
export const PAPER_EDGE = "rgba(140, 102, 64, 0.45)";
const TRACK_FOCUS = "rgb(232, 216, 190)";
const DIAL_FACE = "rgb(255, 253, 240)";
const LEAF = "rgb(122, 154, 90)";
const TOMATO = "rgb(224, 116, 66)";
const TOMATO_LIGHT = "rgb(236, 138, 86)";
export const REST_GREEN = "rgb(122, 154, 90)";

const RATING_COLOR: Record<Rating, string> = {
  good: "rgb(133, 179, 115)", soso: "rgb(230, 186, 77)", poor: "rgb(214, 133, 138)",
};
export const RATING_TITLE: Record<Rating, string> = { good: "Bene", soso: "Così così", poor: "Fatica" };

/** Il punto sul cerchio di raggio `r` a questa frazione di giro (da mezzogiorno, in senso orario). */
function onCircle(cx: number, cy: number, r: number, fraction: number): [number, number] {
  const angle = -Math.PI / 2 + fraction * 2 * Math.PI;
  return [cx + r * Math.cos(angle), cy + r * Math.sin(angle)];
}

/** L'arco di un cerchio che copre `fraction` del giro (null se è troppo poco per vedersi). */
function arcPath(cx: number, cy: number, r: number, fraction: number): string | null {
  if (fraction <= 0.002) return null;
  if (fraction >= 0.999) {
    return `M ${cx} ${cy - r} A ${r} ${r} 0 1 1 ${cx - 0.01} ${cy - r}`;
  }
  const [x, y] = onCircle(cx, cy, r, fraction);
  return `M ${cx} ${cy - r} A ${r} ${r} 0 ${fraction > 0.5 ? 1 : 0} 1 ${x} ${y}`;
}

// ---- le facce di «Com'è andata?»

/** Una faccia disegnata a mano: un sorriso, una linea, una smorfia con gli occhi chiusi. */
export function faceIcon(rating: Rating, size: number, emphasized = false): SVGSVGElement {
  const r = 50, line = Math.max(1.2, r * 0.11) * 1.0;
  const eyeY = -r * 0.22, eyeDX = r * 0.36;
  const svg = s("svg", { width: size, height: size, viewBox: "-52 -52 104 104", "aria-hidden": "true", class: "face" });
  svg.append(s("circle", { r: r - line / 2, fill: RATING_COLOR[rating], stroke: INK, "stroke-opacity": emphasized ? 1 : 0.8, "stroke-width": line }));
  for (const dx of [-eyeDX, eyeDX]) {
    if (rating === "poor") {
      svg.append(s("line", { x1: dx - r * 0.15, y1: eyeY, x2: dx + r * 0.15, y2: eyeY, stroke: INK, "stroke-width": line, "stroke-linecap": "round" }));
    } else {
      svg.append(s("circle", { cx: dx, cy: eyeY, r: r * 0.085, fill: INK }));
    }
  }
  let mouth: string;
  if (rating === "good") mouth = `M ${-r * 0.42} ${r * 0.22} C ${-r * 0.25} ${r * 0.62} ${r * 0.25} ${r * 0.62} ${r * 0.42} ${r * 0.22}`;
  else if (rating === "soso") mouth = `M ${-r * 0.34} ${r * 0.38} L ${r * 0.34} ${r * 0.38}`;
  else mouth = `M ${-r * 0.34} ${r * 0.5} C ${-r * 0.18} ${r * 0.28} ${r * 0.18} ${r * 0.28} ${r * 0.34} ${r * 0.5}`;
  svg.append(s("path", { d: mouth, fill: "none", stroke: INK, "stroke-width": line, "stroke-linecap": "round" }));
  return svg;
}

// ---- il quadrante da girare

export interface Dial {
  element: SVGSVGElement;
  /** Aggiorna i minuti, il giro intero e il passo (cambiando focus/pausa). */
  update(minutes: number, maxMinutes: number, step: number, hardMax: number): void;
}

/** Il quadrante del timer: un pomodoro da girare. Si trascina il pallino (o si usa la rotella) per scegliere i minuti. */
export function createDial(onChange: (minutes: number) => void): Dial {
  const size = 176;
  const cx = size / 2, cy = size / 2 + 4;
  const outer = size / 2 - 14, ring = outer - 10;
  let minutes = 50, maxMinutes = 120, step = 5, hardMax = 180;

  const svg = s("svg", {
    width: size, height: size, viewBox: `0 0 ${size} ${size}`, class: "dial", role: "slider", tabindex: 0,
    "aria-label": "Minuti del timer", "aria-valuemin": 1,
  });
  // Il picciolo e le foglie in cima, come il logo.
  const top = cy - outer;
  for (const sign of [-1, 1]) {
    svg.append(s("path", {
      d: `M ${cx} ${top + 3} C ${cx + sign * 6} ${top - 12} ${cx + sign * 16} ${top - 12} ${cx + sign * 20} ${top - 3} C ${cx + sign * 16} ${top + 6} ${cx + sign * 6} ${top + 6} ${cx} ${top + 3} Z`,
      fill: "rgb(122, 153, 89)", stroke: INK, "stroke-width": 1.2,
    }));
  }
  svg.append(s("rect", { x: cx - 2.5, y: top - 14, width: 5, height: 14, rx: 2, fill: "rgb(122, 153, 89)", stroke: INK, "stroke-width": 1.2 }));
  svg.append(s("circle", { cx, cy, r: outer, fill: DIAL_FACE, stroke: INK, "stroke-width": 2 }));
  svg.append(s("circle", { cx, cy, r: ring, fill: "none", stroke: "rgba(140, 102, 64, 0.13)", "stroke-width": 12 }));
  const arc = s("path", { fill: "none", stroke: ACCENT, "stroke-width": 12, "stroke-linecap": "round" });
  const knob = s("circle", { r: 9, fill: DIAL_FACE, stroke: ACCENT, "stroke-width": 3 });
  const value = s("text", { x: cx, y: cy - 6, "text-anchor": "middle", "dominant-baseline": "central", class: "dial-minutes" });
  const unit = s("text", { x: cx, y: cy + 26, "text-anchor": "middle", "dominant-baseline": "central", class: "dial-unit" }, "minuti");
  svg.append(arc, knob, value, unit);

  const draw = (): void => {
    const fraction = dialFilledFraction(minutes, maxMinutes);
    const path = arcPath(cx, cy, ring, fraction);
    if (path) arc.setAttribute("d", path); else arc.removeAttribute("d");
    const [kx, ky] = onCircle(cx, cy, ring, fraction);
    knob.setAttribute("cx", String(kx));
    knob.setAttribute("cy", String(ky));
    value.textContent = String(minutes);
    svg.setAttribute("aria-valuenow", String(minutes));
    svg.setAttribute("aria-valuemax", String(hardMax));
    svg.setAttribute("aria-valuetext", `${minutes} minuti`);
  };
  const change = (next: number): void => {
    const clamped = Math.min(Math.max(next, 1), hardMax);
    if (clamped === minutes) return;
    minutes = clamped;
    draw();
    onChange(clamped);
  };
  const fromPointer = (event: PointerEvent): void => {
    const box = svg.getBoundingClientRect();
    const dx = event.clientX - (box.left + box.width / 2), dy = event.clientY - (box.top + box.height / 2 + 4);
    if (Math.hypot(dx, dy) <= 16) return;
    let fraction = Math.atan2(dx, -dy) / (2 * Math.PI);
    if (fraction < 0) fraction += 1;
    change(dialMinutes(fraction, minutes, maxMinutes, step));
  };
  svg.addEventListener("pointerdown", (event) => { svg.setPointerCapture(event.pointerId); fromPointer(event); });
  svg.addEventListener("pointermove", (event) => { if (svg.hasPointerCapture(event.pointerId)) fromPointer(event); });
  // La rotella (o due dita sul trackpad) aggiunge o toglie un minuto alla volta; da tastiera frecce e tasti pagina.
  svg.addEventListener("wheel", (event) => {
    if (Math.abs(event.deltaY) < 1) return;
    event.preventDefault();
    change(minutes + (event.deltaY < 0 ? 1 : -1));
  }, { passive: false });
  svg.addEventListener("keydown", (event) => {
    const delta = event.key === "ArrowUp" || event.key === "ArrowRight" ? 1 : event.key === "ArrowDown" || event.key === "ArrowLeft" ? -1
      : event.key === "PageUp" ? step : event.key === "PageDown" ? -step : 0;
    if (delta === 0) return;
    event.preventDefault();
    change(minutes + delta);
  });
  return {
    element: svg,
    update(nextMinutes, nextMax, nextStep, nextHardMax) {
      minutes = nextMinutes; maxMinutes = nextMax; step = nextStep; hardMax = nextHardMax;
      draw();
    },
  };
}

// ---- il pomodoro del focus e della pausa

export interface Tomato {
  element: SVGSVGElement;
  update(progress: number, big: string, small: string): void;
}

/** Il pomodoro con il quadrante: l'arco dice quanta parte della fase è passata, al centro il tempo che manca. */
export function createTomato(ring: string): Tomato {
  const svg = s("svg", { width: 300, height: 218, viewBox: "-150 -116 300 218", class: "tomato", role: "img" });
  const group = s("g", { transform: "translate(0 0) scale(0.935)" });
  group.append(
    s("ellipse", { cx: 0, cy: 4, rx: 120, ry: 100, fill: TOMATO, stroke: INK, "stroke-width": 2 }),
    s("ellipse", { cx: -6, cy: -12, rx: 102, ry: 72, fill: TOMATO_LIGHT }),
  );
  const leaves = [[-44, -84, -16, -100, -2, -84], [44, -84, 16, -100, 2, -84], [-10, -86, 0, -118, 10, -86]] as const;
  for (const [x1, y1, x2, y2, x3, y3] of leaves) {
    group.append(s("path", { d: `M ${x1} ${y1} L ${x2} ${y2} L ${x3} ${y3} Z`, fill: LEAF, stroke: INK, "stroke-width": 1.6, "stroke-linejoin": "round" }));
  }
  const r = 62, centerY = 6;
  group.append(
    s("circle", { cx: 0, cy: centerY, r: r + 12, fill: DIAL_FACE, stroke: INK, "stroke-width": 2 }),
    s("circle", { cx: 0, cy: centerY, r, fill: "none", stroke: TRACK_FOCUS, "stroke-width": 9 }),
  );
  const arc = s("path", { fill: "none", stroke: ring, "stroke-width": 9, "stroke-linecap": "round" });
  const knob = s("circle", { r: 7, fill: DIAL_FACE, stroke: ring, "stroke-width": 3 });
  const big = s("text", { x: 0, y: -6, "text-anchor": "middle", "dominant-baseline": "central", class: "tomato-big" });
  const small = s("text", { x: 0, y: 32, "text-anchor": "middle", "dominant-baseline": "central", class: "tomato-small" });
  group.append(arc, knob, big, small);
  svg.append(group);
  return {
    element: svg,
    update(progress, bigText, smallText) {
      const fraction = Math.min(Math.max(progress, 0), 1);
      const path = arcPath(0, centerY, r, fraction);
      if (path) arc.setAttribute("d", path); else arc.removeAttribute("d");
      const [kx, ky] = onCircle(0, centerY, r, fraction);
      knob.setAttribute("cx", String(kx));
      knob.setAttribute("cy", String(ky));
      big.textContent = bigText;
      small.textContent = smallText;
      svg.setAttribute("aria-label", `${bigText} ${smallText}`);
    },
  };
}

// ---- i puntini del ciclo

/** I quattro puntini del ciclo dei focus, con la scritta accanto («Focus 2 di 4»): i fatti pieni, il corrente con il contorno. */
export function cycleDots(done: number, highlightsNext: boolean, text: string): HTMLElement {
  const row = h("div", { class: "cycle", role: "img", "aria-label": text });
  for (let i = 0; i < 4; i += 1) {
    const state = i < done ? "done" : highlightsNext && i === done ? "current" : "todo";
    row.append(h("span", { class: `dot ${state}` }));
  }
  row.append(h("span", { class: "cycle-text" }, text));
  return row;
}

// ---- il foglietto delle note

export const VISIBLE_NOTES = 4;

/** Le note scritte finora e, in fondo, la riga per scriverne un'altra. */
export function createPostIt(notes: string[], draft: string, onSubmit: (text: string) => void): { element: HTMLElement; input: HTMLInputElement } {
  const older = Math.max(notes.length - VISIBLE_NOTES, 0);
  const input = h("input", { type: "text", class: "postit-input", placeholder: "scrivi una nota…", "aria-label": "Scrivi una nota", maxlength: 160 });
  input.value = draft;
  const submit = (): void => {
    const text = input.value;
    input.value = "";
    if (text.trim() !== "") onSubmit(text);
  };
  input.addEventListener("keydown", (event) => { if (event.key === "Enter") { event.preventDefault(); submit(); } });
  const element = h("div", { class: "postit", role: "group", "aria-label": "Note del focus" },
    h("div", { class: "postit-title" }, "Note", older > 0 ? h("span", { class: "postit-more" }, `+${older} sopra`) : null),
    ...notes.slice(-VISIBLE_NOTES).map((note) => h("div", { class: "postit-note" }, `•  ${note}`)),
    h("div", { class: "postit-row" }, h("span", { class: "postit-plus" }, "+"), input),
  );
  return { element, input };
}

// ---- il pulsante «adesivo»

export function sticker(className: string, label: string, onClick: () => void, ...children: (Node | string)[]): HTMLButtonElement {
  return button(`sticker ${className}`, label, onClick, ...children);
}
