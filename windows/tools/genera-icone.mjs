// Rifà src/renderer/card/icons.generated.ts: le icone (Lucide, licenza ISC) che la scheda usa al posto dei simboli di sistema
// del Mac. Si rilancia solo se cambia l'elenco: `node tools/genera-icone.mjs`.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
// nome nella scheda → nome in Lucide
const icons = {
  chat: "message-circle", rain: "cloud-rain", brown: "audio-waveform", wind: "wind", mute: "volume-x", music: "music",
  walk: "footprints", smile: "smile", eye: "eye", eyeOff: "eye-off", leaf: "leaf", chart: "chart-column", back: "chevron-left",
  lock: "lock", play: "play", checkCircle: "circle-check", trash: "trash-2", stop: "square", skip: "skip-forward", plus: "plus",
  more: "ellipsis", flame: "flame", snowflake: "snowflake", forward: "chevron-right", up: "chevron-up", down: "chevron-down",
};

const entries = Object.entries(icons).map(([name, file]) => {
  const svg = readFileSync(join(root, "node_modules", "lucide-static", "icons", `${file}.svg`), "utf8");
  const inner = svg.replace(/^[\s\S]*?<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "").replace(/\s*\n\s*/g, "").trim();
  return `  ${name}: ${JSON.stringify(inner)},`;
});

writeFileSync(join(root, "src", "renderer", "card", "icons.generated.ts"),
  `// Generato da tools/genera-icone.mjs (icone Lucide, licenza ISC): non si modifica a mano.\n\nexport const ICONS = {\n${entries.join("\n")}\n} as const;\n\nexport type IconName = keyof typeof ICONS;\n`);
console.log(`Scritte ${entries.length} icone`);
