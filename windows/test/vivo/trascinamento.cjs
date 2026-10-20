// Il compagno e i clic: la finestra lascia passare i clic sul vuoto, li riceve sopra il disegno, il trascinamento in aria e la ricaduta.
module.exports = async ({ js, sleep, mouse, shot, metrics, interactions }) => {
  await sleep(1500);
  const state = async () => JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  const hit = async (x, y) => js(`window.__ff.hit(${x}, ${y})`);
  let s = await state();
  console.log("stato iniziale", JSON.stringify(s));
  // un punto del compagno che sia davvero opaco
  let px = null, py = null;
  for (let fy = 0.9; fy > 0.2 && px === null; fy -= 0.05)
    for (let fx = 0.2; fx < 0.9 && px === null; fx += 0.05) {
      const x = Math.round(s.left + s.width * fx), y = Math.round(s.top + s.height * fy);
      if (await hit(x, y)) { px = x; py = y; }
    }
  console.log("punto opaco", px, py);
  // un punto vuoto, in alto a sinistra della scena
  console.log("punto vuoto colpisce?", await hit(50, 50));

  mouse("mouseMove", 50, 50); await sleep(150);
  console.log("lontano:", JSON.stringify(interactions));
  mouse("mouseMove", px, py); await sleep(150);
  console.log("sopra il compagno:", JSON.stringify(interactions));
  mouse("mouseMove", 50, 50); await sleep(150);
  console.log("di nuovo lontano:", JSON.stringify(interactions));

  // trascinamento
  mouse("mouseMove", px, py); await sleep(100);
  mouse("mouseDown", px, py); await sleep(100);
  mouse("mouseMove", px - 20, py - 30); await sleep(150);
  mouse("mouseMove", px - 200, py - 200); await sleep(300);
  s = await state();
  console.log("in aria:", JSON.stringify(s));
  await shot("in-aria");
  mouse("mouseMove", px - 400, py - 250); await sleep(200);
  mouse("mouseUp", px - 400, py - 250); await sleep(400);
  s = await state();
  console.log("rilasciato:", JSON.stringify(s));
  await sleep(2500);
  s = await state();
  console.log("dopo 2,5 s:", JSON.stringify(s));
  await shot("dopo");
  console.log("eventi:", JSON.stringify(interactions));
  metrics("misure");
};
