#!/bin/zsh
# Rebuild Resources/AppIcon.icns from Resources/Icon.jpg.
set -euo pipefail
cd "$(dirname "$0")/.."
SET="$(mktemp -d)/AppIcon.iconset"
swift scripts/icon.swift "$SET"
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Icon rebuilt: Resources/AppIcon.icns"
