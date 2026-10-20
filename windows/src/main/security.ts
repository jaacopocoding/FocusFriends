// Le pagine dell'app non devono mai portare altrove: niente navigazione verso altri indirizzi, niente finestre nuove, niente permessi
// (microfono, fotocamera, notifiche, posizione…). Non c'è motivo che succeda (la pagina non ha collegamenti e il suo CSP chiude la rete),
// ma se un giorno una pagina ricevesse del contenuto strano, qui si ferma.

import { app } from "electron";
import type { Session } from "electron";
import { describeUrl, isAppUrl } from "../core/urls.ts";

/** Vale per ogni finestra, presente e futura. `report` scrive nel registro dell'app (solo schema e sito dell'indirizzo, mai il percorso). */
export function lockDownWindows(report: (message: string) => void): void {
  app.on("web-contents-created", (_event, contents) => {
    // Da sviluppo gli strumenti di Chromium (devtools://) possono muoversi; nell'app installata no.
    const allowed = (url: string): boolean => isAppUrl(url) || (!app.isPackaged && url.startsWith("devtools:"));
    const guard = (event: { url: string; preventDefault(): void }): void => {
      if (allowed(event.url)) return;
      event.preventDefault();
      report(`navigazione rifiutata verso ${describeUrl(event.url)}`);
    };
    contents.on("will-navigate", guard);
    contents.on("will-frame-navigate", guard);
    contents.on("will-redirect", guard);
    contents.setWindowOpenHandler(({ url }) => {
      report(`finestra nuova rifiutata: ${describeUrl(url)}`);
      return { action: "deny" };
    });
    // L'app non usa <webview>.
    contents.on("will-attach-webview", (event) => event.preventDefault());
  });
}

/** Nessun permesso a nessuna pagina: l'app non ne usa. Da chiamare quando l'app è pronta. */
export function denyPermissions(session: Session, report: (message: string) => void): void {
  session.setPermissionRequestHandler((_contents, permission, callback) => {
    report(`permesso rifiutato: ${permission}`);
    callback(false);
  });
  session.setPermissionCheckHandler(() => false);
  session.setDevicePermissionHandler(() => false);
}
