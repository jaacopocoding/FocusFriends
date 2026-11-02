#!/bin/bash
# Disegna fuori schermo l'album vero dell'app per Mac (AlbumView): la copertina e tre doppie pagine, da una cartella di dati.
# Serve l'app compilata (./build.sh): ne prende i disegni e il carattere dei titoli.
#   tools/render-album.sh <cartella dei dati> <cartella dove scrivere>
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d build/FocusFriends.app ] || { echo "Prima compila l'app: ./build.sh" >&2; exit 1; }
DATA=$1; OUT=$2
B=build/render-album
rm -rf "$B"
mkdir -p "$B/src" "$B/B.app/Contents/MacOS" "$B/B.app/Contents/Resources" "$OUT"
for f in Sources/FocusFriends/*.swift; do
    name=$(basename "$f")
    [ "$name" = "main.swift" ] && continue
    [ "$name" = "AlbumWindow.swift" ] && continue
    cp "$f" "$B/src/"
done
# la doppia pagina mostrata è privata: la rendo visibile solo in questa copia
sed -e 's/^    private var spread = 0/    var spread = 0/' Sources/FocusFriends/AlbumWindow.swift > "$B/src/AlbumWindow.swift"
cp tools/render-album/main.swift "$B/src/zz_render.swift"
cp build/FocusFriends.app/Contents/Resources/* "$B/B.app/Contents/Resources/" 2>/dev/null || true
# un identificativo diverso da quello dell'app: le preferenze del banco non toccano quelle vere
sed -e 's/com\.jacopo\.focusfriends/com.jacopo.focusfriends.banco-album/' build/FocusFriends.app/Contents/Info.plist > "$B/B.app/Contents/Info.plist"
swiftc -O -parse-as-library -o "$B/B.app/Contents/MacOS/FocusFriends" "$B"/src/*.swift
"$B/B.app/Contents/MacOS/FocusFriends" "$DATA" "$OUT"
