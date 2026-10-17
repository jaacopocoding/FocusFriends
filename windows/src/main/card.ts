// La scheda vista dal processo principale: i suoi dati e i comandi che arrivano dalla pagina (MenuController.swift).

import { dialog } from "electron";
import type { BrowserWindow } from "electron";
import { buildCardData } from "../core/card.ts";
import type { CardData } from "../core/card.ts";
import { hasTracks } from "../core/music.ts";
import { ambientOfChoice, nextAmbient } from "../core/rules.ts";
import type { AddTimerResult, TimerKind } from "../core/rules.ts";
import { petInfo } from "../core/pets.ts";
import type { Profile } from "../core/profile.ts";
import { evaluateUnlocks, unlockMessage } from "../core/unlocks.ts";
import type { Settings } from "../core/settings.ts";
import { CHATTINESS } from "../core/rules.ts";
import { PET_IDS } from "../core/pets.ts";
import { reflectionReply, saveReflection } from "../core/reflection.ts";
import type { CardCommand } from "../shared/api.ts";
import type { TimerService } from "./timer.ts";

export interface CardServiceOptions {
  settings: Settings;
  profile: Profile;
  timer: () => TimerService;
  window: BrowserWindow;
  isVisible: () => boolean;
  setVisible: (visible: boolean) => void;
  say: (text: string) => void;
  speakNow: () => void;
  reopenCard: () => void;
  moreSettings: () => void;
  quit: () => void;
  stats: () => void;
}

export interface CardService {
  data(): CardData;
  command(command: CardCommand): void;
  addTimer(kind: TimerKind, minutes: number): AddTimerResult;
  /** Dopo un focus (o all'avvio): sblocca i compagni guadagnati e, se è la prima volta, li annuncia. */
  evaluateCompanionRewards(announce: boolean): void;
  /** Dal menu: un suono ambiente (spegne la musica). */
  setAmbient(sound: Settings["ambientSound"]): void;
  /** Dal menu: la sorgente della musica (spegne il suono; per «la mia cartella» la prima volta chiede la cartella). */
  selectMusic(source: Settings["musicSource"]): Promise<void>;
  /** Dal menu: «Scegli la cartella…». */
  chooseMusicFolder(): Promise<void>;
}

export function createCardService(options: CardServiceOptions): CardService {
  const { settings, profile } = options;
  const timer = (): TimerService => options.timer();

  const showPetIfHidden = (): void => { if (!options.isVisible()) options.setVisible(true); };

  /** Il sottofondo è uno solo: un suono o la musica; scegliendone uno l'altro si spegne. */
  const setAmbient = (sound: typeof settings.ambientSound): void => {
    if (sound !== "none") settings.musicSource = "off";
    settings.ambientSound = sound;
  };

  /** Una cartella con la musica, scelta dall'utente (la prima volta, o se quella di prima non c'è più). */
  const chooseFolder = async (): Promise<string | null> => {
    const result = await dialog.showOpenDialog(options.window, {
      title: "Scegli la cartella con la musica",
      message: "Scegli la cartella con la musica da ascoltare mentre studi (mp3, m4a, wav, aiff, flac).",
      buttonLabel: "Scegli", properties: ["openDirectory"], ...(settings.musicFolder ? { defaultPath: settings.musicFolder } : {}),
    });
    const folder = result.filePaths[0];
    if (result.canceled || folder === undefined) return null;
    if (!hasTracks(folder)) {
      await dialog.showMessageBox(options.window, {
        type: "info", message: "Nessun brano in questa cartella",
        detail: "Non ho trovato file audio (mp3, m4a, wav, aiff, flac). Scegli un'altra cartella.",
      });
      return null;
    }
    return folder;
  };

  const selectMusic = async (source: typeof settings.musicSource): Promise<void> => {
    if (source === "folder" && (settings.musicFolder === null || !hasTracks(settings.musicFolder))) {
      const folder = await chooseFolder();
      options.reopenCard();
      if (folder === null) return;
      settings.musicFolder = folder;
    }
    if (source !== "off") settings.ambientSound = "none";
    settings.musicSource = source;
  };

  const confirmDiscard = async (): Promise<void> => {
    const answer = await dialog.showMessageBox(options.window, {
      type: "warning", message: "Eliminare questo focus?", detail: "Non viene registrato: niente minuti, niente piantina.",
      buttons: ["Annulla", "Elimina"], defaultId: 0, cancelId: 0,
    });
    if (answer.response === 1) timer().run(() => timer().engine.discardFocus()); else options.reopenCard();
  };

  const service: CardService = {
    data() {
      const engine = timer().engine;
      return buildCardData({
        now: Date.now(), sessions: timer().log.sessions, profile,
        petVisible: options.isVisible(),
        timers: {
          focus: settings.allTimers("focus"), rest: settings.allTimers("rest"),
          customFocus: settings.customTimers("focus"), customRest: settings.customTimers("rest"),
        },
        chattiness: settings.phraseFrequency, movementOn: settings.movement, askOn: settings.askHowItWent,
        ambient: settings.ambientSound, ambientVolume: settings.ambientVolume,
        music: settings.musicSource, musicFolder: settings.musicFolder, musicVolume: settings.musicVolume,
        lastSessionId: engine.snapshot().lastFocus?.sessionId ?? null,
        recentSubjects: timer().log.recentSubjects(), lastNote: timer().log.lastNote(),
      });
    },

    addTimer(kind, minutes) {
      return settings.addCustomTimer(minutes, kind);
    },

    setAmbient,
    selectMusic,
    async chooseMusicFolder() {
      const folder = await chooseFolder();
      if (folder === null) return;
      settings.ambientSound = "none";
      settings.musicFolder = folder;
      settings.musicSource = "folder";
    },

    evaluateCompanionRewards(announce) {
      const fresh = evaluateUnlocks(profile, timer().log.sessions, PET_IDS, settings.developerMode);
      if (fresh.length === 0 || !announce) return;
      // Dopo la frase di fine focus, che altrimenti la coprirebbe.
      setTimeout(() => options.say(unlockMessage(fresh)), 9000);
    },

    command(command) {
      const run = (action: () => void): void => timer().run(action);
      switch (command.name) {
        case "startFocus":
          showPetIfHidden();
          run(() => timer().engine.startFocus(command.minutes, command.subject));
          break;
        case "startBreak":
          showPetIfHidden();
          run(() => timer().engine.startBreak(command.minutes));
          break;
        case "stopTimer": run(() => timer().engine.stop()); break;
        case "addMinutes": run(() => timer().engine.addMinutes()); break;
        case "togglePause": run(() => timer().engine.toggleFocusPause()); break;
        case "addNote": run(() => timer().engine.addNote(command.text)); break;
        case "discardFocus": void confirmDiscard(); break;
        case "selectPet": {
          if (command.id === settings.pet || !profile.isCompanionUnlocked(command.id)) break;
          settings.pet = command.id;
          showPetIfHidden();
          options.say(petInfo(command.id).greeting);
          break;
        }
        case "showStats": options.stats(); break;
        case "cycleChattiness": {
          const index = CHATTINESS.indexOf(settings.phraseFrequency);
          settings.phraseFrequency = CHATTINESS[(index + 1) % CHATTINESS.length] ?? "sometimes";
          break;
        }
        case "toggleMovement": settings.movement = !settings.movement; break;
        case "toggleAsk": settings.askHowItWent = !settings.askHowItWent; break;
        case "cycleAmbient": setAmbient(nextAmbient(settings.ambientSound)); break;
        case "cycleMusic": {
          // Spenta → brani inclusi → la mia cartella (la prima volta la chiede) → spenta.
          const next = settings.musicSource === "off" ? "bundled" : settings.musicSource === "bundled" ? "folder" : "off";
          void selectMusic(next);
          break;
        }
        case "setMusicVolume": settings.musicVolume = command.value; break;
        case "setAmbientVolume": settings.ambientVolume = command.value; break;
        case "setBackground": {
          const sound = ambientOfChoice(command.choice);
          if (sound !== null) {
            if (sound === "none") settings.musicSource = "off";
            setAmbient(sound);
          } else {
            void selectMusic("bundled");
          }
          break;
        }
        case "setBackgroundVolume":
          if (settings.ambientSound === "none" && settings.musicSource !== "off") settings.musicVolume = command.value;
          else settings.ambientVolume = command.value;
          break;
        case "toggleVisibility": options.setVisible(!options.isVisible()); break;
        case "speak": showPetIfHidden(); options.speakNow(); break;
        case "removeTimer": settings.removeCustomTimer(command.minutes, command.kind); break;
        case "moreSettings": options.moreSettings(); break;
        case "quit": options.quit(); break;
        case "rateLast": {
          const id = timer().engine.snapshot().lastFocus?.sessionId;
          if (!id) break;
          const note = timer().log.sessions.find((x) => x.id === id)?.note ?? null;
          timer().log.setReflection(id, command.rating, note);
          options.say(reflectionReply(command.rating));
          break;
        }
        case "saveReflection": saveReflection(timer().log, command.sessionId, command.rating, command.note); break;
        case "setName": profile.setName(command.userName); break;
        case "finishIntro": {
          // La prima volta: come ti chiami e chi ti fa compagnia. «Salta» vale «nessun nome» e il compagno che c'era.
          profile.setName(command.userName);
          profile.markIntroSeen();
          profile.chooseFirstCompanion(command.petId);
          if (command.petId !== settings.pet) {
            settings.pet = command.petId;
            showPetIfHidden();
          }
          options.say(petInfo(command.petId).greeting);
          break;
        }
      }
    },
  };
  return service;
}
