#!/bin/zsh
# Upload a version built by release.sh to the GitHub releases of the repo set in
# scripts/release.env.
#   ./scripts/publish.sh 1.0.1
# The disk image is also uploaded under the fixed name Plume.dmg, so the download link
#   https://github.com/<repo>/releases/latest/download/Plume.dmg
# always points to the latest version.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release.env

VERSION="${1:?version number, for example 1.0.1}"
[[ -n "$PLUME_REPO" ]] || { echo "PLUME_REPO is empty in scripts/release.env."; exit 1; }

DIR="dist/updates"
DMG="$DIR/Plume-$VERSION.dmg"
[[ -f "$DMG" && -f "$DIR/appcast.xml" ]] || { echo "Run ./scripts/release.sh $VERSION first"; exit 1; }
# Without a Developer ID certificate, the version is released unnotarized: macOS blocks it
# on first launch (the read-me on the disk image explains how to get past that).
if [[ -n "$PLUME_IDENTITY" ]]; then
  xcrun stapler validate "$DMG"
else
  echo "No Developer ID certificate: test version, not notarized."
fi

cp "$DMG" "$DIR/Plume.dmg"
NOTES=(--generate-notes)
[[ -f "notes/$VERSION.md" ]] && NOTES=(--notes-file "notes/$VERSION.md")
# The partial updates (.delta) the feed lists for this version: a few MB instead of the
# whole image. Without them, Sparkle falls back to the full image.
DELTAS=()
for name in $(grep -o "v$VERSION/[^\"]*\.delta" "$DIR/appcast.xml" | sed "s|v$VERSION/||" | sort -u); do
  [[ -f "$DIR/$name" ]] && DELTAS+=("$DIR/$name")
done
gh release create "v$VERSION" "$DMG" "$DIR/Plume.dmg" "$DIR/appcast.xml" "${DELTAS[@]}" \
  --repo "$PLUME_REPO" --title "Plume $VERSION" "${NOTES[@]}"
rm "$DIR/Plume.dmg"
echo "Released: https://github.com/$PLUME_REPO/releases/tag/v$VERSION"
