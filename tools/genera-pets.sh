#!/bin/bash
# Rifà windows/data/pets.json con i dati dei compagni dell'app per Mac (Sources/FocusFriends/Pet.swift).
# Va rilanciato solo se cambia un personaggio. Non tocca i dati dell'utente.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tools
swiftc -O -o build/tools/genera-pets Sources/FocusFriends/Pet.swift tools/genera-pets/main.swift
build/tools/genera-pets assets windows/data/pets.json
