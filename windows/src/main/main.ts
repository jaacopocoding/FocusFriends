// Il processo principale: la finestra trasparente, l'area di notifica, i file.

import { app, BrowserWindow, ipcMain, screen } from "electron";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { CHANNEL } from "../shared/api.ts";
import type { SettingsSnapshot } from "../shared/api.ts";
import { PhraseDeck, loadPhrases } from "../core/phrases.ts";
import { petInfo } from "../core/pets.ts";
import { Settings } from "../core/settings.ts";
import { assetsDirectory, dataDirectory, rendererDirectory, resourcesDirectory } from "./paths.ts";
import { createOverlay, fitToWorkArea, primaryDisplay } from "./overlay.ts";
import { handleScheme, registerScheme } from "./protocol.ts";
import { startTimer } from "./timer.ts";
import type { TimerService } from "./timer.ts";
import { createTray } from "./tray.ts";

registerScheme();

let overlay: BrowserWindow | null = null;
let visible = true;

function snapshot(settings: Settings): SettingsSnapshot {
  return { pet: settings.pet, movement: settings.movement, phraseFrequency: settings.phraseFrequency };
}

async function start(): Promise<void> {
  app.dock?.hide();
  const assets = assetsDirectory(app);
  const data = dataDirectory(app);
  mkdirSync(data, { recursive: true });
  handleScheme({ assets, renderer: rendererDirectory(app), resources: resourcesDirectory(app) });

  const settings = new Settings(data);
  const decks = new Map<string, PhraseDeck>();
  const win = createOverlay(primaryDisplay(), app.getAppPath());
  overlay = win;

  // Finché la pagina non è pronta i messaggi si tengono da parte (e partono nell'ordine in cui sono nati).
  let pageReady = false;
  const waiting: Array<[string, unknown]> = [];
  const send = (channel: string, payload?: unknown): void => {
    if (win.isDestroyed()) return;
    if (!pageReady) waiting.push([channel, payload]); else win.webContents.send(channel, payload);
  };
  ipcMain.on(CHANNEL.rendererReady, () => {
    pageReady = true;
    for (const [channel, payload] of waiting.splice(0)) win.webContents.send(channel, payload);
  });

  settings.addObserver(() => send(CHANNEL.settingsChanged, snapshot(settings)));

  ipcMain.handle(CHANNEL.getSettings, () => snapshot(settings));
  const interactions: string[] = [];
  ipcMain.on(CHANNEL.setInteractive, (_event, interactive: unknown) => {
    if (typeof interactive !== "boolean" || win.isDestroyed()) return;
    win.setIgnoreMouseEvents(!interactive, { forward: true });
    interactions.push(interactive ? "clic-acceso" : "clic-spento");
  });
  ipcMain.handle(CHANNEL.nextPhrase, (_event, petId: unknown) => {
    const id = typeof petId === "string" ? petId : settings.pet;
    // Il file si rilegge a ogni frase: le modifiche valgono subito.
    const phrases = loadPhrases(id, { userDirectory: data, bundledDirectory: assets });
    let deck = decks.get(id);
    if (!deck) { deck = new PhraseDeck(); decks.set(id, deck); }
    return deck.draw(phrases) ?? petInfo(id).fallbackQuote;
  });

  // Il timer e il menu dell'area di notifica si conoscono a vicenda: il primo nasce prima, il secondo gli si aggancia.
  let tray: ReturnType<typeof createTray> | null = null;
  const service: TimerService = startTimer({ directory: data, settings, send, onChange: () => tray?.refresh() });
  tray = createTray(assets, {
    timer: () => service.snapshot(),
    timers: (kind) => settings.allTimers(kind),
    startFocus: (minutes) => service.run(() => service.engine.startFocus(minutes)),
    startBreak: (minutes) => service.run(() => service.engine.startBreak(minutes)),
    togglePause: () => service.run(() => service.engine.toggleFocusPause()),
    addMinutes: () => service.run(() => service.engine.addMinutes()),
    stopTimer: () => service.run(() => service.engine.stop()),
    discardFocus: () => service.run(() => service.engine.discardFocus()),
    speak: () => send(CHANNEL.speakNow),
    isVisible: () => visible,
    toggleVisible: () => setVisible(!visible),
    currentPet: () => settings.pet,
    choosePet: (id) => { settings.pet = id; },
    isMovementOn: () => settings.movement,
    setMovement: (on) => { settings.movement = on; },
    quit: () => app.quit(),
  });
  const menu = tray;
  settings.addObserver(() => menu.refresh());
  // Fine di un focus o di una pausa: il compagno compare anche se l'avevi nascosto.
  service.engine.onEvent((event) => { if (event.type === "sound" && !visible) setVisible(true); });
  ipcMain.handle(CHANNEL.getTimerState, () => service.snapshot());
  ipcMain.on(CHANNEL.timerExtend, () => service.run(() => service.engine.extendFocus()));
  app.on("before-quit", () => service.shutdown());

  const setVisible = (on: boolean): void => {
    visible = on;
    if (on) win.showInactive(); else win.hide();
    send(CHANNEL.visibilityChanged, on);
    menu.refresh();
  };

  // L'area di lavoro cambia (barra delle applicazioni spostata, risoluzione, scala): la finestra la segue.
  const refit = (): void => { if (!win.isDestroyed()) fitToWorkArea(win, primaryDisplay()); };
  screen.on("display-metrics-changed", refit);
  screen.on("display-added", refit);
  screen.on("display-removed", refit);

  if (process.env["FF_SELFTEST"] !== undefined) runSelfTest(win, interactions, settings, () => service);
}

/**
 * Prove automatiche, solo con FF_SELFTEST (mai in uso normale). Due modi:
 * - FF_SELFTEST="4,9": a quei secondi fa una schermata e le misure, poi chiude. FF_SELFTEST_SCRIPT è un comando per la
 *   pagina, eseguito dopo un secondo e mezzo (per esempio «window.__ff.say()»).
 * - FF_SELFTEST_FILE=percorso.cjs: un copione che riceve gli strumenti (finestra, attese, schermate, misure, eventi del mouse).
 * FF_SELFTEST_OUT è la cartella dove scrivere.
 */
function runSelfTest(win: BrowserWindow, interactions: string[], settings: Settings, timer: () => TimerService): void {
  const out = process.env["FF_SELFTEST_OUT"] ?? join(app.getPath("temp"), "ff-selftest");
  mkdirSync(out, { recursive: true });
  // I messaggi della pagina (e i suoi errori) escono sul terminale.
  win.webContents.on("console-message", (event) => console.log(`[pagina:${event.level}] ${event.message}`));
  win.webContents.on("render-process-gone", (_event, details) => console.log(`[pagina] processo finito: ${details.reason}`));

  const tools = {
    win,
    interactions,
    settings,
    timer,
    sleep: (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)),
    js: (code: string) => win.webContents.executeJavaScript(code) as Promise<unknown>,
    async shot(name: string) {
      const image = await win.webContents.capturePage();
      writeFileSync(join(out, `${name}.png`), image.toPNG());
    },
    metrics(name: string) {
      const metrics = app.getAppMetrics().map((m) => ({
        type: m.type, cpu: m.cpu.percentCPUUsage, workingSetMB: Math.round(m.memory.workingSetSize / 1024),
      }));
      writeFileSync(join(out, `${name}.json`), JSON.stringify({ metrics }, null, 2));
    },
    /** Un evento del mouse arriva alla pagina come se l'utente lo avesse fatto (senza passare dal sistema). */
    mouse(type: "mouseMove" | "mouseDown" | "mouseUp", x: number, y: number) {
      win.webContents.sendInputEvent({ type, x, y, button: "left", clickCount: 1 });
    },
    quit: () => app.quit(),
  };

  const file = process.env["FF_SELFTEST_FILE"];
  if (file) {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const script = require(file) as (t: typeof tools) => Promise<void>;
    void script(tools).catch((error: unknown) => { console.log("[prova] errore:", error); }).finally(() => app.quit());
    return;
  }

  const moments = (process.env["FF_SELFTEST"] ?? "").split(",").map(Number).filter((n) => Number.isFinite(n) && n > 0);
  const script = process.env["FF_SELFTEST_SCRIPT"];
  if (script) setTimeout(() => { void tools.js(script).catch(() => undefined); }, 1500);
  moments.forEach((seconds, index) => {
    setTimeout(async () => {
      await tools.shot(`schermata-${index + 1}`);
      tools.metrics(`misure-${index + 1}`);
      if (index === moments.length - 1) app.quit();
    }, seconds * 1000);
  });
}

void app.whenReady().then(start);
app.on("window-all-closed", () => app.quit());
