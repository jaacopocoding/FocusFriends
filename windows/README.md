# FocusFriends per Windows

La versione per Windows di FocusFriends, scritta con **Electron** (TypeScript, HTML e CSS). È in costruzione: il piano è
in [`../PIANO_WINDOWS.md`](../PIANO_WINDOWS.md) e i formati dei dati, comuni con l'app per Mac, in
[`../FORMATI.md`](../FORMATI.md).

**Stato:** da M1 a M10 finite sul Mac, M11 (parità e prove) fatta per la parte che si prova dal Mac; per il resto vedi [`PARITA.md`](PARITA.md) e [`PROVE_SU_WINDOWS.md`](PROVE_SU_WINDOWS.md). In dettaglio: M2, M3, M4, M5, M6, M7, M8 e M9 finite sul Mac (la logica pura in `src/core/`, il timer, la scheda di carta, il menu completo, i suoni, le schede «Cosa studi adesso?», «Com'è andata?» e di benvenuto, e le statistiche) e M1 avviata: il
compagno si vede, cammina, si solleva, parla, ha l'orologio sotto di sé e il «+5 minuti» a fine focus. Clic sull'icona nell'area di
notifica = la scheda; tasto destro = il menu. Manca la prova su Windows.

**Per provarlo** serve Node 24 o più nuovo:

```bash
cd windows
npm install     # una volta: scarica Electron, TypeScript e esbuild in node_modules/ (circa 250 MB)
npm test        # le prove della logica (nessun pacchetto necessario)
npm run check   # controllo dei tipi
npm start       # compila e apre il compagno (Esci: dall'icona nell'area di notifica)
```

**Per fare l'installer** vedi [`RILASCIO.md`](RILASCIO.md): `npm run pacchetto` (e, per la release, il tag `windows-v…` che fa partire la macchina Windows di GitHub).

Sul Mac `npm start` mostra il compagno sullo schermo e lavora in una **cartella di dati di prova**
(`~/Library/Application Support/focusfriends-windows/dati-di-prova`): **non tocca mai i dati dell'app per Mac**. Con
`FF_DATA_DIR=/un/percorso` si sceglie un'altra cartella. Su Windows i dati stanno in `%APPDATA%\FocusFriends`.

**Modalità sviluppatore** (tutti i compagni sbloccati, senza toccare il profilo): scrivi `"developerMode": true` in `impostazioni.json`
(`%APPDATA%\FocusFriends\` su Windows) e riapri l'app.

Le prove includono il **contratto con la versione per Mac**: da ogni cartella di `../tests/fixtures/` il codice deve ricavare
lo stesso risultato dei file `../tests/fixtures/attesi/`, generati dall'app per Mac (`../tests/genera-attesi.sh`), e **il contrario**
(`test/ritorno.test.ts`, solo su un Mac con `swiftc`): i file scritti da questo codice li legge il codice Swift dell'app per Mac con gli stessi risultati. I dati dei
compagni (`data/pets.json`) si rifanno con `../tools/genera-pets.sh`, e le misure dei rumori (`../tests/fixtures/rumore.json`) con
`../tests/genera-rumore.sh`.

## Com'è organizzata (quando ci sarà)

```
windows/
├── src/
│   ├── core/        la logica pura (registro, statistiche, regole): senza Electron, si prova con Node
│   ├── main/        il processo principale: finestre, area di notifica, file, avvio al login
│   │   └── platform/    quello che tocca Windows
│   ├── preload/     il ponte sicuro tra le due parti
│   └── renderer/    l'interfaccia
├── resources/       risorse solo di Windows (per esempio il suono di fine focus)
└── package.json
```

Le immagini, le frasi e i brani sono quelli di `../assets/`, in comune con l'app per Mac. Le prove di confronto usano
gli esempi di `../tests/fixtures/`.

## Installare (quando ci sarà la release)

1. Scarica dalla pagina delle [Releases](https://github.com/jaacopocoding/FocusFriends/releases) l'installer giusto: `…-x64-Setup.exe` per i computer
   Intel e AMD, `…-arm64-Setup.exe` per quelli ARM (per esempio Surface Pro e i portatili Copilot+).
2. Lancialo: si installa per te, senza permessi di amministratore, e si apre. Il programma non è ancora firmato: la prima volta Windows può mostrare
   «Windows ha protetto il PC» → *Ulteriori informazioni* → *Esegui comunque*.
3. Il compagno compare in basso a destra, l'icona è nell'area di notifica (clic = la scheda, tasto destro = il menu).

I dati stanno in `%APPDATA%\FocusFriends` e restano anche se togli l'app. Per controllare il file scaricato:
`Get-FileHash .\FocusFriends-Windows-<versione>-x64-Setup.exe -Algorithm SHA256` (il valore giusto è nelle note della release).
