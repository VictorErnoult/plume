#!/bin/zsh
# Lance les tests. Sans Xcode, le framework Testing des Command Line Tools n'est pas
# trouvé tout seul : on indique son emplacement. Son extension de macros non plus : SwiftPM
# ne l'indique qu'une fois sur deux (« plugin for module 'TestingMacros' not found »).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
# Les tests ne touchent ni aux réglages de l'app installée, ni à sa bibliothèque, ni à son
# dossier de support, ni à son canal de commande. Les variables d'un essai en cours
# (PLUME_SAME_VOICE…) ne s'en mêlent pas non plus.
# unset -m renvoie 1 quand rien ne correspond : sans || true, set -e arrêterait le script sans un mot.
unset -m 'PLUME_*' || true
TESTS_DIR="$(mktemp -d)"
trap 'rm -rf "$TESTS_DIR"' EXIT
export PLUME_DEFAULTS=tests PLUME_CHANNEL=tests
export PLUME_SUPPORT="$TESTS_DIR/support" PLUME_LIBRARY="$TESTS_DIR/library"
# Le jeu de réglages des tests repart de zéro (il peut ne pas exister).
defaults delete studio.brigode.plume.tests >/dev/null 2>&1 || true
DEV=/Library/Developer/CommandLineTools/Library/Developer
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
  -Xlinker -F -Xlinker "$DEV/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
