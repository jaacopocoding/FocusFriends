#!/bin/bash
# Rifà tests/fixtures/attesi/*.json con la versione per Mac (Swift): per ogni cartella di dati di esempio, quello che
# l'app ne ricava con un «adesso» fisso. Va rilanciato solo se cambiano gli esempi o le regole dell'app per Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/fixtures
swiftc -O -o build/fixtures/genera-attesi \
    Sources/FocusFriends/SessionLog.swift Sources/FocusFriends/Profile.swift Sources/FocusFriends/GardenCatalog.swift \
    Sources/FocusFriends/Garden.swift Sources/FocusFriends/GardenPoints.swift Sources/FocusFriends/CompanionRewards.swift \
    Sources/FocusFriends/ToDo.swift Sources/FocusFriends/Remarks.swift Sources/FocusFriends/YearStats.swift Sources/FocusFriends/GardenDrops.swift Sources/FocusFriends/GardenGrid.swift Sources/FocusFriends/GardenCorners.swift \
    tests/genera-attesi/main.swift
build/fixtures/genera-attesi tests/fixtures tests/fixtures/attesi
