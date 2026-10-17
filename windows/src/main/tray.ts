// L'icona nell'area di notifica e il suo menu completo (quello che sul Mac è il menu della barra): clic sull'icona = la scheda,
// tasto destro = questo menu.

import { Menu, Tray, nativeImage, shell } from "electron";
import type { MenuItemConstructorOptions, NativeImage, Rectangle } from "electron";
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { PETS, petInfo } from "../core/pets.ts";
import type { PetData } from "../core/pets.ts";
import { phrasesFileName } from "../core/phrases.ts";
import type { Profile } from "../core/profile.ts";
import { AMBIENT_TITLES, AMBIENT_SOUNDS, CHATTINESS, CHATTINESS_TITLES, FOCUSES_PER_CYCLE, VOLUME_STEPS, nearestStep } from "../core/rules.ts";
import type { Settings } from "../core/settings.ts";
import { musicLabel } from "../core/card.ts";
import type { CardService } from "./card.ts";
import type { TimerService } from "./timer.ts";

export interface TrayDeps {
  assets: string;
  data: string;
  settings: Settings;
  profile: Profile;
  card: CardService;
  timer: () => TimerService;
  isVisible(): boolean;
  setVisible(visible: boolean): void;
  speak(): void;
  /** «Focus N min»: prima si chiede la materia («Cosa studi adesso?»), poi parte. */
  askFocus(minutes: number): void;
  /** Un clic sull'icona: apre o chiude la scheda sotto (sopra) di lei. */
  toggleCard(bounds: Rectangle): void;
  /** «Personalizza…»: la scheda aperta sulla pagina dei timer. */
  openTimers(): void;
  showStats(): void;
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

/** «Modifica le frasi…»: parte dal file incluso (se non c'è già il tuo) e lo apre nell'editor. */
async function openPhrasesFile(deps: TrayDeps): Promise<void> {
  const name = phrasesFileName(deps.settings.pet);
  const file = join(deps.data, name);
  if (!existsSync(file)) {
    const bundled = join(deps.assets, name);
    mkdirSync(deps.data, { recursive: true });
    if (existsSync(bundled)) copyFileSync(bundled, file);
  }
  if (existsSync(file)) await shell.openPath(file);
}

export function createTray(deps: TrayDeps): { refresh(): void; popUp(): void; bounds(): Rectangle; destroy(): void } {
  const { settings, profile, card } = deps;
  const tray = new Tray(iconFor(petInfo(settings.pet), deps.assets));
  let menu: Menu;

  const timerItems = (): MenuItemConstructorOptions[] => {
    const timer = deps.timer().snapshot();
    const running = timer.phase !== null;
    const items: MenuItemConstructorOptions[] = [
      ...settings.allTimers("focus").map((m): MenuItemConstructorOptions => ({ label: `Focus ${m} min`, click: () => deps.askFocus(m) })),
      { type: "separator" },
      ...settings.allTimers("rest").map((m): MenuItemConstructorOptions => ({
        label: `Pausa ${m} min`, type: "checkbox", checked: timer.breakMinutes === m, click: () => card.command({ name: "startBreak", minutes: m }),
      })),
      { type: "separator" },
      { label: "Personalizza…", click: () => deps.openTimers() },
    ];
    const custom: Array<["focus" | "rest", number]> = [
      ...settings.customTimers("focus").map((m): ["focus", number] => ["focus", m]),
      ...settings.customTimers("rest").map((m): ["rest", number] => ["rest", m]),
    ];
    if (custom.length > 0) {
      items.push({
        label: "Rimuovi un timer personalizzato",
        submenu: custom.map(([kind, m]) => ({
          label: `${kind === "focus" ? "Focus" : "Pausa"} ${m} min`, click: () => card.command({ name: "removeTimer", kind, minutes: m }),
        })),
      });
    }
    items.push({ type: "separator" });
    if (running && timer.phase === "focus") {
      items.push({ label: timer.isPaused ? "Riprendi" : "Ferma", click: () => card.command({ name: "togglePause" }) });
      items.push({ label: "Altri 5 minuti", click: () => card.command({ name: "addMinutes" }) });
      items.push({ label: "Elimina questo focus", click: () => card.command({ name: "discardFocus" }) });
    } else if (running) {
      items.push({ label: "Altri 5 minuti", click: () => card.command({ name: "addMinutes" }) });
    }
    items.push({
      label: running ? `Ferma timer (${timer.remainingText})` : "Ferma timer", enabled: running, click: () => card.command({ name: "stopTimer" }),
    });
    return items;
  };

  const volumeItems = (current: number, set: (value: number) => void): MenuItemConstructorOptions[] =>
    VOLUME_STEPS.map((step) => ({
      label: `Volume ${Math.round(step * 100)}%`, type: "radio" as const, checked: nearestStep(current) === step, click: () => set(step),
    }));

  const build = (): Menu => {
    const pet = petInfo(settings.pet);
    const timer = deps.timer().snapshot();
    const visible = deps.isVisible();
    return Menu.buildFromTemplate([
      { label: `Fai parlare ${pet.name}`, click: () => deps.speak() },
      { type: "separator" },
      { label: timer.phase === null ? "Pomofocus" : `Pomofocus · ${timer.remainingText}`, submenu: timerItems() },
      { label: `${profile.statsTitle}…`, click: () => deps.showStats() },
      {
        label: "Suono ambiente",
        submenu: [
          ...AMBIENT_SOUNDS.map((sound): MenuItemConstructorOptions => ({
            label: AMBIENT_TITLES[sound], type: "radio", checked: settings.ambientSound === sound, click: () => card.setAmbient(sound),
          })),
          { type: "separator" },
          ...volumeItems(settings.ambientVolume, (value) => { settings.ambientVolume = value; }),
        ],
      },
      {
        label: "Musica",
        submenu: [
          { label: "Nessuna", type: "radio", checked: settings.musicSource === "off", click: () => { void card.selectMusic("off"); } },
          { label: "Brani inclusi", type: "radio", checked: settings.musicSource === "bundled", click: () => { void card.selectMusic("bundled"); } },
          {
            label: musicLabel("folder", settings.musicFolder).replace("Cartella:", "La mia cartella:"), type: "radio",
            checked: settings.musicSource === "folder", click: () => { void card.selectMusic("folder"); },
          },
          { label: "Scegli la cartella…", click: () => { void card.chooseMusicFolder(); } },
          { type: "separator" },
          ...volumeItems(settings.musicVolume, (value) => { settings.musicVolume = value; }),
        ],
      },
      {
        label: `Frequenza delle frasi · ${CHATTINESS_TITLES[settings.phraseFrequency]}`,
        submenu: CHATTINESS.map((level): MenuItemConstructorOptions => ({
          label: CHATTINESS_TITLES[level], type: "radio", checked: settings.phraseFrequency === level, click: () => { settings.phraseFrequency = level; },
        })),
      },
      {
        label: `Personaggio · ${pet.name}`,
        submenu: PETS.map((p): MenuItemConstructorOptions => {
          const unlocked = profile.isCompanionUnlocked(p.id);
          return {
            label: p.name, type: "radio", checked: p.id === pet.id, enabled: unlocked,
            click: () => card.command({ name: "selectPet", id: p.id }),
          };
        }),
      },
      {
        label: pet.walks ? `Movimento · ${settings.movement ? "In movimento" : "Fermo"}` : "Movimento",
        enabled: pet.walks,
        submenu: [
          { label: "In movimento", type: "radio", checked: settings.movement, click: () => { settings.movement = true; } },
          { label: "Fermo", type: "radio", checked: !settings.movement, click: () => { settings.movement = false; } },
        ],
      },
      { type: "separator" },
      { label: "Chiedi com'è andata", type: "checkbox", checked: settings.askHowItWent, click: (item) => { settings.askHowItWent = item.checked; } },
      {
        label: `Pausa lunga dopo ${FOCUSES_PER_CYCLE} focus`, type: "checkbox", checked: settings.longBreakEnabled,
        click: (item) => { settings.longBreakEnabled = item.checked; },
      },
      { label: "Modifica le frasi…", click: () => { void openPhrasesFile(deps); } },
      { type: "separator" },
      { label: visible ? `Nascondi ${pet.name}` : `Mostra ${pet.name}`, click: () => deps.setVisible(!visible) },
      { label: "Esci da FocusFriends", click: () => deps.quit() },
    ]);
  };

  /** Icona e suggerimento (a ogni cambio); il menu si compone solo quando si apre. */
  let lastLook = "";
  const refresh = (): void => {
    const pet = petInfo(settings.pet);
    const timer = deps.timer().snapshot();
    const tooltip = timer.phase !== null ? `FocusFriends — ${timer.label.toLowerCase()} ${timer.remainingText}` : "FocusFriends";
    const look = `${pet.id}|${tooltip}`;
    if (look === lastLook) return;
    if (!lastLook.startsWith(`${pet.id}|`)) tray.setImage(iconFor(pet, deps.assets));
    lastLook = look;
    tray.setToolTip(tooltip);
  };
  const popUp = (): void => {
    menu = build();
    tray.popUpContextMenu(menu);
  };
  refresh();
  tray.on("click", (_event, bounds) => deps.toggleCard(bounds));
  tray.on("right-click", popUp);
  return { refresh, popUp, bounds: () => tray.getBounds(), destroy: () => tray.destroy() };
}
