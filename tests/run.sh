#!/bin/bash
# Compila e lancia le prove del registro e delle statistiche.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
swiftc -O -o build/tests/stats Sources/FocusFriends/SessionLog.swift Sources/FocusFriends/Profile.swift Sources/FocusFriends/CustomTimers.swift Sources/FocusFriends/AmbientSound.swift Sources/FocusFriends/MusicLibrary.swift Sources/FocusFriends/BreakCycle.swift Sources/FocusFriends/CompanionRewards.swift Sources/FocusFriends/GardenCatalog.swift Sources/FocusFriends/Garden.swift Sources/FocusFriends/GardenPoints.swift Sources/FocusFriends/ToDo.swift Sources/FocusFriends/Remarks.swift Sources/FocusFriends/YearStats.swift Sources/FocusFriends/BubblePlacement.swift Sources/FocusFriends/GardenDrops.swift tests/main.swift
build/tests/stats
