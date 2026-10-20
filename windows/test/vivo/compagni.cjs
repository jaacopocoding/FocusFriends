// Cambia compagno, accende e spegne il movimento, misure.
module.exports = async ({ js, sleep, shot, settings, metrics }) => {
  const state = async () => JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  await sleep(1200);
  for (const id of ["pianty", "porcellino", "ciccio", "gattino", "pianty"]) {
    settings.pet = id;
    await sleep(900);
    const s = await state();
    console.log(id, JSON.stringify({ pet: s.pet, left: Math.round(s.left), top: Math.round(s.top), w: s.width, h: s.height }));
    await shot("pet-" + id);
  }
  console.log("movimento spento");
  settings.movement = false;
  await sleep(500);
  const a = await state(); await sleep(3000); const b = await state();
  console.log("fermo:", a.left === b.left && a.top === b.top);
  settings.movement = true;
  await sleep(3500);
  const c = await state();
  console.log("riacceso, si è mosso:", c.left !== b.left);
  metrics("misure");
};
