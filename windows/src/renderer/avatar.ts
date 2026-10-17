// La testa di un compagno ritagliata dall'immagine e centrata sul muso, dentro un cerchio (come l'avatar della scheda del Mac).

import type { PetData } from "../core/pets.ts";

/** Un cerchio grande `size` pixel con la testa del compagno (si riempie quando l'immagine è caricata). */
export function avatarCircle(pet: PetData, size: number, urlOf: (path: string) => string, className = "avatar-image"): HTMLSpanElement {
  const circle = document.createElement("span");
  circle.className = className;
  circle.style.width = `${size}px`;
  circle.style.height = `${size}px`;
  const probe = new Image();
  probe.onload = () => {
    const crop = pet.iconCrop ?? { x: 0, y: 0, width: 1, height: 1 };
    const cropHeight = crop.height * probe.naturalHeight;
    const scale = (size / cropHeight) * 1.12;
    const shownWidth = crop.width * probe.naturalWidth * scale, shownHeight = cropHeight * scale;
    const fullWidth = probe.naturalWidth * scale, fullHeight = probe.naturalHeight * scale;
    circle.style.backgroundImage = `url("${urlOf(pet.iconImage)}")`;
    circle.style.backgroundSize = `${fullWidth}px ${fullHeight}px`;
    const x = size / 2 - shownWidth * pet.iconFocus - crop.x * fullWidth;
    const y = size / 2 - shownHeight * 0.48 - (1 - crop.y - crop.height) * fullHeight;
    circle.style.backgroundPosition = `${x}px ${y}px`;
  };
  probe.src = urlOf(pet.iconImage);
  return circle;
}
