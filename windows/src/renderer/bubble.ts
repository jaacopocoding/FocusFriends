// Il fumetto: l'immagine `bubble.png` scalata sul testo, con la frase centrata nell'ovale (BubbleView in SpeechBubble.swift).

import type { Size } from "../core/pets.ts";

/** L'ovale occupa l'83,7% dell'altezza dell'immagine, il resto è la codina. */
export const ELLIPSE_HEIGHT_FRACTION = 0.837;
const ELLIPSE_ASPECT = 1.63;                  // larghezza / altezza dell'ovale
/** Posizione orizzontale della punta della codina, come frazione della larghezza. */
export const TAIL_TIP_FRACTION = 0.825;
const TEXT_WIDTH_FRACTION = 0.65;
const TEXT_HEIGHT_FRACTION = 0.55;

/** Quanto sta il testo, a capo a una certa larghezza: la riga più larga e l'altezza (si misura con la pagina). */
function measure(text: string, width: number): Size {
  const probe = document.getElementById("measure")!;
  probe.style.maxWidth = `${width}px`;
  probe.textContent = text;
  const rect = probe.getBoundingClientRect();
  return { width: Math.ceil(rect.width), height: Math.ceil(rect.height) };
}

/** Dimensione del fumetto per questa frase: prova varie larghezze del testo e sceglie quella che dà un ovale con proporzioni più simili a quelle dell'immagine. */
export function bubbleSize(text: string): Size {
  let best: { width: number; height: number; score: number } | null = null;
  for (let wrap = 110; wrap <= 260; wrap += 10) {
    const t = measure(text, wrap);
    const ew = Math.max(t.width / TEXT_WIDTH_FRACTION, 130);
    const eh = Math.max(t.height / TEXT_HEIGHT_FRACTION, (ew / ELLIPSE_ASPECT) * 0.6);
    // Più l'ovale è vicino alle proporzioni dell'immagine, meno viene deformata.
    const score = Math.abs(Math.log(ew / eh / ELLIPSE_ASPECT)) + (ew * eh) / 400_000;
    if (best === null || score < best.score) best = { width: ew, height: eh, score };
  }
  const ellipse = best ?? { width: 180, height: 110 };
  return { width: Math.ceil(ellipse.width), height: Math.ceil(ellipse.height / ELLIPSE_HEIGHT_FRACTION) };
}

/** Crea l'elemento del fumetto per questa frase (già della dimensione giusta). */
export function createBubble(text: string): { element: HTMLDivElement; size: Size } {
  const size = bubbleSize(text);
  const element = document.createElement("div");
  element.className = "bubble";
  element.style.width = `${size.width}px`;
  element.style.height = `${size.height}px`;
  const label = document.createElement("div");
  label.className = "text";
  label.textContent = text;
  // Il testo sta centrato nell'ovale, cioè nella parte alta del fumetto.
  label.style.top = `${(size.height * ELLIPSE_HEIGHT_FRACTION) / 2}px`;
  element.append(label);
  return { element, size };
}
