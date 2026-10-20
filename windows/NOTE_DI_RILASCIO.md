## FocusFriends per Windows 1.0.1

Il compagno che ti fa compagnia mentre studi, adesso anche su Windows 10 e 11 (Intel/AMD e ARM): un personaggio che cammina sul desktop,
un timer Pomofocus con la sua schermata del focus, i suoni di sottofondo, le statistiche e i compagni da sbloccare studiando.
Stessi dati, stesse regole e stesso aspetto dell'[app per Mac](https://github.com/jaacopocoding/FocusFriends#readme): i file di studio si possono
leggere con l'una e con l'altra.

### Novità della 1.0.1

Nessuna funzione nuova e nessun cambio ai dati: si installa sopra la 1.0.0 e tutto resta com'è. Cambia quello che non si vede, per rendere l'app più solida:

- **Più chiusa in sé**: le finestre dell'app non aprono mai pagine web né finestre nuove, e non ottengono permessi (microfono, fotocamera, posizione, notifiche): l'app non ne usa nessuno.
- **Le opzioni di prova non cambiano più l'app**: quelle usate solo per provarla durante lo sviluppo (per esempio saltare la conferma di «Cancella tutto…») hanno effetto soltanto con l'interruttore delle prove.
- Le prove dal vivo di chi sviluppa l'app sono ora nel repository (`windows/test/vivo/`).

### Come si installa

1. Scarica l'installer giusto: **`FocusFriends-Windows-<versione>-x64-Setup.exe`** per i computer Intel e AMD, **`…-arm64-Setup.exe`** per quelli ARM
   (per esempio Surface Pro e i portatili Copilot+).
2. Lancialo: si installa solo per te (nessun permesso di amministratore) e si apre da solo.
3. **Il programma non è firmato**: la prima volta Windows può mostrare «Windows ha protetto il PC». Scegli *Ulteriori informazioni* → *Esegui comunque*.
4. Il compagno compare in basso a destra. L'icona è nell'area di notifica (su Windows 11, nel menu «^» finché non la trascini fuori):
   clic = la scheda, tasto destro = il menu. Il tasto destro sul compagno apre la scheda accanto a lui.

I dati di studio e le impostazioni stanno in `%APPDATA%\FocusFriends`; **restano anche se togli l'app**. Nessuna rete, nessun invio. Per aggiornare basta
lanciare l'installer nuovo: si installa sopra e i dati restano.

### Come controllare il file scaricato

Il checksum SHA-256 di ogni installer è in `SHA256SUMS.txt`. Da PowerShell:

```powershell
Get-FileHash .\FocusFriends-Windows-<versione>-x64-Setup.exe -Algorithm SHA256
```

### Cosa non c'è (ancora)

- **Il giardino**: arriva con la prossima uscita. Il resto c'è tutto.
- **Sopra le app a schermo intero**: come sul Mac, il compagno resta sopra anche a un video o a una presentazione a schermo intero. Si nasconde dal menu.
- **Desktop virtuali**: Windows non lo lascia comparire su tutti; sta sul desktop in cui l'hai aperto.

### Se qualcosa non va

Apri una [segnalazione](https://github.com/jaacopocoding/FocusFriends/issues) e, se puoi, allega `%APPDATA%\FocusFriends\registro-app.log`: contiene la
versione di Windows, le misure degli schermi e gli errori, e **non** contiene nomi, materie o note.
