#!/bin/bash
# Simula quanto ci vuole a completare l'album del giardino con le regole dei regali (GardenDrops.swift), per tre modi di studiare.
# uso:  tests/simula-regali.sh [numero di oggetti dell'album, default: quelli di adesso]
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/simula
swiftc -O -o build/simula/regali Sources/FocusFriends/SessionLog.swift Sources/FocusFriends/GardenPoints.swift \
    Sources/FocusFriends/GardenCatalog.swift Sources/FocusFriends/GardenGrid.swift Sources/FocusFriends/GardenDrops.swift tests/simula-regali/main.swift
build/simula/regali "$@"
