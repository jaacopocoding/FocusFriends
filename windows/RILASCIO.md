# Come si rilascia la versione per Windows

## L'installer

`npm run pacchetto` (dentro `windows/`) compila, prepara le risorse (`build/assets`: solo le immagini, le frasi e i brani che l'app usa) e
fa l'installer con electron-builder (`electron-builder.yml`): un file `FocusFriends-Windows-<versione>-<x64|arm64>-Setup.exe` per ogni tipo di
computer, in `windows/release/`. È un installer **per l'utente** (NSIS, una sola finestra, nessun permesso di amministratore): mette l'app in
`%LOCALAPPDATA%\Programs\FocusFriends`, crea la voce nel menu Start e la apre. Toglierla (da *App installate*) **non cancella i dati di studio**,
che stanno in `%APPDATA%\FocusFriends` e sono dell'utente.

Su un Mac si può provare tutto il pacchetto con `npx electron-builder --win nsis --x64 -c.win.signAndEditExecutable=false` (scarica da solo gli
strumenti): senza Wine non si mette l'icona dentro il programma, quindi l'installer vero lo fa la macchina Windows di GitHub (sotto).

## La versione

La versione sta in `windows/package.json` (`version`). Prima della release: alzarla, aggiornare `PIANO_WINDOWS.md` e scrivere le note.

## La release, con GitHub

1. `git tag windows-v0.9.0 && git push origin windows-v0.9.0` (il tag lo metti tu: senza tag non si pubblica niente).
2. Il flusso «Windows» (`.github/workflows/windows.yml`) controlla i tipi, lancia le prove, compila e fa i due installer su una macchina Windows di
   GitHub, calcola lo **SHA-256** di ognuno e crea una **bozza** di release con gli installer e `SHA256SUMS.txt`.
3. Completa le note e pubblica la bozza. Chi scarica può controllare il file da PowerShell:

   ```powershell
   Get-FileHash .\FocusFriends-Windows-0.9.0-x64-Setup.exe -Algorithm SHA256
   ```

## Come si aggiorna chi ha già l'app

A mano, per ora: si scarica il nuovo installer dalla pagina delle release e lo si lancia; si installa sopra la versione vecchia e i dati
restano. Gli aggiornamenti automatici (electron-updater: il file `latest.yml` che electron-builder fa già) si aggiungeranno solo se serviranno.

## La firma del codice (da decidere prima della prima release pubblica)

Senza firma Windows mostra, la prima volta, «Windows ha protetto il PC» (SmartScreen): si va su *Ulteriori informazioni* → *Esegui comunque*.
Le strade, dalla più semplice alla più costosa:

| Strada | Costo | Note |
|---|---|---|
| **Niente firma** e una nota nel README (come sul Mac, che non è notarizzato) | 0 | L'avviso c'è per tutti, e SmartScreen impara con le installazioni. |
| **SignPath Foundation** | 0 per i progetti liberi | Per progetti open source: servono licenza libera (c'è: MIT), repository pubblico e una richiesta. Firma dalla CI. |
| **Trusted Signing di Microsoft** | circa 10 dollari al mese | Firma dalla CI; richiede la verifica dell'identità. |
| **Certificato di firma** (OV o EV) | circa 200–400 dollari l'anno | L'EV toglie subito l'avviso; l'OV lo toglie con il tempo. |

Consiglio: partire senza firma e fare domanda a SignPath Foundation, che non costa nulla.

## Strumenti di compilazione e avvisi di sicurezza

`npm audit` segnala 8 avvisi «moderati» in **strumenti usati solo per compilare** (electron-builder e le sue dipendenze `@electron/get`,
`global-agent`…): non finiscono nell'app. Non si corregge con `npm audit fix --force` (cambierebbe versione maggiore); si aggiorna
electron-builder quando ne esce una che li risolve.
