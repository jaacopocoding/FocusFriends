// Piccoli aiuti per costruire la scheda: elementi HTML e SVG a partire da una descrizione, e le icone.

import { ICONS } from "./icons.generated.ts";
import type { IconName } from "./icons.generated.ts";

type Child = Node | string | null | undefined | false;
type Props = Record<string, string | number | boolean | null | undefined | ((event: Event) => void)>;

const SVG_NS = "http://www.w3.org/2000/svg";

function apply(element: Element, props: Props | undefined): void {
  if (!props) return;
  for (const [key, value] of Object.entries(props)) {
    if (value === undefined || value === null || value === false) continue;
    if (typeof value === "function") element.addEventListener(key.replace(/^on/, "").toLowerCase(), value);
    else if (key === "class") element.setAttribute("class", String(value));
    else if (value === true) element.setAttribute(key, "");
    else element.setAttribute(key, String(value));
  }
}

function append(element: Element, children: Child[]): void {
  for (const child of children) {
    if (child === null || child === undefined || child === false) continue;
    element.append(typeof child === "string" ? document.createTextNode(child) : child);
  }
}

/** Un elemento HTML: `h("div", { class: "x" }, "testo", altroElemento)`. */
export function h<K extends keyof HTMLElementTagNameMap>(tag: K, props?: Props, ...children: Child[]): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag);
  apply(element, props);
  append(element, children);
  return element;
}

/** Un elemento SVG. */
export function s<K extends keyof SVGElementTagNameMap>(tag: K, props?: Props, ...children: Child[]): SVGElementTagNameMap[K] {
  const element = document.createElementNS(SVG_NS, tag);
  apply(element, props);
  append(element, children);
  return element;
}

/** Un'icona (Lucide) grande `size` pixel, del colore del testo. */
export function icon(name: IconName, size = 16): SVGSVGElement {
  const svg = s("svg", {
    width: size, height: size, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 2,
    "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true", class: "icon",
  });
  svg.innerHTML = ICONS[name];
  return svg;
}

/** Un pulsante vero (tastiera e lettori di schermo funzionano da soli). */
export function button(className: string, label: string, onClick: () => void, ...children: Child[]): HTMLButtonElement {
  const element = h("button", { type: "button", class: className, "aria-label": label }, ...children);
  element.addEventListener("click", onClick);
  return element;
}
