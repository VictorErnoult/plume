#!/bin/zsh
# Met en ligne une version fabriquée par release.sh, sur les « releases » GitHub du dépôt
# indiqué dans scripts/release.env.
#   ./scripts/publish.sh 1.0.1
# L'image disque est aussi déposée sous le nom fixe Plume.dmg : le lien de téléchargement
#   https://github.com/<dépôt>/releases/latest/download/Plume.dmg
# pointe ainsi toujours sur la dernière version.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release.env

VERSION="${1:?numéro de version, par exemple 1.0.1}"
[[ -n "$PLUME_REPO" ]] || { echo "PLUME_REPO est vide dans scripts/release.env."; exit 1; }

DIR="dist/mises-a-jour"
DMG="$DIR/Plume-$VERSION.dmg"
[[ -f "$DMG" && -f "$DIR/appcast.xml" ]] || { echo "Lance d'abord ./scripts/release.sh $VERSION"; exit 1; }
# Sans certificat Developer ID, la version est publiée non notarisée : macOS la bloque à la
# première ouverture (le Lisez-moi de l'image disque explique comment passer).
if [[ -n "$PLUME_IDENTITY" ]]; then
  xcrun stapler validate "$DMG"
else
  echo "Pas de certificat Developer ID : version d'essai, non notarisée."
fi

cp "$DMG" "$DIR/Plume.dmg"
NOTES=(--generate-notes)
[[ -f "notes/$VERSION.md" ]] && NOTES=(--notes-file "notes/$VERSION.md")
gh release create "v$VERSION" "$DMG" "$DIR/Plume.dmg" "$DIR/appcast.xml" \
  --repo "$PLUME_REPO" --title "Plume $VERSION" "${NOTES[@]}"
rm "$DIR/Plume.dmg"
echo "Publiée : https://github.com/$PLUME_REPO/releases/tag/v$VERSION"
