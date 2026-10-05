# Choisit le SDK macOS quand on compile sans Xcode. À sourcer depuis un script zsh.
#
# Pourquoi : depuis le SDK macOS 27, `@State` de SwiftUI est une macro dont l'extension
# (SwiftUIMacros) n'est livrée qu'avec Xcode. Avec les seuls Command Line Tools, la compilation
# échoue (« plugin for module 'SwiftUIMacros' not found »). On compile donc une vue minimale ;
# si l'erreur est celle-là, on se rabat sur le SDK macOS 26 le plus récent. Toute autre erreur
# est laissée à `swift build`, qui l'affichera. Un SDKROOT déjà réglé est respecté.

if [[ -z "${SDKROOT:-}" ]] && [[ "$(print -r -- 'import SwiftUI
struct V: View { @State var a = 0; var body: some View { EmptyView() } }' \
    | swiftc -typecheck - 2>&1)" == *SwiftUIMacros* ]]; then
  sdk=("$(xcode-select -p)"/SDKs/MacOSX26.*.sdk(N/nOn))
  if (( ! $#sdk )); then
    echo "Ce SDK macOS demande Xcode pour compiler SwiftUI, et aucun SDK macOS 26 n'est installé." >&2
    echo "Installe Xcode (ou sélectionne-le : sudo xcode-select -s /Applications/Xcode.app)," >&2
    echo "ou règle SDKROOT vers un SDK macOS 26." >&2
    exit 1
  fi
  export SDKROOT="${sdk[1]}"
  echo "SDK macOS : ${SDKROOT:t} (le SDK par défaut demande Xcode pour SwiftUI)"
  unset sdk
fi
