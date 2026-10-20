// Le pagine non portano fuori dall'app: navigazione verso il web, finestre nuove e permessi vengono rifiutati.
const { BrowserWindow } = require("electron");
module.exports = async ({ js, sleep, win }) => {
  await sleep(1500);
  const before = BrowserWindow.getAllWindows().length;
  const url = () => win.webContents.getURL();
  console.log("indirizzo all'inizio:", url());

  // 1. una finestra nuova (come un collegamento con target="_blank")
  console.log("window.open ->", JSON.stringify(await js("(() => { const w = window.open('https://example.com/'); return w === null ? null : 'aperta'; })()")));
  await sleep(500);
  console.log("finestre prima/dopo:", before, BrowserWindow.getAllWindows().length, "(devono essere uguali)");

  // 2. la pagina prova ad andare altrove
  await js("location.href = 'https://example.com/'");
  await sleep(1500);
  console.log("dopo location.href:", url(), "(deve restare ff://app/…)");
  await js("location.href = 'file:///C:/Windows/win.ini'");
  await sleep(800);
  console.log("dopo file://:", url(), "(deve restare ff://app/…)");

  // 3. i permessi
  const asked = await js(`(async () => {
    const out = {};
    // Ogni richiesta ha tre secondi per rispondere: una che resta appesa non ferma la prova.
    const within = (promise) => Promise.race([promise, new Promise((ok) => setTimeout(() => ok('nessuna risposta'), 3000))]);
    try { out.notifiche = await within(Notification.requestPermission()); } catch (e) { out.notifiche = 'errore ' + e.name; }
    try { const r = await within(navigator.mediaDevices.getUserMedia({ audio: true })); out.microfono = typeof r === 'string' ? r : 'CONCESSO'; } catch (e) { out.microfono = e.name; }
    try { out.posizione = await within(new Promise((ok) => navigator.geolocation.getCurrentPosition(() => ok('CONCESSA'), (e) => ok('rifiutata ' + e.code)))); } catch (e) { out.posizione = 'errore ' + e.name; }
    try { out.appunti = (await within(navigator.permissions.query({ name: 'clipboard-read' }))).state; } catch (e) { out.appunti = 'errore ' + e.name; }
    return JSON.stringify(out);
  })()`);
  console.log("permessi:", asked, "(nessuno deve essere concesso)");

  // 4. la pagina è ancora viva
  const state = JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  console.log("la pagina risponde ancora:", state.pet, state.width, state.height);
};
