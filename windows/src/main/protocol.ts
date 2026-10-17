// Il protocollo `ff://app/`: serve alla pagina i suoi file (`/index.html`, `/overlay.js`) e le immagini (`/assets/…`)
// senza dare accesso al disco. Una sola origine: le immagini si possono leggere dal canvas senza permessi speciali.

import { net, protocol } from "electron";
import { resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";

export const SCHEME = "ff";

/** Va chiamata prima che l'app sia pronta. */
export function registerScheme(): void {
  protocol.registerSchemesAsPrivileged([{ scheme: SCHEME, privileges: { standard: true, secure: true, supportFetchAPI: true } }]);
}

export function handleScheme(roots: { assets: string; renderer: string }): void {
  protocol.handle(SCHEME, (request) => {
    const url = new URL(request.url);
    if (url.host !== "app") return new Response("not found", { status: 404 });
    const pathname = decodeURIComponent(url.pathname);
    const [root, relative] = pathname.startsWith("/assets/")
      ? [roots.assets, pathname.slice("/assets/".length)]
      : [roots.renderer, pathname === "/" ? "index.html" : pathname.slice(1)];
    const file = resolve(root, relative);
    // Mai fuori dalla cartella indicata (niente «../»).
    if (file !== root && !file.startsWith(root + sep)) return new Response("forbidden", { status: 403 });
    return net.fetch(pathToFileURL(file).toString());
  });
}
