// Il processo principale: la finestra trasparente, l'area di notifica, i file.

import { app, BrowserWindow, ipcMain, powerMonitor, screen, session } from "electron";
import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { CHANNEL } from "../shared/api.ts";
import type { CardCommand, CardOpenRequest, QuietSpeech, SettingsSnapshot } from "../shared/api.ts";
import { PhraseDeck, loadPhrases } from "../core/phrases.ts";
import { AppLog } from "../core/diagnostics.ts";
import { describeDisplay } from "../core/displays.ts";
import { testValue } from "../core/environment.ts";
import { PET_IDS, petInfo } from "../core/pets.ts";
import { Profile } from "../core/profile.ts";
import type { TimerKind } from "../core/rules.ts";
import { Settings } from "../core/settings.ts";
import { refreshSystemZone } from "../core/time.ts";
import { ToDoList } from "../core/todoList.ts";
import { createCardService } from "./card.ts";
import { loginItem } from "./login.ts";
import { createMusicService } from "./music.ts";
import { createRemarks } from "./remarks.ts";
import type { RemarksService } from "./remarks.ts";
import { createStage } from "./stage.ts";
import type { Stage } from "./stage.ts";
import { createStatsController } from "./statsWindow.ts";
import type { StatsController } from "./statsWindow.ts";
import { assetsDirectory, dataDirectory, rendererDirectory, resourcesDirectory } from "./paths.ts";
import { createOverlay, primaryDisplay } from "./overlay.ts";
import { handleScheme, registerScheme } from "./protocol.ts";
import { denyPermissions, lockDownWindows } from "./security.ts";
import { startTimer } from "./timer.ts";
import type { TimerService } from "./timer.ts";
import { createTray } from "./tray.ts";

// Prove di memoria e processore: con FF_SWITCHES (un elenco JSON di opzioni di Chromium) e FF_NO_GPU si provano alternative. Solo da sviluppo.
if (process.env["FF_SELFTEST"] !== undefined) {
  for (const option of JSON.parse(process.env["FF_SWITCHES"] ?? "[]") as string[]) {
    const [name, value] = option.split("=");
    app.commandLine.appendSwitch(name!, value);
  }
  if (process.env["FF_NO_GPU"] === "1") app.disableHardwareAcceleration();
}

registerScheme();

let visible = true;

// Una sola copia dell'app: un doppio avvio non deve mai toccare i dati due volte (è già successo sul Mac, per un errore di una prova).
// (Solo le prove automatiche possono saltare il controllo, per aprire più copie con cartelle di dati diverse.)
const gotLock = testValue(process.env, "FF_NO_LOCK") === "1" || app.requestSingleInstanceLock();
if (!gotLock) app.quit();

/** Il registro dell'app (senza dati personali) per capire cosa è successo dopo un arresto inatteso. */
let appLog: AppLog | null = null;
process.on("uncaughtException", (error) => { appLog?.error("eccezione non gestita", error); });
process.on("unhandledRejection", (reason) => { appLog?.error("promessa respinta e non gestita", reason); });

// Nessuna finestra porta fuori dall'app, né apre finestre nuove (i permessi si negano in start()).
lockDownWindows((message) => appLog?.warn(message));

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
  app.setAppUserModelId("com.jacopo.focusfriends");
  const assets = assetsDirectory(app);
  const data = dataDirectory(app);
  mkdirSync(data, { recursive: true });
  const log = new AppLog({ directory: data, home: homedir() });
  appLog = log;
  log.info(`avvio ${app.getVersion()} (${process.platform} ${process.getSystemVersion()} ${process.arch}, Electron ${process.versions.electron})`);
  app.on("child-process-gone", (_event, details) => log.warn(`processo ${details.type} finito: ${details.reason} (codice ${details.exitCode})`));
  denyPermissions(session.defaultSession, (message) => log.warn(message));
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
  const todo = new ToDoList(data);
  const decks = new Map<string, PhraseDeck>();
  const win = createOverlay(primaryDisplay(), app.getAppPath());
  // Se la pagina cade la si ricarica (non più di tre volte in dieci minuti), così il compagno torna.
  const reloads: number[] = [];
  win.webContents.on("render-process-gone", (_event, details) => {
    log.warn(`la pagina del compagno è caduta: ${details.reason}`);
    const now = Date.now();
    while (reloads.length > 0 && now - reloads[0]! > 600_000) reloads.shift();
    if (details.reason === "clean-exit" || reloads.length >= 3 || win.isDestroyed()) return;
    reloads.push(now);
    win.webContents.reload();
  });

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
  const sayWhenQuiet = (speech: QuietSpeech): void => send(CHANNEL.sayWhenQuiet, speech);

  const stage = createStage(win, send);
  ipcMain.on(CHANNEL.dragging, (_event, on: unknown) => stage.setDragging(on === true));
  settings.addObserver(() => send(CHANNEL.settingsChanged, snapshot(settings)));
  // I problemi con il profilo li dice il compagno.
  profile.onProblem = say;
  settings.onProblem = say;
  todo.onProblem = say;
  profile.addObserver(() => statsRef?.refreshTitle());
  // Chi usava già l'app li tiene tutti; per gli altri si guadagnano (silenziosamente: al massimo sono già meritati).
  profile.keepAllCompanions(PET_IDS);

  ipcMain.handle(CHANNEL.getSettings, () => snapshot(settings));
  const interactions: string[] = [];

  // Il timer, il menu dell'area di notifica e la scheda si conoscono a vicenda: nascono uno dopo l'altro e si agganciano.
  let tray: ReturnType<typeof createTray> | null = null;
  const service: TimerService = startTimer({ directory: data, settings, send, onChange: () => tray?.refresh() });
  // Le frasi che il compagno dice di sua iniziativa, in quest'ordine: il saluto dell'avvio e il riepilogo della settimana (una volta), le scadenze
  // di oggi e domani (al massimo ogni tre ore, mai durante un focus), ogni tanto un numero dello studio, e poi il mazzo. Come Speaker.sayRandom sul Mac.
  const remarks = createRemarks({
    settings, profile, todo, log: () => service.log, timerPhase: () => service.engine.snapshot().phase,
    isVisible: () => visible, sayWhenQuiet,
  });
  ipcMain.handle(CHANNEL.nextPhrase, (_event, petId: unknown) => remarks.nextPhrase(() => {
    const id = typeof petId === "string" ? petId : settings.pet;
    // Il file si rilegge a ogni frase: le modifiche valgono subito.
    const phrases = loadPhrases(id, { userDirectory: data, bundledDirectory: assets });
    let deck = decks.get(id);
    if (!deck) { deck = new PhraseDeck(); decks.set(id, deck); }
    return deck.draw(phrases) ?? petInfo(id).fallbackQuote;
  }));
  remarks.greetOnLaunch();

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
    settings, profile, todo, window: win, timer: () => service,
    isVisible: () => visible, setVisible, say, sayWhenQuiet,
    speakNow: () => send(CHANNEL.speakNow),
    reopenCard: () => send(CHANNEL.cardReopen),
    moreSettings: () => tray?.popUp(),
    quit: () => app.quit(),
    stats: () => stats.show("day"),
  });

  /** Un clic sull'icona (o una scelta del menu) che apre la scheda: le coordinate sono quelle della finestra (l'area di lavoro dello schermo del compagno). */
  const openCard = (request: Omit<CardOpenRequest, "anchor"> & { bounds?: { x: number; y: number; width: number; height: number } }): void => {
    const area = stage.current.workArea;
    // Se l'icona sta su un altro schermo, la scheda si apre di fianco al compagno.
    const sameScreen = request.bounds !== undefined && stage.displayOf(request.bounds)?.id === stage.current.id;
    const anchor = request.bounds && sameScreen
      ? { x: request.bounds.x - area.x, y: request.bounds.y - area.y, width: request.bounds.width, height: request.bounds.height }
      : null;
    send(CHANNEL.cardToggle, { anchor, toggle: request.toggle, ...(request.page ? { page: request.page } : {}) } satisfies CardOpenRequest);
  };

  tray = createTray({
    assets, data, settings, profile, card, timer: () => service, isVisible: () => visible, setVisible,
    speak: () => send(CHANNEL.speakNow),
    askFocus: (minutes) => send(CHANNEL.askSubject, minutes),
    askName: () => send(CHANNEL.askName),
    loginItem: loginItem(app),
    screens: () => stage.displays().map((d, i) => ({ id: d.id, label: `Schermo ${i + 1}${d.primary ? " (principale)" : ""}`, current: d.id === stage.current.id })),
    moveToScreen: (id) => stage.moveTo(id, false),
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
  // Chiusura pulita: un focus in corso si registra come interrotto, anche se è Windows che chiude la sessione.
  let closing = false;
  const shutdown = (reason: string): void => {
    if (closing) return;
    closing = true;
    log.info(`chiusura (${reason})`);
    service.shutdown();
  };
  app.on("before-quit", () => shutdown("uscita"));
  win.on("session-end", () => shutdown("fine della sessione di Windows"));
  // Una seconda copia dell'app non parte: quella che c'è mostra il compagno.
  app.on("second-instance", () => {
    log.info("seconda copia dell'app: si mostra il compagno");
    if (!visible) setVisible(true);
  });

  // Fine di un focus o di una pausa: il compagno compare anche se l'avevi nascosto.
  service.engine.onEvent((event) => {
    if (event.type === "sound" && !visible) setVisible(true);
    if (event.type === "focusRecorded") {
      card.evaluateCompanionRewards(true);
      remarks.focusRecorded(event.session);
    }
  });
  card.evaluateCompanionRewards(false);
  // La prima volta (anche per chi la usava già): come ti chiami e chi ti fa compagnia.
  ipcMain.once(CHANNEL.rendererReady, () => {
    if (!profile.introSeen) setTimeout(() => send(CHANNEL.showIntro), 800);
  });
  ipcMain.handle(CHANNEL.getTimerState, () => service.snapshot());

  // L'area di lavoro cambia (barra delle applicazioni spostata, risoluzione, scala, uno schermo tolto o aggiunto): la finestra la segue.
  // (Misure, scala e lato della barra finiscono nel registro dell'app: una prova su un altro computer si capisce da lì.)
  const logDisplays = (reason: string): void => {
    const primaryId = screen.getPrimaryDisplay().id;
    for (const d of screen.getAllDisplays()) {
      log.info(`${reason}: ${describeDisplay({ id: d.id, primary: d.id === primaryId, bounds: d.bounds, workArea: d.workArea, scaleFactor: d.scaleFactor })}`);
    }
  };
  logDisplays("schermi all'avvio");
  screen.on("display-metrics-changed", () => { logDisplays("schermo cambiato"); stage.refit(); });
  screen.on("display-added", () => { log.info("schermo aggiunto"); logDisplays("schermi ora"); stage.refit(); });
  screen.on("display-removed", () => { log.info("schermo tolto"); logDisplays("schermi ora"); stage.refit(); });
  // Appena la pagina è pronta sa dov'è la finestra.
  ipcMain.once(CHANNEL.rendererReady, () => stage.refit());

  // Sleep e risveglio (anche col coperchio chiuso). Il timer non ha bisogno di niente: un salto di più di 10 secondi lo conta già
  // come tempo da fermo. Al risveglio, però, possono essere cambiati il fuso orario (un viaggio), gli schermi (un monitor
  // scollegato nel frattempo) e l'uscita audio, che a volte si ferma da sola.
  powerMonitor.on("suspend", () => { log.info("il computer va in sleep"); remarks.suspended(); });
  const awake = (what: string): void => {
    log.info(`${what}: si rileggono fuso e schermi, l'audio riparte se serve`);
    refreshSystemZone();
    logDisplays("schermi al risveglio");
    stage.refit();
    send(CHANNEL.systemResumed);
  };
  powerMonitor.on("resume", () => { awake("il computer si risveglia"); remarks.resumed(); });
  powerMonitor.on("unlock-screen", () => awake("lo schermo è sbloccato"));

  if (process.env["FF_SELFTEST"] !== undefined) runSelfTest(win, interactions, settings, () => service, card, stats, stage, remarks);
}

/**
 * Prove automatiche, solo con FF_SELFTEST (mai in uso normale). Due modi:
 * - FF_SELFTEST="4,9": a quei secondi fa una schermata e le misure, poi chiude. FF_SELFTEST_SCRIPT è un comando per la
 *   pagina, eseguito dopo un secondo e mezzo (per esempio «window.__ff.say()»).
 * - FF_SELFTEST_FILE=percorso.cjs: un copione che riceve gli strumenti (finestra, attese, schermate, misure, eventi del mouse).
 * FF_SELFTEST_OUT è la cartella dove scrivere.
 */
function runSelfTest(win: BrowserWindow, interactions: string[], settings: Settings, timer: () => TimerService, card: ReturnType<typeof createCardService>, stats: StatsController, stage: Stage, remarks: RemarksService): void {
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
    stage,
    remarks,
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
    /** Sleep e risveglio simulati: gli stessi messaggi che manda Windows. */
    power: (event: "suspend" | "resume" | "lock-screen" | "unlock-screen") => { powerMonitor.emit(event); },
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

if (gotLock) void app.whenReady().then(start);
app.on("window-all-closed", () => app.quit());
