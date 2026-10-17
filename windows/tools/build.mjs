// Compila il processo principale, il ponte e la pagina in `dist/` (esbuild). `node tools/build.mjs`, o `--watch` non c'è ancora.

import { build } from "esbuild";
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = (...parts) => join(root, "dist", ...parts);
const src = (...parts) => join(root, "src", ...parts);

const common = { bundle: true, sourcemap: true, logLevel: "info", loader: { ".json": "json" } };

await build({
  ...common, entryPoints: [src("main", "main.ts")], outfile: out("main", "main.cjs"),
  platform: "node", format: "cjs", target: "node22", external: ["electron"],
});
await build({
  ...common, entryPoints: [src("preload", "preload.ts")], outfile: out("preload", "preload.cjs"),
  platform: "node", format: "cjs", target: "node22", external: ["electron"],
});
await build({
  ...common, entryPoints: [src("renderer", "overlay.ts")], outfile: out("renderer", "overlay.js"),
  platform: "browser", format: "iife", target: "chrome140",
});

// Il generatore dei rumori: gira nel thread audio, in un file a parte.
await build({
  ...common, entryPoints: [src("renderer", "audio", "noiseWorklet.ts")], outfile: out("renderer", "noise-worklet.js"),
  platform: "browser", format: "iife", target: "chrome140",
});

mkdirSync(out("renderer"), { recursive: true });
copyFileSync(src("renderer", "index.html"), out("renderer", "index.html"));
// Un solo foglio di stile per la pagina: quello della scena e quello della scheda.
writeFileSync(out("renderer", "overlay.css"), ["overlay.css", join("card", "card.css")].map((f) => readFileSync(src("renderer", f), "utf8")).join("\n"));
