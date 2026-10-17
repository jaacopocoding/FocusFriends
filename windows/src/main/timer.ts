// Il timer nel processo principale: lì il tempo non rallenta quando la pagina è nascosta. Tiene il registro, fa battere il
// motore ogni 0,2 secondi e manda alla pagina com'è il timer (una volta al secondo, o subito se succede qualcosa).

import { join } from "node:path";
import { PomodoroEngine } from "../core/pomodoro.ts";
import type { PomodoroEvent, PomodoroSnapshot } from "../core/pomodoro.ts";
import { SessionLog } from "../core/log.ts";
import type { Settings } from "../core/settings.ts";
import { CHANNEL } from "../shared/api.ts";

const BEAT_MS = 200;

export interface TimerService {
  engine: PomodoroEngine;
  log: SessionLog;
  snapshot(): PomodoroSnapshot;
  /** Esegue un comando del timer e manda subito alla pagina com'è dopo. */
  run(command: () => void): void;
  /** Chiusura dell'app: un focus ancora in corso si salva come interrotto. */
  shutdown(): void;
}

/** Cosa fa cambiare quello che si vede: a parte i secondi, la crescita (a passi dell'1%). */
function visibleKey(s: PomodoroSnapshot): string {
  return JSON.stringify([
    s.phase, s.label, s.remainingText, s.isPaused, s.rangeText, s.focusMinutes, s.breakMinutes, s.subject, s.notes.length,
    s.lastFocus?.sessionId ?? null, s.isLongBreak, s.cycleDone, s.graceSecondsLeft !== null,
    s.growthProgress === null ? null : Math.floor(s.growthProgress * 100),
  ]);
}

export function startTimer(options: {
  directory: string;
  settings: Settings;
  send: (channel: string, payload: unknown) => void;
  /** Cambia qualcosa che si vede (per rifare il menu dell'area di notifica). */
  onChange: () => void;
}): TimerService {
  const { settings, send } = options;
  const log = new SessionLog(options.directory);
  // I problemi con i dati li dice il compagno.
  log.onProblem = (text) => send(CHANNEL.timerEvent, { type: "say", text } satisfies PomodoroEvent);
  // Se l'app si era chiusa di colpo durante un focus, lo salvo come interrotto.
  log.recoverInterrupted();

  const engine = new PomodoroEngine({
    log, now: () => Date.now(), longBreakEnabled: () => settings.longBreakEnabled, petId: () => settings.pet,
  });
  let lastKey = "";
  const broadcast = (force: boolean): void => {
    const snapshot = engine.snapshot();
    const key = visibleKey(snapshot);
    if (!force && key === lastKey) return;
    lastKey = key;
    send(CHANNEL.timerState, snapshot);
    options.onChange();
  };
  engine.onEvent((event) => {
    send(CHANNEL.timerEvent, event);
    broadcast(true);
  });
  const timer = setInterval(() => {
    engine.tick();
    broadcast(false);
  }, BEAT_MS);

  return {
    engine, log,
    snapshot: () => engine.snapshot(),
    run: (command) => { command(); broadcast(true); },
    shutdown: () => {
      clearInterval(timer);
      engine.recordInterruptedFocusOnQuit();
    },
  };
}

/** Dove sta il file «in corso» (per le prove). */
export const progressFile = (directory: string): string => join(directory, "in-corso.json");
