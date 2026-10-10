# Spidy

Un piccolo personaggio che se ne sta sul desktop del Mac e ogni tanto dice una frase motivazionale.
Non fa altro: è solo una cosa carina sullo schermo. Si sceglie tra **Spidy** (un mini Spider-Man) e
**Bonsy** (un bonsai che cresce mentre fai il Pomofocus).

## Cosa fa

- Compare nell'angolo in basso a destra, sempre sopra le altre finestre e su tutti gli Spaces.
- Ogni 40–110 secondi mostra un fumetto con una frase (la prima dopo 5 secondi dall'avvio).
- Si può trascinare dove si vuole; il fumetto lo segue.
- Non ha icona nel Dock: si controlla dalla barra dei menu o con il tasto destro su Spidy.

## Menu

| Voce | Cosa fa |
|---|---|
| Nascondi / Mostra Spidy | Lo toglie dallo schermo o lo rimette |
| Fai parlare Spidy | Mostra subito una frase |
| Pomofocus ▸ | Timer: *Focus 30/50 min*, *Pausa 5/10 min*, *Ferma timer* |
| Personaggio ▸ | Sceglie tra Spidy e Bonsy (la scelta resta alla riapertura) |
| Avvia al login | Si avvia da solo all'accensione del Mac |
| Modifica le frasi… | Apre il file delle frasi |
| Esci da Spidy | Chiude l'app |

## Pomofocus

Dal menu *Pomofocus* scegli un focus di 30 o 50 minuti: sotto Spidy compare un mini orologio digitale
con il conto alla rovescia. L'orologio resta visibile per i primi 2 minuti di ogni fase, poi si
ritira; ricompare con un'animazione a tendina quando passi il mouse su Spidy, e resta sempre visibile
quando mancano 5 minuti o meno. Alla fine del focus suona un avviso e parte da sola la pausa (5 minuti,
oppure l'ultima durata scelta tra *Pausa 5 min* e *Pausa 10 min*, segnata con la spunta). Alla fine della
pausa l'orologio sparisce. Durante il focus Spidy parla più di rado, per non distrarti.

## Bonsy

Bonsy ha cinque stadi di crescita, dal seme al bonsai adulto. Durante un focus parte dal primo
stadio e passa al successivo ogni quinto del tempo (con un focus da 50 minuti: ai minuti 0, 10, 20,
30 e 40). Durante la pausa e quando non c'è nessun timer resta allo stadio finale. Ha le sue frasi,
in `assets/frasi_bonsy.txt`.

## Installazione

Serve macOS 13 o successivo e gli strumenti da riga di comando di Xcode (`xcode-select --install`).

```bash
./build.sh                         # crea build/Spidy.app
cp -R build/Spidy.app /Applications/
open /Applications/Spidy.app
```

Per l'avvio al login è meglio che l'app stia in **Applicazioni**. macOS potrebbe chiedere
l'approvazione in Impostazioni di Sistema → Generali → Elementi login.

## Frasi

Le frasi di partenza sono in `assets/frasi.txt`, una per riga (le righe che iniziano con `#` sono ignorate).
Per usare le tue senza ricompilare, scegli *Modifica le frasi…* dal menu: crea e apre
`~/Library/Application Support/Spidy/frasi.txt`, che ha la precedenza sul file incluso nell'app.
Le modifiche valgono dalla frase successiva.

## Struttura

```
Sources/Spidy/
  main.swift            avvio dell'app
  AppDelegate.swift     crea finestra, fumetti e menu
  SpidyWindow.swift     finestra trasparente con il personaggio
  Speaker.swift         tempi e comparsa dei fumetti
  SpeechBubble.swift    fumetto: immagine scalata sul testo
  Pet.swift             i personaggi (Spidy, Bonsy): immagini, frasi, misure
  Quotes.swift          caricamento delle frasi
  Pomodoro.swift        logica del timer focus/pausa
  TimerBubble.swift     orologio digitale sotto Spidy
  MenuController.swift  icona nella barra, menu, avvio al login
assets/
  original.png          immagine di partenza
  spidy.png             personaggio ritagliato (generato da tools/cutout.py)
  bubble_original.png   immagine di partenza del fumetto
  bubble.png            fumetto ritagliato (generato da tools/cutout_bubble.py)
  frasi.txt             frasi di Spidy
  frasi_bonsy.txt       frasi di Bonsy
  bonsy/original.png    immagine di partenza di Bonsy (5 stadi)
  bonsy/stage1..5.png   stadi ritagliati (generati da tools/cutout_bonsy.py)
  AppIcon.icns          icona dell'app (generata da tools/make_icon.py)
tools/cutout.py         ritaglia lo sfondo bianco di Spidy (richiede Pillow e numpy)
tools/cutout_bubble.py  ritaglia il fumetto dalla carta
tools/cutout_bonsy.py   ritaglia i 5 stadi del bonsai
tools/make_icon.py      crea l'icona dell'app da assets/spidy.png
build.sh                compila e crea build/Spidy.app
```

## Cambiare il personaggio

Sostituisci `assets/original.png` con un'immagine su sfondo bianco, poi:

```bash
python3 tools/cutout.py && ./build.sh
```
