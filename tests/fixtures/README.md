# Dati di esempio e risultati attesi

Ogni cartella qui dentro è una **cartella dei dati** di esempio (come `~/Library/Application Support/FocusFriends/`):
dentro ci sono i file che l'app legge (`sessioni.json`, `in-corso.json`, `profilo.json`, `giardino.json`…). I formati
sono in [`../../FORMATI.md`](../../FORMATI.md).

| Cartella | Cosa prova |
|---|---|
| `v0-lista`, `v1-con-ora-locale`, `v2-voti` | file di versioni vecchie: si leggono, si copiano intatti in `backup/` e si riscrivono in versione 3 |
| `v3-completo` | una serie con un giorno di ghiaccio e uno che la azzera, materie scritte in modi diversi, voti, note; con profilo e giardino |
| `v3-serie-lunga` | quindici giorni di fila: il moltiplicatore arriva a ×2 |
| `v3-una-rovinata` | una sessione non si legge: si tengono le altre e il file com'era va in `sessioni.corrotto-…` |
| `v3-piu-nuovo` | versione 99: si legge, **sola lettura**, non si riscrive |
| `v3-illeggibile` | non è JSON: si mette da parte e si riparte da vuoto |
| `in-corso-attivo`, `in-corso-fermo`, `in-corso-sotto-un-minuto` | recupero dopo una chiusura improvvisa (anche con il timer fermo, e sotto il minuto) |
| `profilo-vecchio`, `profilo-solo-nome`, `profilo-rovinato` | profilo senza elenco dei sbloccati (li hanno tutti), nome lungo da accorciare, file rovinato |
| `giardino-rovinato`, `giardino-piu-nuovo` | giardino rovinato (si mette da parte) e di una versione più nuova |
| `dafare` | le cose da fare: tutti i gruppi ed etichette (anche l'anno dopo), materia da pulire, una data che non esiste, testo vuoto, caratteri di controllo, emoji, testo troppo lungo, voci fatte (una da più di 7 giorni: sparisce), un id in minuscolo, un campo sconosciuto, una data con il fuso «+02:00» |
| `dafare-rovinato`, `dafare-nuovo`, `dafare-campo-sbagliato` | cose da fare: file non JSON (si mette da parte), versione 2 (sola lettura; promemoria con il testo accorciato), una scadenza scritta come numero (tutto il file è rovinato, come in Swift) |
| `impostazioni-esempio`, `impostazioni-sbagliate` | solo per Windows: preferenze valide e preferenze con valori sbagliati (valgono i predefiniti), più un file di frasi |

## `attesi/`

Per ogni cartella (tranne `impostazioni-*`) un file con **quello che la versione per Mac ne ricava** con un «adesso»
fisso (14 ottobre 2026, ore 20:00, Europe/Rome): quante sessioni, quali file nascono, quali avvisi, le statistiche, la serie, i
punti, i compagni. Un'altra versione dell'app deve dare gli stessi risultati. I numeri di tempo dei nomi dei file messi
da parte sono scritti `<epoch>`.

Per rifarli (solo se cambiano gli esempi o le regole del Mac): `./tests/genera-attesi.sh`. L'esito è sempre lo stesso
a parità di codice.
