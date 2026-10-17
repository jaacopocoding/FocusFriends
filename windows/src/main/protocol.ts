// Il protocollo `ff://app/`: serve alla pagina i suoi file (`/index.html`, `/overlay.js`), le immagini (`/assets/…`) e i suoni (`/resources/…`)
// senza dare accesso al disco. Una sola origine: le immagini si possono leggere dal canvas senza permessi speciali.

import { net, protocol } from "electron";
import { createReadStream, statSync } from "node:fs";
import { extname, resolve, sep } from "node:path";
import { Readable } from "node:stream";
import { pathToFileURL } from "node:url";

export const SCHEME = "ff";

/** Va chiamata prima che l'app sia pronta. */
export function registerScheme(): void {
  protocol.registerSchemesAsPrivileged([{ scheme: SCHEME, privileges: { standard: true, secure: true, supportFetchAPI: true } }]);
}

const AUDIO_TYPES: Record<string, string> = {
  ".m4a": "audio/mp4", ".aac": "audio/aac", ".mp3": "audio/mpeg", ".wav": "audio/wav", ".flac": "audio/flac",
  ".aif": "audio/aiff", ".aiff": "audio/aiff", ".caf": "audio/x-caf",
};

/** Un file audio, anche a pezzi (`Range`): il lettore ne ha bisogno per saltare e per i file con l'indice in fondo. */
function serveAudio(file: string, request: Request): Response {
  let size: number;
  try {
    size = statSync(file).size;
  } catch {
    return new Response("not found", { status: 404 });
  }
  const headers: Record<string, string> = {
    "Content-Type": AUDIO_TYPES[extname(file).toLowerCase()] ?? "application/octet-stream", "Accept-Ranges": "bytes",
  };
  const match = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get("range") ?? "");
  if (!match) {
    return new Response(Readable.toWeb(createReadStream(file)) as ReadableStream, { status: 200, headers: { ...headers, "Content-Length": String(size) } });
  }
  let start = match[1] === "" ? NaN : Number(match[1]);
  let end = match[2] === "" ? NaN : Number(match[2]);
  if (Number.isNaN(start)) { start = Math.max(size - end, 0); end = size - 1; }       // «bytes=-N»: gli ultimi N
  else if (Number.isNaN(end) || end >= size) end = size - 1;
  if (start > end || start >= size) return new Response("range", { status: 416, headers: { "Content-Range": `bytes */${size}` } });
  return new Response(Readable.toWeb(createReadStream(file, { start, end })) as ReadableStream, {
    status: 206, headers: { ...headers, "Content-Range": `bytes ${start}-${end}/${size}`, "Content-Length": String(end - start + 1) },
  });
}

export function handleScheme(roots: { assets: string; renderer: string; resources: string; musicFile: (version: number, id: number) => string | null }): void {
  protocol.handle(SCHEME, (request) => {
    const url = new URL(request.url);
    if (url.host !== "app") return new Response("not found", { status: 404 });
    const pathname = decodeURIComponent(url.pathname);
    // La musica: `/music/<versione>/<numero>`, solo i brani dell'elenco valido adesso.
    const track = /^\/music\/(\d+)\/(\d+)$/.exec(pathname);
    if (track) {
      const file = roots.musicFile(Number(track[1]), Number(track[2]));
      return file === null ? new Response("not found", { status: 404 }) : serveAudio(file, request);
    }
    const [root, relative] = pathname.startsWith("/assets/")
      ? [roots.assets, pathname.slice("/assets/".length)]
      : pathname.startsWith("/resources/")
        ? [roots.resources, pathname.slice("/resources/".length)]
        : [roots.renderer, pathname === "/" ? "index.html" : pathname.slice(1)];
    const file = resolve(root, relative);
    // Mai fuori dalla cartella indicata (niente «../»).
    if (file !== root && !file.startsWith(root + sep)) return new Response("forbidden", { status: 403 });
    // Un file che non c'è non deve far cadere niente: la pagina riceve un 404.
    return net.fetch(pathToFileURL(file).toString()).catch(() => new Response("not found", { status: 404 }));
  });
}
