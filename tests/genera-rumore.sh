#!/bin/bash
# Rifà tests/fixtures/rumore.json: com'è il rumore (pioggia, marrone, vento) che genera l'app per Mac, per controllare che la
# versione per Windows ne generi uno uguale. Prende il generatore da Sources/FocusFriends/AmbientPlayer.swift (la sola classe
# NoiseSynth, resa visibile) e lo fa girare con le stesse regole: 44100 Hz, volume 1, dissolvenza breve, dieci secondi.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/fixtures
SYNTH=build/fixtures/NoiseSynth.swift
echo "import Foundation" > "$SYNTH"
sed -n '/^private final class NoiseSynth {/,/^\/\/\/ Il suono ambiente del focus/p' Sources/FocusFriends/AmbientPlayer.swift \
    | sed '$d' | sed 's/^private final class NoiseSynth/final class NoiseSynth/' >> "$SYNTH"
swiftc -O -o build/fixtures/genera-rumore "$SYNTH" tests/genera-rumore/main.swift
build/fixtures/genera-rumore tests/fixtures/rumore.json
