// Prepara le risorse che l'installer porta con sé (`build/assets` e `build/resources`): solo le immagini, le frasi e i brani che l'app usa
// davvero (quelli di `data/pets.json`, il fumetto, le frasi dei compagni, la musica), senza i fogli originali. `node tools/prepara-risorse.mjs`.

import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const assets = join(root, "..", "assets");
const stage = join(root, "build");
rmSync(stage, { recursive: true, force: true });
mkdirSync(join(stage, "assets"), { recursive: true });

const wanted = new Set(["bubble.png"]);
const { pets } = JSON.parse(readFileSync(join(root, "data", "pets.json"), "utf8"));
for (const pet of pets) {
  pet.images.forEach((path) => wanted.add(path));
  pet.focusGrowthImages.forEach((path) => wanted.add(path));
  if (pet.picked) wanted.add(pet.picked.image);
  wanted.add(`frasi_${pet.id}.txt`);
}
for (const name of readdirSync(join(assets, "music"))) if (/\.(m4a|mp3|aac|wav|flac)$/i.test(name)) wanted.add(`music/${name}`);

let missing = 0;
for (const path of wanted) {
  const from = join(assets, path);
  if (!existsSync(from)) { console.error(`manca assets/${path}`); missing += 1; continue; }
  mkdirSync(dirname(join(stage, "assets", path)), { recursive: true });
  cpSync(from, join(stage, "assets", path));
}
if (missing > 0) process.exit(1);

mkdirSync(join(stage, "resources"), { recursive: true });
cpSync(join(root, "resources", "fine-focus.wav"), join(stage, "resources", "fine-focus.wav"));
// (i caratteri scelti andranno in resources/fonts quando ci saranno)
if (existsSync(join(root, "resources", "fonts"))) cpSync(join(root, "resources", "fonts"), join(stage, "resources", "fonts"), { recursive: true });

const size = (dir) => readdirSync(dir, { withFileTypes: true }).reduce((total, e) => total + (e.isDirectory() ? size(join(dir, e.name)) : statSync(join(dir, e.name)).size), 0);
console.log(`Preparati ${wanted.size} file di assets (${(size(join(stage, "assets")) / 1e6).toFixed(1)} MB) e le risorse (${(size(join(stage, "resources")) / 1e6).toFixed(2)} MB)`);
