// Apre e chiude la scheda dal compagno (schermata della pagina principale).
module.exports = async ({ js, sleep, shot, timer, settings }) => {
  const state = async () => JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  await sleep(1500);
  await js("window.__ff.openCard()");
  await sleep(900);
  console.log("scheda aperta:", await js("window.__ff.cardOpen()"));
  await shot("scheda-principale");
  await js("window.__ff.closeCard()");
  await sleep(300);
  console.log("scheda chiusa:", !(await js("window.__ff.cardOpen()")));
};
