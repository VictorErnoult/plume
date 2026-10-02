#!/bin/zsh
# Refait Resources/AppIcon.icns à partir de Resources/Icone.jpg.
set -euo pipefail
cd "$(dirname "$0")/.."
SET="$(mktemp -d)/AppIcon.iconset"
swift scripts/icon.swift "$SET"
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Icône refaite : Resources/AppIcon.icns"
