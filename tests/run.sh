#!/bin/bash
# Compila e lancia le prove del registro e delle statistiche.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
swiftc -O -o build/tests/stats Sources/FocusFriends/SessionLog.swift Sources/FocusFriends/Profile.swift Sources/FocusFriends/CustomTimers.swift Sources/FocusFriends/AmbientSound.swift tests/main.swift
build/tests/stats
