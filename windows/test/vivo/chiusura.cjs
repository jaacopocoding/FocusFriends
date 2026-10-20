// Chiude l'app con un focus in corso (dura circa 70 secondi): dopo, in data/sessioni.json della cartella dei risultati, la sessione deve esserci come interrotta.
module.exports = async ({ sleep, timer, quit }) => {
  await sleep(1500);
  const svc = timer();
  svc.run(() => svc.engine.startFocus(25, "Anatomia"));
  await sleep(65000);
  console.log("chiudo con il focus in corso");
};
