#!/bin/zsh
# Run the tests. Without Xcode, the Testing framework of the Command Line Tools is not
# found on its own: we give its location. Neither is its macro extension: SwiftPM only
# passes it every other time ("plugin for module 'TestingMacros' not found").
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
# The tests touch neither the installed app's settings, nor its library, nor its support
# folder, nor its command channel. Variables from a trial run in progress
# (PLUME_SAME_VOICE...) stay out of it too.
# unset -m returns 1 when nothing matches: without || true, set -e would stop the script silently.
unset -m 'PLUME_*' || true
TESTS_DIR="$(mktemp -d)"
trap 'rm -rf "$TESTS_DIR"' EXIT
export PLUME_DEFAULTS=tests PLUME_CHANNEL=tests
export PLUME_SUPPORT="$TESTS_DIR/support" PLUME_LIBRARY="$TESTS_DIR/library"
# The tests' settings suite starts from scratch (it may not exist).
defaults delete studio.brigode.plume.tests >/dev/null 2>&1 || true
DEV=/Library/Developer/CommandLineTools/Library/Developer
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
  -Xlinker -F -Xlinker "$DEV/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
  -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
