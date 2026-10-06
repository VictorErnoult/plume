#!/bin/zsh
# Create (once) a stable local signing identity for Plume.
#
# Why: macOS ties permissions (Microphone, Accessibility, audio capture) to the app's
# signature. With an "ad hoc" signature, every rebuild would lose them. A self-signed
# certificate, kept in a dedicated keychain, gives the same signature from one build
# to the next.
set -euo pipefail

NAME="Plume Local Signing"
KEYCHAIN="$HOME/Library/Keychains/plume-signing.keychain-db"
PASS="plume-local-signing"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  security unlock-keychain -p "$PASS" "$KEYCHAIN"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout "pass:$PASS" -name "$NAME" >/dev/null 2>&1

[ -f "$KEYCHAIN" ] || security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$PASS" "$KEYCHAIN"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$KEYCHAIN" >/dev/null

# Add the keychain to the user's search list, without removing the others.
EXISTING=("${(@f)$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')}")
if ! printf '%s\n' "${EXISTING[@]}" | grep -qx "$KEYCHAIN"; then
  security list-keychains -d user -s "${EXISTING[@]}" "$KEYCHAIN"
fi
echo "Signing identity created: $NAME"
