# Spidy

Un mini Spider-Man che se ne sta sul desktop del Mac e ogni tanto dice una frase motivazionale.
Non fa altro: è solo una cosa carina sullo schermo.

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
| Avvia al login | Si avvia da solo all'accensione del Mac |
| Modifica le frasi… | Apre il file delle frasi |
| Esci da Spidy | Chiude l'app |

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
  Quotes.swift          caricamento delle frasi
  MenuController.swift  icona nella barra, menu, avvio al login
assets/
  original.png          immagine di partenza
  spidy.png             personaggio ritagliato (generato da tools/cutout.py)
  bubble_original.png   immagine di partenza del fumetto
  bubble.png            fumetto ritagliato (generato da tools/cutout_bubble.py)
  frasi.txt             frasi incluse nell'app
tools/cutout.py         ritaglia lo sfondo bianco di Spidy (richiede Pillow e numpy)
tools/cutout_bubble.py  ritaglia il fumetto dalla carta
build.sh                compila e crea build/Spidy.app
```

## Cambiare il personaggio

Sostituisci `assets/original.png` con un'immagine su sfondo bianco, poi:

```bash
python3 tools/cutout.py && ./build.sh
```
