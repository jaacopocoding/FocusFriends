// L'app impacchettata (FF_APP=<…>/app.asar): compagno, carattere, scheda e brani inclusi si caricano dall'asar.
module.exports = async ({ js, sleep, shot, timer }) => {
  await sleep(2500);
  const s = JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  console.log("compagno caricato dall'asar:", s.pet, s.width, s.height);
  console.log("carattere Chewy caricato dall'asar:", await js(`document.fonts.check('20px "Chewy"')`));
  const svc = timer();
  svc.run(() => svc.engine.startFocus(25, "Prova"));
  await sleep(1500);
  await js("window.__ff.openCard()"); await sleep(800);
  console.log("scheda:", await js("document.querySelector('.card-root') !== null"));
  await shot("da-asar");
  console.log("musica inclusa:", await js("window.focusfriends.musicTracks('bundled').then(l => l.tracks.length)"));
};
