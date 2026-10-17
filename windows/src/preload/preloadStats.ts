// Il ponte sicuro della finestra delle statistiche.

import { contextBridge, ipcRenderer } from "electron";
import { STATS_CHANNEL } from "../shared/statsApi.ts";
import type { StatsApi, StatsData } from "../shared/statsApi.ts";

const api: StatsApi = {
  getData: () => ipcRenderer.invoke(STATS_CHANNEL.getData) as Promise<StatsData>,
  onData: (callback) => {
    ipcRenderer.on(STATS_CHANNEL.data, (_event, data: StatsData) => callback(data));
  },
  editSession: (edit) => ipcRenderer.send(STATS_CHANNEL.edit, edit),
  deleteSession: (id) => ipcRenderer.send(STATS_CHANNEL.delete, id),
  exportCsv: () => ipcRenderer.send(STATS_CHANNEL.exportCsv),
  deleteAll: () => ipcRenderer.send(STATS_CHANNEL.deleteAll),
  back: () => ipcRenderer.send(STATS_CHANNEL.back),
};

contextBridge.exposeInMainWorld("focusfriendsStats", api);
