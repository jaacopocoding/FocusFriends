// Due schermi finti (serve FF_FAKE_DISPLAYS): spostamenti, trascinamento oltre il bordo, schermo scollegato.
module.exports = async ({ js, sleep, win, stage, shot }) => {
  const state = async () => JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  const origin = async () => JSON.parse(await js("JSON.stringify(window.__ff.stageOrigin())"));
  await sleep(1800);
  console.log("schermi:", stage.displays().map((d) => `${d.id}:${JSON.stringify(d.workArea)}`).join(" | "));
  console.log("all'inizio:", JSON.stringify(win.getBounds()), "origine", JSON.stringify(await origin()));
  let s = await state();
  console.log("compagno:", JSON.stringify({ left: Math.round(s.left), top: Math.round(s.top), scene: s.scene }));
  // sull'altro schermo, dal menu: riparte da terra
  stage.moveTo(2, false);
  await sleep(1000);
  s = await state();
  console.log("sul secondo:", JSON.stringify(win.getBounds()), "origine", JSON.stringify(await origin()), "compagno", JSON.stringify({ left: Math.round(s.left), top: Math.round(s.top), scene: s.scene }));
  await shot("secondo-schermo");
  // trascinato: resta dov'è sullo schermo (coordinate globali)
  const before = await state();
  const globalBefore = { x: (await origin()).x + before.left, y: (await origin()).y + before.top };
  stage.moveTo(1, true);
  await sleep(1000);
  s = await state();
  const globalAfter = { x: (await origin()).x + s.left, y: (await origin()).y + s.top };
  console.log("di nuovo sul primo, posizione globale prima/dopo:", JSON.stringify(globalBefore), JSON.stringify(globalAfter));
  // lo schermo del compagno sparisce: torna sul principale
  stage.moveTo(2, false); await sleep(600);
  console.log("scollego il secondo (finto): corrente prima", stage.current.id);
};
