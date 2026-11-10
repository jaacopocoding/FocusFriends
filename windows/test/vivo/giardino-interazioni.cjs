// I compagni usano le cose (GardenInteractions): per ogni scena del gattino, la si mostra subito (window.__garden.showInteraction) e si fa la
// schermata; poi si lascia passeggiare il gattino per vedere se ne sceglie una da solo.
// Con FF_SOLO_DA_SOLO=1 salta le scene mostrate e aspetta che il gattino ne scelga una da solo.
//   FF_PROFILO='{"version":1,"introSeen":true,"firstCompanion":"gattino","unlocked":["gattino"]}' test/vivo/esegui.sh giardino-interazioni.cjs 200
const fs = require("fs");
module.exports = async ({ sleep, gardenWindow, garden, settings }) => {
  const out = process.env.FF_SELFTEST_OUT;
  settings["values"]["gardenHour"] = 14;
  settings["values"]["gardenSeason"] = "spring";
  // ogni cosa sulla prima tessera libera, cominciando da quella detta
  const items = [["cesto-cuscino", 4, 4], ["tiragraffi", 7, 3], ["panchina", 6, 6], ["amaca", 3, 6]];
  for (const [id, col, row] of items) {
    garden.drops.found[id] = 1;
    let done = false;
    for (let k = 0; k < 64 && !done; k += 1) {
      const at = { col: (col + (k % 8)) % 8, row: (row + Math.floor(k / 8)) % 8 };
      if (garden.canPlace(id, at, false, "gattino")) { garden.place(id, at, false, "gattino"); done = true; }
    }
  }
  gardenWindow.show();
  for (let i = 0; i < 60 && !(gardenWindow.window && !gardenWindow.window.isDestroyed()); i += 1) await sleep(50);
  const wc = () => gardenWindow.window.webContents;
  const run = (code) => wc().executeJavaScript(code);
  const shot = async (name) => fs.writeFileSync(`${out}/${name}.png`, (await wc().capturePage()).toPNG());
  await sleep(2500);
  if (!process.env.FF_SOLO_DA_SOLO) {
    for (const [id] of items) {
      await run(`window.__garden.showInteraction("gattino", ${JSON.stringify(id)})`);
      await sleep(900);
      await shot(`scena-${id}`);
    }
  }
  // da solo
  for (let i = 0; i < 170; i += 1) {
    await sleep(1000);
    const scene = await run("(() => { const w = window.__garden.life.walkers[0]; return w && w.scene ? w.scene.interaction.item : null; })()");
    if (scene) { console.log(`${i + 1} s: il gattino usa ${scene}`); await sleep(800); await shot(`da-solo-${scene}`); break; }
  }
};
