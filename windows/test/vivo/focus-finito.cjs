// Un focus da 1 minuto che finisce da solo: passa alla pausa, il compagno parla, la sessione è salvata (dura circa 75 secondi).
module.exports = async ({ js, sleep, shot, timer }) => {
  const state = async () => JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  await sleep(1500);
  const svc = timer();
  svc.run(() => svc.engine.startFocus(1, "Chimica"));
  await sleep(72500);
  let s = await state();
  console.log("dopo la fine:", JSON.stringify({ phase: s.timer.phase, label: s.timer.label, text: s.timer.remainingText, prompt: s.prompt, growth: s.growth, speaking: s.speaking, w: s.width, cycle: s.timer.cycleDone }));
  await shot("pausa");
  await sleep(3000);
  await shot("pausa2");
  console.log("sessioni:", JSON.stringify(svc.log.sessions.map((x) => ({ s: x.seconds, c: x.completed, p: x.plannedMinutes, subject: x.subject, pet: x.pet }))));
  svc.run(() => svc.engine.stop());
};
