// Compila il processo principale, il ponte e la pagina in `dist/` (esbuild). `node tools/build.mjs`, o `--watch` non c'è ancora.

import { build } from "esbuild";
import { copyFileSync, mkdirSync } from "node:fs";
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

mkdirSync(out("renderer"), { recursive: true });
for (const file of ["index.html", "overlay.css"]) copyFileSync(src("renderer", file), out("renderer", file));
