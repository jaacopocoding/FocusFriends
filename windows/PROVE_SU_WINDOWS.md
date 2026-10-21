# Prove su Windows

Quello che dal Mac non si può provare (le sigle **W** di `PARITA.md`). Servono una macchina Windows, anche virtuale
(Parallels o UTM con Windows 11 ARM, che esegue anche le app x64), e un'ora per volta. Per ogni punto: cosa fare, cosa deve
succedere, cosa mandarmi. In caso di dubbio basta il file `registro-app.log` e una schermata (**Win + Maiusc + S**).

**Dove sta tutto.** I dati: `%APPDATA%\FocusFriends\` (scrivilo nella barra di Esplora file). Il registro dell'app:
`%APPDATA%\FocusFriends\registro-app.log`: contiene la versione di Windows, le misure e la scala di ogni schermo, il lato
della barra delle applicazioni, sleep e risvegli, errori. Niente nomi né materie: si può mandare così com'è.

**Come si avvia.** Una delle due:

- **L'installer** (dalla [pagina delle release](https://github.com/jaacopocoding/FocusFriends/releases): la più recente il cui nome comincia con `windows-v`): `FocusFriends-Windows-<versione>-x64-Setup.exe`, oppure `…-arm64-Setup.exe` su Windows ARM.
  Non è firmato: Windows dice «Windows ha protetto il PC». Si va avanti con *Ulteriori informazioni* → *Esegui comunque*.
- **Dai sorgenti**: installare Node.js 24, copiare la cartella `windows/`, poi nel terminale `npm ci` e `npm start`.

Tra una prova e l'altra, per ricominciare da zero: chiudere l'app e cancellare `%APPDATA%\FocusFriends\`.

---

## A. Il compagno e i clic (la prova più importante)

| Passo | Deve succedere |
|---|---|
| Aprire l'app | Compare il compagno in basso a destra, **sopra** la barra delle applicazioni, con i piedi sulla sua linea |
| Aprire Blocco note (o il browser) sotto il compagno e cliccare **vicino** al compagno, ma sul vuoto | Il clic arriva a Blocco note, non al compagno |
| Cliccare **sul disegno** del compagno | Parla; con il tasto destro si apre la scheda di fianco a lui |
| Scrivere in Blocco note e, intanto, lasciare che il compagno parli | La tastiera **non** si sposta: continui a scrivere in Blocco note |
| Aprire la scheda, scrivere nel campo «Cosa studi adesso?» | La tastiera va alla scheda; chiudendola (Esc) torna a Blocco note senza dover cliccare |
| Trascinare il compagno in giro | Segue il cursore senza scatti, fumetto e orologio lo seguono |
| Guardare la barra delle applicazioni e premere **Alt + Tab** | Nessun pulsante né finestra di FocusFriends |

Mandami: una schermata con il compagno e una finestra aperta sotto; dimmi quale dei passi sopra non va.

## B. Barra delle applicazioni e scala

Per ognuna: il compagno sta sopra la barra, la scheda si apre dal lato giusto dell'icona e niente esce dallo schermo.

| Cosa cambiare (Impostazioni di Windows) | |
|---|---|
| Barra **in alto** / **a sinistra** / **a destra** (Windows 10: clic destro sulla barra → Impostazioni; Windows 11 permette solo in basso, se ne può provare la nascosta) | Il compagno si adatta; riga nuova nel registro dell'app («schermo cambiato») |
| Barra **nascosta automaticamente** | Il compagno sta in fondo allo schermo, non sotto un bordo invisibile |
| Scala **100 %**, **125 %**, **150 %**, **200 %** (Sistema → Schermo → Scala) | Compagno, fumetto, orologio e schede della stessa misura relativa; il testo non sfocato |

Mandami: il registro dell'app (le righe «schermo …») e una schermata per scala.

## C. Due schermi

Un secondo monitor (anche virtuale) con scala diversa, per esempio il principale al 100 % e il secondo al 150 %.

- Dal menu dell'area di notifica → **Schermo** → l'altro: il compagno riparte da terra sull'altro schermo.
- **Trascinare** il compagno fino al bordo e oltre: la finestra lo segue sull'altro schermo **senza che il trascinamento si interrompa**.
- Scollegare il secondo schermo mentre il compagno è lì: torna sul principale.

## D. Sleep, coperchio, blocco, fuso orario

| Passo | Deve succedere |
|---|---|
| Avviare un **focus da 5 minuti** con la pioggia, mettere il computer in sleep per un minuto, svegliarlo | Il tempo dormito **non** conta (l'orologio non salta avanti), la pioggia riparte da sola, il compagno è al suo posto |
| Chiudere il coperchio e riaprirlo (portatile), oppure *Sospendi* | Come sopra |
| Win + L (blocca) e sbloccare durante un focus | Il focus continua |
| Senza nessun focus, mettere il computer in sleep per **più di un'ora** e svegliarlo (dalla 1.2) | Dopo 5 secondi il compagno dice «Rieccoti!…» (con lo studio di oggi o le cose da fare). Con meno di un'ora, o con «Frasi: Mai», o con il compagno nascosto, non dice niente |
| Cambiare il **fuso orario** (Ora e lingua → Data e ora) mentre l'app è aperta | Le sessioni di prima restano nel loro giorno; una sessione nuova usa l'orologio nuovo (si vede nelle statistiche, «Oggi») |
| Spostare l'ora avanti di un'ora e indietro (ora legale) | Nessuna sessione cambia giorno |

Mandami: il registro dell'app (righe «il computer va in sleep» / «si risveglia») e dimmi se il focus ha contato bene.

## E. App a schermo intero e desktop virtuali (qui decidiamo cosa fare)

| Passo | Cosa guardare |
|---|---|
| Un video in **schermo intero** in un browser (F11 o il pulsante del video) | Il compagno resta sopra al video? È un fastidio? |
| Una presentazione (PowerPoint o LibreOffice) in schermo intero, e un gioco se c'è | Idem; il gioco in schermo intero esclusivo di solito copre tutto |
| **Win + Ctrl + D** (nuovo desktop) e poi **Win + Ctrl + →** | Il compagno resta sull'altro desktop o ti segue? |
| Dal secondo desktop, **clic sull'icona nell'area di notifica** | Si apre la scheda? Windows ti riporta sul primo desktop? |

Se i comportamenti fanno male, le strade già pensate sono:

1. *Schermo intero*: nascondere il compagno quando Windows dice «app a schermo intero» (`SHQueryUserNotificationState`).
   Serve un piccolo componente nativo (un pacchetto con file già compilati, o un eseguibile minuscolo fatto dalla CI);
   da evitare uno script PowerShell lanciato da un'app non firmata.
2. *Desktop virtuali*: la pagina sa quando la finestra non è sul desktop corrente (`visibilitychange`); il processo
   principale la nasconde e la rimostra, e su Windows questo dovrebbe portarla sul desktop attuale (da verificare).

## F. Suoni

- **Fine focus**: la campana (`resources/fine-focus.wav`) si sente, non è troppo forte né sgradevole. *(È ancora da approvare.)*
- **Brani inclusi**: tutti e cinque suonano. Se uno no, dimmi quale.
- **Una cartella con file `.mp3`, `.m4a`, `.wav`, `.flac`, `.aif` e `.caf`**: dimmi quali suonano (gli altri vengono saltati).
- **Pioggia per un'ora** con un focus lungo: niente scatti, processore sotto il 5 %.
- **Scollegare le cuffie** (o cambiare l'uscita audio) durante la pioggia: il suono continua sull'altra uscita.

## G. Finestre di sistema

- Statistiche → **Esporta CSV…**: la finestra di salvataggio compare, il file si apre in Excel con gli accenti giusti.
- Menu → Musica → **Scegli la cartella…**: la finestra di scelta della cartella.
- Statistiche → **Cancella tutto…**: la conferma, con **Annulla** come scelta predefinita.
- Menu → **Modifica le frasi…**: il file si apre nell'editor di testo.
- Il carattere delle schede e delle statistiche: leggibile alle varie scale.

## H. Installare, avviare al login, togliere

1. Installare: nessuna richiesta di amministratore; voce *FocusFriends* nel menu Start; l'app si avvia da sola alla fine.
2. Menu → **Avvia al login** (ora attivo, perché l'app è installata): riavviare Windows → il compagno compare da solo.
3. Aprire l'app due volte: la seconda copia non parte, la prima mostra il compagno.
4. **Disinstallare** (Impostazioni → App): l'app sparisce, `%APPDATA%\FocusFriends\` **resta**.
5. L'icona nell'area di notifica: su Windows 11 è nel menu «^»; trascinarla fuori per fissarla. Il tasto destro sul compagno apre comunque la scheda.

## I. Prestazioni

Con il compagno fermo (frasi «Mai»), poi con un focus e la pioggia: **Gestione attività** (Ctrl + Maiusc + Esc) → *Dettagli*, e
sommare i processi `FocusFriends.exe`. Obiettivo: **memoria sotto i 250 MB, processore sotto il 2 % a riposo** (sotto il 5 %
con la pioggia). Se la memoria è alta, mandami la lista dei processi con le loro misure (le leve sono in `PIANO_WINDOWS.md`, M9).

## J. Una giornata vera e i dati sul Mac

1. Usare l'app per un giorno: focus veri, note, una pausa, un voto, un cambio di compagno.
2. Copiare `sessioni.json` e `profilo.json` **in una cartella di prova sul Mac** (mai in `~/Library/Application Support/FocusFriends`
   dell'app vera): lanciare l'app per Mac su quella cartella oppure `tests/genera-attesi.sh` con una copia della cartella, e
   confrontare numeri e testi delle statistiche con quelli della versione per Windows.
   (Che i file scritti dal codice per Windows siano letti uguali dal Mac è già provato con dati inventati: `test/ritorno.test.ts`.)

---

**Quando tutto questo è passato**, la prima uscita per Windows è pronta: versione 1.0, senza giardino.
