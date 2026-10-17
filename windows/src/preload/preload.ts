// Il ponte sicuro: la pagina non ha Node né Electron, solo queste funzioni.

import { contextBridge, ipcRenderer } from "electron";
import { CHANNEL } from "../shared/api.ts";
import type { CardData } from "../core/card.ts";
import type { PomodoroEvent, PomodoroSnapshot } from "../core/pomodoro.ts";
import type { AddTimerResult } from "../core/rules.ts";
import type { CardOpenRequest, FocusFriendsApi, SettingsSnapshot } from "../shared/api.ts";

const api: FocusFriendsApi = {
  getSettings: () => ipcRenderer.invoke(CHANNEL.getSettings) as Promise<SettingsSnapshot>,
  onSettingsChanged: (callback) => {
    ipcRenderer.on(CHANNEL.settingsChanged, (_event, settings: SettingsSnapshot) => callback(settings));
  },
  setInteractive: (interactive) => ipcRenderer.send(CHANNEL.setInteractive, interactive),
  nextPhrase: (petId) => ipcRenderer.invoke(CHANNEL.nextPhrase, petId) as Promise<string>,
  onVisibilityChanged: (callback) => {
    ipcRenderer.on(CHANNEL.visibilityChanged, (_event, visible: boolean) => callback(visible));
  },
  getTimerState: () => ipcRenderer.invoke(CHANNEL.getTimerState) as Promise<PomodoroSnapshot>,
  onTimerState: (callback) => {
    ipcRenderer.on(CHANNEL.timerState, (_event, state: PomodoroSnapshot) => callback(state));
  },
  onTimerEvent: (callback) => {
    ipcRenderer.on(CHANNEL.timerEvent, (_event, event: PomodoroEvent) => callback(event));
  },
  extendFocus: () => ipcRenderer.send(CHANNEL.timerExtend),
  getCardData: () => ipcRenderer.invoke(CHANNEL.cardData) as Promise<CardData>,
  cardCommand: (command) => ipcRenderer.send(CHANNEL.cardCommand, command),
  addCustomTimer: (kind, minutes) => ipcRenderer.invoke(CHANNEL.cardAddTimer, kind, minutes) as Promise<AddTimerResult>,
  cardOpened: (open) => ipcRenderer.send(CHANNEL.cardOpened, open),
  onCardToggle: (callback) => {
    ipcRenderer.on(CHANNEL.cardToggle, (_event, request: CardOpenRequest) => callback(request));
  },
  onCardReopen: (callback) => {
    ipcRenderer.on(CHANNEL.cardReopen, () => callback());
  },
  onSpeakNow: (callback) => {
    ipcRenderer.on(CHANNEL.speakNow, () => callback());
  },
  ready: () => ipcRenderer.send(CHANNEL.rendererReady),
  selfTest: process.env["FF_SELFTEST"] !== undefined,
};

contextBridge.exposeInMainWorld("focusfriends", api);
