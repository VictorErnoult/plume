# Pick the macOS SDK when building without Xcode. Source it from a zsh script.
#
# Why: since the macOS 27 SDK, SwiftUI's `@State` is a macro whose extension
# (SwiftUIMacros) ships only with Xcode. With the Command Line Tools alone, the build
# fails ("plugin for module 'SwiftUIMacros' not found"). So we compile a minimal view;
# if that is the error, we fall back to the newest macOS 26 SDK. Any other error is left
# to `swift build`, which will show it. An already-set SDKROOT is respected.

if [[ -z "${SDKROOT:-}" ]] && [[ "$(print -r -- 'import SwiftUI
struct V: View { @State var a = 0; var body: some View { EmptyView() } }' \
    | swiftc -typecheck - 2>&1)" == *SwiftUIMacros* ]]; then
  sdk=("$(xcode-select -p)"/SDKs/MacOSX26.*.sdk(N/nOn))
  if (( ! $#sdk )); then
    echo "This macOS SDK needs Xcode to build SwiftUI, and no macOS 26 SDK is installed." >&2
    echo "Install Xcode (or select it: sudo xcode-select -s /Applications/Xcode.app)," >&2
    echo "or point SDKROOT at a macOS 26 SDK." >&2
    exit 1
  fi
  export SDKROOT="${sdk[1]}"
  echo "macOS SDK: ${SDKROOT:t} (the default SDK needs Xcode for SwiftUI)"
  unset sdk
fi
