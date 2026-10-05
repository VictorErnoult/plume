#!/bin/zsh
# Lance les tests. Sans Xcode, le framework Testing des Command Line Tools n'est pas
# trouvé tout seul : on indique son emplacement. Son extension de macros non plus : SwiftPM
# ne l'indique qu'une fois sur deux (« plugin for module 'TestingMacros' not found »).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
DEV=/Library/Developer/CommandLineTools/Library/Developer
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
  -Xlinker -F -Xlinker "$DEV/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
