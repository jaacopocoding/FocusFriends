// Sleep e risveglio simulati con pioggia e musica.
module.exports = async ({ js, sleep, timer, settings, power }) => {
  const audio = async () => JSON.parse(await js("JSON.stringify(window.__ff.audio())"));
  await sleep(1500);
  settings.ambientVolume = 0.05;
  settings.ambientSound = "rain";
  await sleep(300);
  const svc = timer();
  svc.run(() => svc.engine.startFocus(25));
  await sleep(4000);
  let a = await audio();
  console.log("1 focus + pioggia:", a.ambient.state, "livello", a.ambient.level.toFixed(4));

  // il sistema ferma il motore (cuffie scollegate): si riaccende da solo e col risveglio
  await js("window.__ff.interruptAudio()");
  await sleep(150);
  power("suspend");
  await sleep(1500);
  power("resume");
  await sleep(2500);
  a = await audio();
  console.log("2 dopo sleep e risveglio:", a.ambient.state, "livello", a.ambient.level.toFixed(4));

  // fuori dal focus un risveglio non fa partire niente
  svc.run(() => svc.engine.toggleFocusPause());
  await sleep(3500);
  a = await audio();
  console.log("3 focus fermo:", a.ambient.state, "livello", a.ambient.level.toFixed(4));
  power("resume");
  await sleep(2000);
  a = await audio();
  console.log("4 risveglio da fermo: ", a.ambient.state, "livello", a.ambient.level.toFixed(4), "(deve restare zero)");
  svc.run(() => svc.engine.toggleFocusPause());
  await sleep(2500);

  // musica: il brano si ferma da solo e al risveglio riparte
  settings.ambientSound = "none";
  settings.musicVolume = 0.05;
  settings.musicSource = "bundled";
  await sleep(3500);
  a = await audio();
  console.log("5 musica:", JSON.stringify(a.music));
  await js("window.__ff.interruptAudio()");
  await sleep(300);
  a = await audio();
  console.log("6 musica fermata dal sistema:", a.music.playing);
  power("resume");
  await sleep(2500);
  a = await audio();
  console.log("7 dopo il risveglio:", JSON.stringify(a.music));
  svc.run(() => svc.engine.stop());
  await sleep(3500);
  a = await audio();
  console.log("8 dopo lo stop:", a.music.playing);
  power("resume");
  await sleep(1500);
  a = await audio();
  console.log("9 risveglio dopo lo stop: musica", a.music.playing, "(deve restare ferma)");
  settings.musicSource = "off";
};
