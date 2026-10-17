# FocusFriends per Windows

La versione per Windows di FocusFriends, scritta con **Electron** (TypeScript, HTML e CSS). È in costruzione: il piano è
in [`../PIANO_WINDOWS.md`](../PIANO_WINDOWS.md) e i formati dei dati, comuni con l'app per Mac, in
[`../FORMATI.md`](../FORMATI.md).

**Stato:** tappa M0 (fondamenta). Non c'è ancora niente da avviare.

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
