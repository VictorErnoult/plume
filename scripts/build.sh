#!/bin/zsh
# Compile Plume et assemble build/Plume.app, signée avec l'identité locale.
#   ./scripts/build.sh            compile et assemble
#   ./scripts/build.sh --install  … puis installe dans /Applications et relance l'app
# Pour publier une version destinée à d'autres Mac : ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Plume.app"
./scripts/assemble.sh "$APP"

./scripts/signing-identity.sh
KEYCHAIN="$HOME/Library/Keychains/plume-signing.keychain-db"
codesign --force --deep --sign "Plume Local Signing" --keychain "$KEYCHAIN" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "Plume Local Signing" --keychain "$KEYCHAIN" "$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Plume 2>/dev/null && sleep 0.6 || true
  rm -rf /Applications/Plume.app
  cp -R "$APP" /Applications/Plume.app
  mkdir -p "$HOME/.local/bin"
  ln -sf /Applications/Plume.app/Contents/MacOS/Plume "$HOME/.local/bin/plume"
  open /Applications/Plume.app
  echo "Installée : /Applications/Plume.app (commande : plume)"
else
  echo "Assemblée : $APP"
fi
