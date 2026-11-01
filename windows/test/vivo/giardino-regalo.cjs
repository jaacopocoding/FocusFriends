// Il giardino (G4): a fine focus la figurina. Con `quickGifts` un focus da un minuto conta e vale un'ora, quindi il primo trova la prima
// figurina: la frase di fine focus la dice, la figurina compare accanto al compagno, e nella scheda c'è la riga della prossima. (Circa 90 secondi.)
//   FF_IMPOSTAZIONI='{"quickGifts":true}' test/vivo/esegui.sh giardino-regalo.cjs 150
module.exports = async ({ js, sleep, shot, timer, garden, card }) => {
  await sleep(1500);
  const svc = timer();
  const before = Object.keys(garden.drops.found).length;
  console.log("prima:", JSON.stringify({ trovate: before, mancano: garden.minutesToNextGift }));
  const said = [];
  svc.engine.onEvent((event) => { if (event.type === "say") said.push(event.text); });
  svc.run(() => svc.engine.startFocus(1, "Chimica"));
  await sleep(71500);  // il minuto e i 10 secondi di «Ancora 5 minuti?»
  // la figurina compare insieme alla frase: le schermate a due momenti della girata
  await sleep(900);
  await shot("regalo-1");
  await sleep(1500);
  await shot("regalo-2");
  const found = Object.keys(garden.drops.found).filter((id) => !["margherite", "trifoglio", "mughetti"].includes(id));
  console.log("dopo:", JSON.stringify({ trovate: Object.keys(garden.drops.found).length, nuove: [...garden.unseen], mancano: garden.minutesToNextGift, riserva: garden.drops.studyBank, nuovaSullIsola: garden.allPlacements.some((p) => found.includes(p.item)) }));
  console.log("frase:", JSON.stringify(said));
  console.log("figurina accanto al compagno:", await js("document.querySelector('.gift-card') !== null"));
  console.log("dati della scheda:", JSON.stringify(card.data().album));
  await sleep(5500);
  console.log("dopo 8 secondi la figurina è sparita:", await js("document.querySelector('.gift-card') === null"));
  svc.run(() => svc.engine.stop());
};
