// L'icona nell'area di notifica e il suo menu: mostra/nascondi, scelta del compagno, movimento, esci.

import { Menu, Tray, nativeImage } from "electron";
import type { MenuItemConstructorOptions, NativeImage } from "electron";
import { join } from "node:path";
import { PETS, petInfo } from "../core/pets.ts";
import type { PetData } from "../core/pets.ts";
import type { PomodoroSnapshot } from "../core/pomodoro.ts";
import type { TimerKind } from "../core/rules.ts";

export interface TrayActions {
  timer(): PomodoroSnapshot;
  /** I timer di serie e quelli personalizzati, in ordine crescente. */
  timers(kind: TimerKind): number[];
  startFocus(minutes: number): void;
  startBreak(minutes: number): void;
  togglePause(): void;
  addMinutes(): void;
  stopTimer(): void;
  discardFocus(): void;
  speak(): void;
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
    const timer = actions.timer();
    const running = timer.phase !== null;
    const pomofocus: MenuItemConstructorOptions[] = [
      ...actions.timers("focus").map((m) => ({ label: `Focus ${m} min`, click: () => actions.startFocus(m) })),
      { type: "separator" as const },
      ...actions.timers("rest").map((m) => ({
        label: `Pausa ${m} min`, type: "checkbox" as const, checked: timer.breakMinutes === m, click: () => actions.startBreak(m),
      })),
    ];
    if (running) {
      pomofocus.push({ type: "separator" });
      if (timer.phase === "focus") {
        pomofocus.push({ label: timer.isPaused ? "Riprendi" : "Ferma", click: () => actions.togglePause() });
      }
      pomofocus.push({ label: "Altri 5 minuti", click: () => actions.addMinutes() });
      pomofocus.push({ label: timer.phase === "focus" ? "Termina e salva" : "Salta la pausa", click: () => actions.stopTimer() });
      if (timer.phase === "focus") pomofocus.push({ label: "Elimina questo focus", click: () => actions.discardFocus() });
    }
    tray.setImage(iconFor(pet, assets));
    tray.setToolTip(running ? `FocusFriends — ${timer.label.toLowerCase()} ${timer.remainingText}` : "FocusFriends");
    tray.setContextMenu(Menu.buildFromTemplate([
      { label: `Fai parlare ${pet.name}`, click: () => actions.speak() },
      { type: "separator" },
      { label: "Pomofocus", submenu: pomofocus },
      { type: "separator" },
      { label: actions.isVisible() ? `Nascondi ${pet.name}` : `Mostra ${pet.name}`, click: () => actions.toggleVisible() },
      {
        label: "Personaggio",
        submenu: PETS.map((p) => ({
          label: p.name, type: "radio" as const, checked: p.id === pet.id, click: () => actions.choosePet(p.id),
        })),
      },
      { label: "In movimento", type: "checkbox", checked: actions.isMovementOn(), click: (item) => actions.setMovement(item.checked) },
      { type: "separator" },
      { label: "Esci da FocusFriends", click: () => actions.quit() },
    ]));
  };
  refresh();
  tray.on("click", () => actions.toggleVisible());
  return { refresh, destroy: () => tray.destroy() };
}
