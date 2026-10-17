# FocusFriends per Windows

La versione per Windows di FocusFriends, scritta con **Electron** (TypeScript, HTML e CSS). È in costruzione: il piano è
in [`../PIANO_WINDOWS.md`](../PIANO_WINDOWS.md) e i formati dei dati, comuni con l'app per Mac, in
[`../FORMATI.md`](../FORMATI.md).

**Stato:** M2 finita (logica pura, `src/core/`) e M1 avviata: il compagno si vede, cammina, si solleva e parla sopra l'area di lavoro.
Manca la prova su Windows.

**Per provarlo** serve Node 24 o più nuovo:

```bash
cd windows
npm install     # una volta: scarica Electron, TypeScript e esbuild in node_modules/ (circa 250 MB)
npm test        # le prove della logica (nessun pacchetto necessario)
npm run check   # controllo dei tipi
npm start       # compila e apre il compagno (Esci: dall'icona nell'area di notifica)
```

Sul Mac `npm start` mostra il compagno sullo schermo e lavora in una **cartella di dati di prova**
(`~/Library/Application Support/focusfriends-windows/dati-di-prova`): **non tocca mai i dati dell'app per Mac**. Con
`FF_DATA_DIR=/un/percorso` si sceglie un'altra cartella. Su Windows i dati stanno in `%APPDATA%\FocusFriends`.

Le prove includono il **contratto con la versione per Mac**: da ogni cartella di `../tests/fixtures/` il codice deve ricavare
lo stesso risultato dei file `../tests/fixtures/attesi/`, generati dall'app per Mac (`../tests/genera-attesi.sh`). I dati dei
compagni (`data/pets.json`) si rifanno con `../tools/genera-pets.sh`.

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
