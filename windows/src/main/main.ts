// Il processo principale: la finestra trasparente, l'area di notifica, i file.

import { app, BrowserWindow, ipcMain, screen } from "electron";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { CHANNEL } from "../shared/api.ts";
import type { CardCommand, CardOpenRequest, SettingsSnapshot } from "../shared/api.ts";
import { PhraseDeck, loadPhrases } from "../core/phrases.ts";
import { PET_IDS, petInfo } from "../core/pets.ts";
import { Profile } from "../core/profile.ts";
import type { TimerKind } from "../core/rules.ts";
import { Settings } from "../core/settings.ts";
import { createCardService } from "./card.ts";
import { createMusicService } from "./music.ts";
import { createStatsController } from "./statsWindow.ts";
import type { StatsController } from "./statsWindow.ts";
import { assetsDirectory, dataDirectory, rendererDirectory, resourcesDirectory } from "./paths.ts";
import { createOverlay, fitToWorkArea, primaryDisplay } from "./overlay.ts";
import { handleScheme, registerScheme } from "./protocol.ts";
import { startTimer } from "./timer.ts";
import type { TimerService } from "./timer.ts";
import { createTray } from "./tray.ts";

registerScheme();

let visible = true;

function snapshot(settings: Settings): SettingsSnapshot {
  return {
    pet: settings.pet, movement: settings.movement, phraseFrequency: settings.phraseFrequency, askHowItWent: settings.askHowItWent,
    ambientSound: settings.ambientSound, ambientVolume: settings.ambientVolume,
    musicSource: settings.musicSource, musicFolder: settings.musicFolder, musicVolume: settings.musicVolume,
  };
}

async function start(): Promise<void> {
  let statsRef: StatsController | null = null;
  app.dock?.hide();
  const assets = assetsDirectory(app);
  const data = dataDirectory(app);
  mkdirSync(data, { recursive: true });
  const settings = new Settings(data);
  const music = createMusicService({ assets, folder: () => settings.musicFolder });
  handleScheme({ assets, renderer: rendererDirectory(app), resources: resourcesDirectory(app), musicFile: music.file });
  music.prepareFolder();
  let lastFolder = settings.musicFolder;
  settings.addObserver(() => {
    if (settings.musicFolder === lastFolder) return;
    lastFolder = settings.musicFolder;
    music.prepareFolder();
  });
  const profile = new Profile(data, { developer: () => settings.developerMode });
  const decks = new Map<string, PhraseDeck>();
  const win = createOverlay(primaryDisplay(), app.getAppPath());

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
  const say = (text: string): void => send(CHANNEL.timerEvent, { type: "say", text });

  settings.addObserver(() => send(CHANNEL.settingsChanged, snapshot(settings)));
  // I problemi con il profilo li dice il compagno.
  profile.onProblem = say;
  profile.addObserver(() => statsRef?.refreshTitle());
  // Chi usava già l'app li tiene tutti; per gli altri si guadagnano (silenziosamente: al massimo sono già meritati).
  profile.keepAllCompanions(PET_IDS);

  ipcMain.handle(CHANNEL.getSettings, () => snapshot(settings));
  const interactions: string[] = [];
  ipcMain.handle(CHANNEL.nextPhrase, (_event, petId: unknown) => {
    const id = typeof petId === "string" ? petId : settings.pet;
    // Il file si rilegge a ogni frase: le modifiche valgono subito.
    const phrases = loadPhrases(id, { userDirectory: data, bundledDirectory: assets });
    let deck = decks.get(id);
    if (!deck) { deck = new PhraseDeck(); decks.set(id, deck); }
    return deck.draw(phrases) ?? petInfo(id).fallbackQuote;
  });

  // Il timer, il menu dell'area di notifica e la scheda si conoscono a vicenda: nascono uno dopo l'altro e si agganciano.
  let tray: ReturnType<typeof createTray> | null = null;
  const service: TimerService = startTimer({ directory: data, settings, send, onChange: () => tray?.refresh() });

  const setVisible = (on: boolean): void => {
    visible = on;
    if (on) win.showInactive(); else win.hide();
    send(CHANNEL.visibilityChanged, on);
    tray?.refresh();
  };

  const stats: StatsController = statsRef = createStatsController({
    appPath: app.getAppPath(), log: () => service.log, profile,
    onBack: () => send(CHANNEL.cardReopen),
    onDeleteAll: () => undefined,
  });
  const card = createCardService({
    settings, profile, window: win, timer: () => service,
    isVisible: () => visible, setVisible, say,
    speakNow: () => send(CHANNEL.speakNow),
    reopenCard: () => send(CHANNEL.cardReopen),
    moreSettings: () => tray?.popUp(),
    quit: () => app.quit(),
    stats: () => stats.show("day"),
  });

  /** Un clic sull'icona (o una scelta del menu) che apre la scheda: le coordinate sono quelle della finestra (l'area di lavoro). */
  const openCard = (request: Omit<CardOpenRequest, "anchor"> & { bounds?: { x: number; y: number; width: number; height: number } }): void => {
    const area = primaryDisplay().workArea;
    const anchor = request.bounds
      ? { x: request.bounds.x - area.x, y: request.bounds.y - area.y, width: request.bounds.width, height: request.bounds.height }
      : null;
    send(CHANNEL.cardToggle, { anchor, toggle: request.toggle, ...(request.page ? { page: request.page } : {}) } satisfies CardOpenRequest);
  };

  tray = createTray({
    assets, data, settings, profile, card, timer: () => service, isVisible: () => visible, setVisible,
    speak: () => send(CHANNEL.speakNow),
    askFocus: (minutes) => send(CHANNEL.askSubject, minutes),
    askName: () => send(CHANNEL.askName),
    toggleCard: (bounds) => openCard({ toggle: true, bounds }),
    openTimers: () => openCard({ toggle: false, page: "timers" }),
    showStats: () => stats.show("day"),
    quit: () => app.quit(),
  });
  const menu = tray;
  settings.addObserver(() => menu.refresh());

  ipcMain.handle(CHANNEL.musicTracks, (_event, source: unknown) => music.list(source === "bundled" || source === "folder" ? source : "off"));
  ipcMain.handle(CHANNEL.cardData, () => card.data());
  ipcMain.on(CHANNEL.cardCommand, (_event, command: CardCommand) => card.command(command));
  ipcMain.handle(CHANNEL.cardAddTimer, (_event, kind: TimerKind, minutes: number) => card.addTimer(kind, minutes));
  // La finestra riceve tutti i clic finché c'è una scheda o una finestra di dialogo aperta, e la tastiera finché si scrive:
  // altrimenti lascia passare i clic e non prende mai il fuoco.
  let wasInteractive = false, hadKeyboard = false;
  ipcMain.on(CHANNEL.inputMode, (_event, mode: { interactive?: unknown; keyboard?: unknown }) => {
    if (win.isDestroyed()) return;
    const interactive = mode.interactive === true, keyboard = mode.keyboard === true;
    win.setIgnoreMouseEvents(!interactive, { forward: true });
    if (keyboard !== hadKeyboard) {
      win.setFocusable(keyboard);
      if (keyboard) win.focus(); else win.blur();
    }
    if (interactive !== wasInteractive) interactions.push(interactive ? "clic-acceso" : "clic-spento");
    wasInteractive = interactive;
    hadKeyboard = keyboard;
  });
  ipcMain.on(CHANNEL.timerExtend, () => service.run(() => service.engine.extendFocus()));
  app.on("before-quit", () => service.shutdown());

  // Fine di un focus o di una pausa: il compagno compare anche se l'avevi nascosto.
  service.engine.onEvent((event) => {
    if (event.type === "sound" && !visible) setVisible(true);
    if (event.type === "focusRecorded") card.evaluateCompanionRewards(true);
  });
  card.evaluateCompanionRewards(false);
  // La prima volta (anche per chi la usava già): come ti chiami e chi ti fa compagnia.
  ipcMain.once(CHANNEL.rendererReady, () => {
    if (!profile.introSeen) setTimeout(() => send(CHANNEL.showIntro), 800);
  });
  ipcMain.handle(CHANNEL.getTimerState, () => service.snapshot());

  // L'area di lavoro cambia (barra delle applicazioni spostata, risoluzione, scala): la finestra la segue.
  const refit = (): void => { if (!win.isDestroyed()) fitToWorkArea(win, primaryDisplay()); };
  screen.on("display-metrics-changed", refit);
  screen.on("display-added", refit);
  screen.on("display-removed", refit);

  if (process.env["FF_SELFTEST"] !== undefined) runSelfTest(win, interactions, settings, () => service, card, stats);
}

/**
 * Prove automatiche, solo con FF_SELFTEST (mai in uso normale). Due modi:
 * - FF_SELFTEST="4,9": a quei secondi fa una schermata e le misure, poi chiude. FF_SELFTEST_SCRIPT è un comando per la
 *   pagina, eseguito dopo un secondo e mezzo (per esempio «window.__ff.say()»).
 * - FF_SELFTEST_FILE=percorso.cjs: un copione che riceve gli strumenti (finestra, attese, schermate, misure, eventi del mouse).
 * FF_SELFTEST_OUT è la cartella dove scrivere.
 */
function runSelfTest(win: BrowserWindow, interactions: string[], settings: Settings, timer: () => TimerService, card: ReturnType<typeof createCardService>, stats: StatsController): void {
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
    card,
    stats,
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
    mouse(type: "mouseMove" | "mouseDown" | "mouseUp", x: number, y: number, button: "left" | "right" = "left") {
      win.webContents.sendInputEvent({ type, x, y, button, clickCount: 1 });
    },
    key(keyCode: string) {
      win.webContents.sendInputEvent({ type: "keyDown", keyCode });
      win.webContents.sendInputEvent({ type: "keyUp", keyCode });
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
