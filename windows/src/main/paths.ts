// Dove stanno i dati e le immagini.

import { join } from "node:path";
import type { App } from "electron";
import { dataDirectoryOverride } from "../core/environment.ts";

/**
 * La cartella dei dati. Su Windows è `%APPDATA%\FocusFriends` (FORMATI.md §1). Con `FF_DATA_DIR` si sceglie un'altra cartella, ma
 * solo dai sorgenti o durante le prove (`FF_SELFTEST`): l'app installata ignora la variabile.
 * Sugli altri sistemi (cioè quando si prova sul Mac) NON si usa mai la cartella dell'app per Mac: si lavora in una
 * cartella di prova a parte, così i dati veri non rischiano niente.
 */
export function dataDirectory(app: App): string {
  const override = dataDirectoryOverride(process.env, app.isPackaged);
  if (override) return override;
  if (process.platform === "win32") return join(app.getPath("appData"), "FocusFriends");
  return join(app.getPath("userData"), "dati-di-prova");
}

/** Le immagini e le frasi incluse (la cartella `assets/` del progetto, in comune con l'app per Mac). */
export function assetsDirectory(app: App): string {
  return app.isPackaged ? join(process.resourcesPath, "assets") : join(app.getAppPath(), "..", "assets");
}

/** I file della pagina (HTML, CSS, JavaScript compilato). */
export function rendererDirectory(app: App): string {
  return join(app.getAppPath(), "dist", "renderer");
}

/** Le risorse solo di Windows (per esempio il suono di fine focus). */
export function resourcesDirectory(app: App): string {
  return app.isPackaged ? join(process.resourcesPath, "resources") : join(app.getAppPath(), "resources");
}
