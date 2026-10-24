#!/bin/zsh
# Build Plume and assemble build/Plume.app, signed with the local identity.
#   ./scripts/build.sh            build and assemble
#   ./scripts/build.sh --install  ... then install into /Applications and relaunch the app
# To release a version for other Macs: ./scripts/release.sh
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
  # The designated requirement (identifier + local certificate) is the same from one build to
  # the next, so the Accessibility grant survives. It doesn't survive a change of certificate
  # (a release build was installed before): the switch then looks on but the new binary is
  # not trusted and its key events are silently dropped. Reset, so Plume asks again.
  if /Applications/Plume.app/Contents/MacOS/Plume doctor 2>/dev/null | grep -q "Accessibility (this process)  enabled"; then
    echo "Accessibility: grant kept."
  else
    tccutil reset Accessibility studio.brigode.plume >/dev/null 2>&1 || true
    echo "Accessibility: not granted to this signature. Re-grant it when Plume asks (System Settings › Privacy › Accessibility › Plume)."
  fi
  open /Applications/Plume.app
  echo "Installed: /Applications/Plume.app (command: plume)"
else
  echo "Assembled: $APP"
fi
