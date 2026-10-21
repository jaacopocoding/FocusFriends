# FocusFriends per Windows

La versione per Windows di FocusFriends, scritta con **Electron** (TypeScript, HTML e CSS). La prima uscita (senza il giardino) è **uscita**: il piano è
in [`../PIANO_WINDOWS.md`](../PIANO_WINDOWS.md) e i formati dei dati, comuni con l'app per Mac, in
[`../FORMATI.md`](../FORMATI.md).

**Stato:** l'ultima versione è la **1.1.1** (con «Da fare», senza il giardino), **pubblicata** il 21 ottobre 2026:
[release `windows-v1.1.1`](https://github.com/jaacopocoding/FocusFriends/releases/tag/windows-v1.1.1). Prima, il 21 ottobre, la 1.1.0
([`windows-v1.1.0`](https://github.com/jaacopocoding/FocusFriends/releases/tag/windows-v1.1.0)); la prima uscita, la 1.0.0, è del 18 ottobre
([`windows-v1.0.0`](https://github.com/jaacopocoding/FocusFriends/releases/tag/windows-v1.0.0)). È provata sul Mac con prove automatiche e prove dal vivo, sulla
CI di GitHub (macchina Windows) e, in modo sommario, su un computer Windows vero. Il confronto con l'app per Mac, funzione per funzione, è in [`PARITA.md`](PARITA.md);
quello che resta da provare su Windows, punto per punto, in [`PROVE_SU_WINDOWS.md`](PROVE_SU_WINDOWS.md). Il giardino è la seconda uscita.
La 1.1 aggiunge la pagina **Da fare** della scheda, come sull'app per Mac (con la 1.0.1, che non è uscita da sola).
Clic sull'icona nell'area di notifica = la scheda; tasto destro = il menu.

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
`FF_DATA_DIR=/un/percorso` si sceglie un'altra cartella (solo dai sorgenti: l'app installata la ignora). Su Windows i dati stanno in `%APPDATA%\FocusFriends`.

**Modalità sviluppatore** (tutti i compagni sbloccati, senza toccare il profilo): scrivi `"developerMode": true` in `impostazioni.json`
(`%APPDATA%\FocusFriends\` su Windows) e riapri l'app.

Le prove includono il **contratto con la versione per Mac**: da ogni cartella di `../tests/fixtures/` il codice deve ricavare
lo stesso risultato dei file `../tests/fixtures/attesi/`, generati dall'app per Mac (`../tests/genera-attesi.sh`), e **il contrario**
(`test/ritorno.test.ts`, solo su un Mac con `swiftc`): i file scritti da questo codice li legge il codice Swift dell'app per Mac con gli stessi risultati. I dati dei
compagni (`data/pets.json`) si rifanno con `../tools/genera-pets.sh`, e le misure dei rumori (`../tests/fixtures/rumore.json`) con
`../tests/genera-rumore.sh`.

## Com'è organizzata

```
windows/
├── src/
│   ├── core/        la logica pura (registro, statistiche, regole, timer, suoni): senza Electron, si prova con Node
│   ├── main/        il processo principale: finestre, area di notifica, file, avvio al login, timer
│   ├── preload/     il ponte sicuro tra le due parti
│   ├── renderer/    l'interfaccia (il compagno, le schede, le statistiche, i suoni)
│   └── shared/      il contratto tra processo principale e interfaccia
├── resources/       risorse solo di Windows: il suono di fine focus e il carattere (Chewy, licenza Apache 2.0)
├── data/            i dati dei compagni (generati da Pet.swift)
├── test/            le prove (`npm test`), anche il contratto con l'app per Mac, nei due versi
│   └── vivo/        i copioni per provare dal vivo l'app vera (`esegui.sh`), con il loro README
├── tools/           compilazione, icone, preparazione delle risorse per l'installer
└── package.json
```

Come funziona il codice (processi, finestra trasparente, timer, dati, suoni, prove, scelte fatte e punti deboli) è in [`ARCHITECTURE.md`](ARCHITECTURE.md).

Le immagini, le frasi e i brani sono quelli di `../assets/`, in comune con l'app per Mac. Le prove di confronto usano
gli esempi di `../tests/fixtures/`.

## Installare

1. Scarica dalla pagina delle [Releases](https://github.com/jaacopocoding/FocusFriends/releases) l'installer giusto: `…-x64-Setup.exe` per i computer
   Intel e AMD, `…-arm64-Setup.exe` per quelli ARM (per esempio Surface Pro e i portatili Copilot+).
2. Lancialo: si installa per te, senza permessi di amministratore, e si apre. Il programma non è ancora firmato: la prima volta Windows può mostrare
   «Windows ha protetto il PC» → *Ulteriori informazioni* → *Esegui comunque*.
3. Il compagno compare in basso a destra, l'icona è nell'area di notifica (clic = la scheda, tasto destro = il menu).

I dati stanno in `%APPDATA%\FocusFriends` e restano anche se togli l'app. Per controllare il file scaricato:
`Get-FileHash .\FocusFriends-Windows-<versione>-x64-Setup.exe -Algorithm SHA256` (il valore giusto è nelle note della release).
