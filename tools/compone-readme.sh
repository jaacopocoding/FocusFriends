#!/bin/bash
# Rifà le immagini del README fatte con i disegni dei compagni: docs/images/scrivania.png, compagni.png, frasi.png e crescita.png.
# Prima disegna fuori schermo i fumetti e l'orologio veri dell'app (BubbleView, TimerView), poi li compone con i disegni (tools/compone_readme.py).
set -euo pipefail
cd "$(dirname "$0")/.."
B=build/fumetti
rm -rf "$B"
mkdir -p "$B/B.app/Contents/MacOS" "$B/B.app/Contents/Resources" build/readme
cp assets/bubble.png "$B/B.app/Contents/Resources/"
cat > "$B/B.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>com.jacopo.focusfriends.fumetti</string>
    <key>CFBundleExecutable</key><string>render</string>
    <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
bash tools/banchi/render-scheda.sh
swiftc -O -parse-as-library -o "$B/B.app/Contents/MacOS/render" Sources/FocusFriends/SpeechBubble.swift Sources/FocusFriends/TimerBubble.swift tools/banchi/render-fumetti/main.swift
# 1: sulla scrivania (Gattino); 2-5: nella riga delle frasi (Pianty, Porcellino, Gattino, Riccio)
"$B/B.app/Contents/MacOS/render" build/readme \
    "Stai andando bene. Davvero." \
    "Un passo alla volta: anch'io ho cominciato da un seme." \
    "Un passo alla volta: io arrivo ovunque trotterellando." \
    "Un respiro profondo, le spalle giù, e si riparte." \
    "Quando è troppo, ci si arrotola un attimo. Poi si riparte." \
    --tempi 24:10 24:09 24:08 24:07 24:06 24:05 24:04 24:03 24:02
python3 tools/compone_readme.py
