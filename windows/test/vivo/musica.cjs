// Una cartella di musica (FF_PROVA_MUSICA=<cartella>): il brano dopo il primo, cartella che sparisce, musica spenta.
const folder = process.env.FF_PROVA_MUSICA;
module.exports = async ({ js, sleep, timer, settings }) => {
  const audio = async () => JSON.parse(await js("JSON.stringify(window.__ff.audio())"));
  await sleep(1500);
  settings.musicVolume = 0.05;
  settings.musicFolder = folder;
  settings.musicSource = "folder";
  await sleep(3500);
  let a = await audio();
  console.log("cartella:", JSON.stringify(a.music));
  const first = a.music.title;
  // fine del brano: ne parte un altro (anteprima: 5 s, poi si ferma)
  const svc = timer();
  svc.run(() => svc.engine.startFocus(25));
  await sleep(1500);
  await js("window.__ff.skipMusic()");
  await sleep(2500);
  a = await audio();
  console.log("dopo la fine del primo:", JSON.stringify(a.music), "primo era:", first);
  // cartella inesistente: nessun brano, silenzio
  settings.musicFolder = folder + "/non-esiste";
  await sleep(2500);
  a = await audio();
  console.log("cartella inesistente:", JSON.stringify(a.music));
  svc.run(() => svc.engine.stop());
  settings.musicSource = "off";
  await sleep(500);
};
