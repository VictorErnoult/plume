#!/bin/zsh
# Fabrique une version publiable de Plume : app signée et notarisée, image disque, flux de
# mises à jour. Rien n'est mis en ligne : c'est le rôle de scripts/publish.sh.
#   ./scripts/release.sh 1.0.1
# Réglages dans scripts/release.env. Sans certificat Developer ID, le script tourne en mode
# essai (signature locale, pas de notarisation) pour vérifier toute la chaîne.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release.env

VERSION="${1:?numéro de version, par exemple 1.0.1}"
# Pas de version avec un test qui échoue : Sparkle la proposerait à toutes les installations.
./scripts/test.sh
# Numéro de construction : la date, toujours croissante — c'est lui que Sparkle compare.
BUILD="${PLUME_BUILD:-$(date +%Y%m%d%H%M)}"
REPO="${PLUME_REPO:-proprietaire/plume}"
# Les trois variables PLUME_BUILD, PLUME_FEED_URL et PLUME_DOWNLOAD_PREFIX ne servent qu'à
# essayer une mise à jour de bout en bout sur ce Mac (voir docs/PUBLIER.md).
FEED="${PLUME_FEED_URL:-https://github.com/$REPO/releases/latest/download/appcast.xml}"
PREFIX="${PLUME_DOWNLOAD_PREFIX:-https://github.com/$REPO/releases/download/v$VERSION/}"

DIST="${PLUME_DIST:-dist}"
APP="$DIST/Plume.app"
# Compilation hors du dossier personnel : aucun chemin de ce Mac dans le binaire publié.
export PLUME_SCRATCH="${PLUME_SCRATCH:-/Users/Shared/plume-build}"
TOOLS="$PLUME_SCRATCH/artifacts/sparkle/Sparkle/bin"
# Sans dépôt où publier, l'app ne cherche pas de mises à jour : c'est une version pour
# testeurs, rangée à part pour ne jamais entrer dans le flux des versions publiées.
UPDATES=1
[[ -z "${PLUME_REPO:-}" && -z "${PLUME_FEED_URL:-}" ]] && UPDATES=0
OUT="$DIST/mises-a-jour"
[[ $UPDATES == 0 ]] && OUT="$DIST/essai"
DMG="$OUT/Plume-$VERSION.dmg"
mkdir -p "$OUT"

./scripts/assemble.sh "$APP"

# Clé publique des mises à jour : créée au premier passage, gardée dans le trousseau.
if [[ -z "$PLUME_ED_PUBLIC_KEY" ]]; then
  if ! PLUME_ED_PUBLIC_KEY="$("$TOOLS/generate_keys" -p 2>/dev/null)"; then
    "$TOOLS/generate_keys" >/dev/null
    PLUME_ED_PUBLIC_KEY="$("$TOOLS/generate_keys" -p)"
  fi
  /usr/bin/sed -i '' "s|^PLUME_ED_PUBLIC_KEY=.*|PLUME_ED_PUBLIC_KEY=\"$PLUME_ED_PUBLIC_KEY\"|" scripts/release.env
  echo "Clé publique des mises à jour notée dans scripts/release.env."
fi

PLIST="$APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }
plist "Set :CFBundleShortVersionString $VERSION"
plist "Set :CFBundleVersion $BUILD"
if [[ $UPDATES == 1 ]]; then
  plist "Add :SUFeedURL string $FEED"
  plist "Add :SUPublicEDKey string $PLUME_ED_PUBLIC_KEY"
  plist "Add :SUEnableAutomaticChecks bool true"
fi
# Flux servi par ce Mac pendant un essai : le système n'autorise le http qu'en local.
if [[ "$FEED" == http://127.0.0.1* ]]; then
  plist "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true"
  plist "Add :SUAutomaticallyUpdate bool true"
fi

# --- Signature
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ENTITLEMENTS="Resources/Plume.entitlements"
if [[ -n "$PLUME_IDENTITY" ]]; then
  ESSAI=0
  SIGN=(codesign --force --timestamp --options runtime --sign "$PLUME_IDENTITY")
else
  ESSAI=1
  echo "Mode essai : signature locale, pas de notarisation."
  ./scripts/signing-identity.sh
  SIGN=(codesign --force --options runtime --sign "Plume Local Signing"
    --keychain "$HOME/Library/Keychains/plume-signing.keychain-db")
  # Un certificat local n'a pas d'identifiant d'équipe : sans cette dérogation, le système
  # refuserait de charger Sparkle sous le « hardened runtime ».
  ENTITLEMENTS="$DIST/essai.entitlements"
  cp Resources/Plume.entitlements "$ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS"
fi
# De l'intérieur vers l'extérieur : les outils de Sparkle, la bibliothèque, puis l'app.
"${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$PLUME_NOTARY_PROFILE" --wait
}

# --- Notarisation de l'app, pour qu'elle s'ouvre même hors ligne
if [[ $ESSAI == 0 ]]; then
  ditto -c -k --keepParent "$APP" "$DIST/Plume.zip"
  notarize "$DIST/Plume.zip"
  xcrun stapler staple "$APP"
  rm "$DIST/Plume.zip"
fi

# --- Image disque : l'app et un raccourci vers Applications
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Plume.app"
ln -s /Applications "$STAGE/Applications"
# Une version non notarisée est bloquée à la première ouverture : on dit comment passer.
if [[ $ESSAI == 1 ]]; then
  cp Resources/Lisez-moi-testeurs.txt "$STAGE/Lisez-moi.txt"
  if [[ $UPDATES == 1 ]]; then
    print "\nLes nouvelles versions arrivent toutes seules : Plume te les propose dès qu'elles sortent." >>"$STAGE/Lisez-moi.txt"
  else
    print "\nCette version ne se met pas à jour toute seule : une nouvelle te sera envoyée." >>"$STAGE/Lisez-moi.txt"
  fi
fi
rm -f "$DMG"
hdiutil create -volname "Plume" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
if [[ $ESSAI == 0 ]]; then
  codesign --force --timestamp --sign "$PLUME_IDENTITY" "$DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
fi

# --- Flux de mises à jour : signé avec la clé du trousseau. Les notes de version, si elles
# existent (notes/1.0.1.md), sont jointes.
if [[ $UPDATES == 1 ]]; then
  [[ -f "notes/$VERSION.md" ]] && cp "notes/$VERSION.md" "$OUT/Plume-$VERSION.md"
  "$TOOLS/generate_appcast" "$OUT" --download-url-prefix "$PREFIX" --embed-release-notes \
    --link "https://github.com/$REPO" -o "$OUT/appcast.xml"
fi

echo
echo "Version $VERSION ($BUILD) prête dans $OUT :"
ls -lh "$OUT" | tail -n +2
[[ $ESSAI == 1 ]] && echo "Non notarisée : macOS la bloque à la première ouverture (voir Lisez-moi.txt dans l'image disque)."
exit 0
