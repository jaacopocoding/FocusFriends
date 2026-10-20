// Pioggia, vento, marrone e musica: anteprima, focus, focus fermo e ripreso; i livelli reali dell'audio (volume basso).
module.exports = async ({ js, sleep, timer, settings, metrics }) => {
  const audio = async () => JSON.parse(await js("JSON.stringify(window.__ff.audio())"));
  await sleep(1500);
  console.log("all'inizio:", JSON.stringify(await audio()));
  settings.ambientVolume = 0.05;                 // piano: durante la prova suona davvero
  await sleep(300);
  // anteprima della pioggia (fuori dal focus)
  settings.ambientSound = "rain";
  await sleep(2500);
  let a = await audio();
  console.log("anteprima pioggia:", a.ambient.state, "livello", a.ambient.level.toFixed(4));
  await sleep(2500);
  a = await audio();
  console.log("dopo l'anteprima:", a.ambient.state, "livello", a.ambient.level.toFixed(4));
  // un focus con la pioggia
  const svc = timer();
  svc.run(() => svc.engine.startFocus(25));
  await sleep(4000);
  a = await audio();
  console.log("focus + pioggia:", a.ambient.state, "livello", a.ambient.level.toFixed(4), "focusActive", a.ambient.focusActive);
  metrics("misure-pioggia-1");
  await sleep(10000);
  metrics("misure-pioggia-2");
  // fermo: si spegne
  svc.run(() => svc.engine.toggleFocusPause());
  await sleep(3000);
  a = await audio();
  console.log("focus fermo:", a.ambient.state, "livello", a.ambient.level.toFixed(4));
  svc.run(() => svc.engine.toggleFocusPause());
  await sleep(3000);
  a = await audio();
  console.log("ripreso:", "livello", a.ambient.level.toFixed(4));
  // vento e marrone
  for (const sound of ["wind", "brown"]) {
    settings.ambientSound = sound;
    await sleep(3500);
    a = await audio();
    console.log(sound + ":", "livello", a.ambient.level.toFixed(4), a.ambient.sound);
  }
  // musica: spegne il suono
  settings.musicVolume = 0.05;
  settings.ambientSound = "none";
  settings.musicSource = "bundled";
  await sleep(3500);
  a = await audio();
  console.log("musica:", JSON.stringify(a.music), "suono:", a.ambient.sound);
  svc.run(() => svc.engine.stop());
  await sleep(4000);
  a = await audio();
  console.log("dopo lo stop:", JSON.stringify(a.music), a.ambient.state);
  settings.musicSource = "off";
};
