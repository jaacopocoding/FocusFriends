// Avvia un focus, lo allunga, lo ferma e lo riprende, poi lo interrompe: stato della scena, orologio, crescita del compagno, misure di memoria e processore.
module.exports = async ({ js, sleep, shot, timer, settings, metrics }) => {
  const state = async () => JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  await sleep(1500);
  const svc = timer();
  svc.run(() => svc.engine.startFocus(25, "Anatomia"));
  await sleep(1500);
  let s = await state();
  console.log("dopo l'avvio:", JSON.stringify({ shiftedUp: s.shiftedUp, clock: s.clock, top: Math.round(s.top), growth: s.growth, speaking: s.speaking, text: s.timer && s.timer.remainingText }));
  await sleep(1200);
  await shot("focus-avvio");
  console.log("progresso:", (await state()).timer.growthProgress);
  svc.run(() => svc.engine.addMinutes());
  await sleep(600);
  svc.run(() => svc.engine.toggleFocusPause());
  await sleep(800);
  console.log("fermo:", (await state()).timer.label);
  await shot("focus-fermo");
  svc.run(() => svc.engine.toggleFocusPause());
  await sleep(300);
  svc.run(() => svc.engine.stop());
  await sleep(1200);
  s = await state();
  console.log("dopo lo stop:", JSON.stringify({ shiftedUp: s.shiftedUp, clock: s.clock, top: Math.round(s.top), growth: s.growth, phase: s.timer.phase }));
  metrics("misure");
};
