// Il focus scade e compare «+5 minuti»: un clic sul pulsante lo prolunga; poi la sessione si interrompe (dura circa 70 secondi).
module.exports = async ({ js, sleep, shot, timer, mouse }) => {
  const state = async () => JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  await sleep(1500);
  const svc = timer();
  svc.run(() => svc.engine.startFocus(1, "Chimica"));
  await sleep(3000);
  let s = await state();
  console.log("durante il focus:", JSON.stringify({ growth: s.growth, w: s.width, clock: s.clock.shown, speaking: s.speaking }));
  await shot("focus");
  await sleep(58500);          // 61,5 s: scaduto
  s = await state();
  console.log("scaduto:", JSON.stringify({ prompt: s.prompt, label: s.timer.label, text: s.timer.remainingText, grace: s.timer.graceSecondsLeft }));
  await shot("scaduto");
  const prompt = await js("(() => { const r = document.querySelector('.extend').getBoundingClientRect(); return JSON.stringify({x: r.left, y: r.top, w: r.width, h: r.height}); })()");
  const r = JSON.parse(prompt);
  console.log("pulsante:", prompt);
  const cx = Math.round(r.x + r.w / 2), cy = Math.round(r.y + r.h / 2);
  mouse("mouseMove", cx, cy); await sleep(200);
  mouse("mouseDown", cx, cy); await sleep(60); mouse("mouseUp", cx, cy);
  await sleep(1200);
  s = await state();
  console.log("dopo il tocco:", JSON.stringify({ prompt: s.prompt, label: s.timer.label, text: s.timer.remainingText, focusMinutes: s.timer.focusMinutes }));
  await shot("esteso");
  svc.run(() => svc.engine.stop());
  await sleep(500);
  console.log("sessioni:", JSON.stringify(svc.log.sessions.map((x) => ({ s: x.seconds, c: x.completed, p: x.plannedMinutes }))));
};
