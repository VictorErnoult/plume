#!/bin/zsh
# Lance les tests. Sans Xcode, le framework Testing des Command Line Tools n'est pas
# trouvé tout seul : on indique son emplacement.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV=/Library/Developer/CommandLineTools/Library/Developer
swift test \
  -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
  -Xlinker -F -Xlinker "$DEV/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
