// L'icona nell'area di notifica e il suo menu: mostra/nascondi, scelta del compagno, movimento, esci.

import { Menu, Tray, nativeImage } from "electron";
import type { NativeImage } from "electron";
import { join } from "node:path";
import { PETS, petInfo } from "../core/pets.ts";
import type { PetData } from "../core/pets.ts";

export interface TrayActions {
  isVisible(): boolean;
  toggleVisible(): void;
  currentPet(): string;
  choosePet(id: string): void;
  isMovementOn(): boolean;
  setMovement(on: boolean): void;
  quit(): void;
}

/** L'icona del compagno: la testa (`iconCrop`, con l'origine in basso) o, senza ritaglio, tutta l'immagine. */
export function iconFor(pet: PetData, assets: string): NativeImage {
  const image = nativeImage.createFromPath(join(assets, pet.iconImage));
  if (image.isEmpty()) return image;
  const { width, height } = image.getSize();
  const crop = pet.iconCrop;
  const cropped = crop
    ? image.crop({
        x: Math.round(crop.x * width), y: Math.round((1 - crop.y - crop.height) * height),
        width: Math.round(crop.width * width), height: Math.round(crop.height * height),
      })
    : image;
  const size = cropped.getSize();
  return cropped.resize(size.width >= size.height ? { width: 32 } : { height: 32 });
}

export function createTray(assets: string, actions: TrayActions): { refresh(): void; destroy(): void } {
  const tray = new Tray(iconFor(petInfo(actions.currentPet()), assets));
  tray.setToolTip("FocusFriends");

  const refresh = (): void => {
    const pet = petInfo(actions.currentPet());
    tray.setImage(iconFor(pet, assets));
    tray.setContextMenu(Menu.buildFromTemplate([
      { label: actions.isVisible() ? `Nascondi ${pet.name}` : `Mostra ${pet.name}`, click: () => actions.toggleVisible() },
      { type: "separator" },
      {
        label: "Compagno",
        submenu: PETS.map((p) => ({
          label: p.name, type: "radio" as const, checked: p.id === pet.id, click: () => actions.choosePet(p.id),
        })),
      },
      { label: "In movimento", type: "checkbox", checked: actions.isMovementOn(), click: (item) => actions.setMovement(item.checked) },
      { type: "separator" },
      { label: "Esci", click: () => actions.quit() },
    ]));
  };
  refresh();
  tray.on("click", () => actions.toggleVisible());
  return { refresh, destroy: () => tray.destroy() };
}
