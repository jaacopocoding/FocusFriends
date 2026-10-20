// Il compagno nascosto: il sottofondo continua e il timer pure.
module.exports = async ({ js, sleep, timer, settings, card, metrics }) => {
  const audio = async () => JSON.parse(await js("JSON.stringify(window.__ff.audio())"));
  await sleep(1500);
  settings.ambientVolume = 0.05;
  settings.ambientSound = "wind";
  await sleep(300);
  const svc = timer();
  svc.run(() => svc.engine.startFocus(25));
  await sleep(3500);
  console.log("visibile, livello:", (await audio()).ambient.level.toFixed(4));
  card.command({ name: "toggleVisibility" });          // nascondo il compagno: la finestra non si vede più
  await sleep(4000);
  console.log("nascosto, livello:", (await audio()).ambient.level.toFixed(4), "timer:", svc.snapshot().remainingText);
  card.command({ name: "toggleVisibility" });
  svc.run(() => svc.engine.stop());
  await sleep(300);
};
