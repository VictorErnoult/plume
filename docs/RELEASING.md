# Releasing Plume

Plume is distributed outside the Mac App Store: a signed and notarized `.dmg` disk image,
hosted on the releases of a public GitHub repository, with automatic updates (Sparkle). No
Xcode is needed: the Command Line Tools are enough.

## Before the Apple account: trial versions

The repository is `soyAkil/plume` (`PLUME_REPO` in `scripts/release.env`). As long as
`PLUME_IDENTITY` is empty:

```sh
./scripts/release.sh 0.9.1     # → dist/mises-a-jour/Plume-0.9.1.dmg and appcast.xml
./scripts/publish.sh 0.9.1     # publishes to GitHub
```

The app is signed with the local certificate (`Plume Local Signing`, keychain
`plume-signing.keychain-db`), not notarized, but with automatic updates. The `.dmg` contains a
`Read-me.txt` that explains how to get past macOS's block on first open (System Settings ›
Privacy & Security › "Open Anyway").

Sparkle accepts changing *either* the update key *or* the signing certificate from one version
to the next, never both at once: so you can move to the Developer ID certificate later without
losing testers. You do have to keep the update key (see below) and, until the move to
Developer ID, the keychain `~/Library/Keychains/plume-signing.keychain-db`.

Without `PLUME_REPO`, `release.sh` builds a version without updates, put in `dist/trial`.

## Once and for all

1. **Apple Developer account** (€99/year) at developer.apple.com.
2. **"Developer ID Application" certificate**: in Keychain Access, *Certificate Assistant ›
   Request a Certificate From a Certificate Authority* (save the request to disk); on
   developer.apple.com, *Certificates › + › Developer ID Application*, upload the request
   there, download the certificate and open it. `security find-identity -v -p codesigning`
   should then show a line `Developer ID Application: Name (TEAM)`: that is the value of
   `PLUME_IDENTITY` in `scripts/release.env`.
3. **Notarization**: create an app-specific password at account.apple.com, then
   `xcrun notarytool store-credentials plume-notary --apple-id <address> --team-id <TEAM> --password <app-specific password>`.
4. **Public GitHub repository**: `soyAkil/plume`, already set in `PLUME_REPO`. The update feed
   address is baked into every published app: you can't change repository afterwards without
   leaving older versions with no updates.
5. **Update key**: already created (keychain, "Private key for signing Sparkle updates";
   public part in `scripts/release.env`). Back it up:
   `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x plume-key.txt`, store the file in a
   password manager, then delete it from disk. Without it, no update can be published again.

## For each version

```sh
# optional: release notes, shown in the update window
$EDITOR notes/1.0.1.md
./scripts/release.sh 1.0.1   # tests, builds, signs, notarizes, makes the .dmg and the feed
./scripts/publish.sh 1.0.1   # publishes to GitHub
```

`release.sh` publishes nothing. It produces `dist/mises-a-jour/Plume-1.0.1.dmg` and
`appcast.xml` (the feed, signed with the keychain key). Keep the `dist/mises-a-jour` folder from
one version to the next: the feed builds up there. It keeps its French name on purpose: it holds
the feed history on the release Mac, and renaming it loses delta updates.

Permanent download link, for the website:
`https://github.com/<repository>/releases/latest/download/Plume.dmg`

## What has been verified, and what hasn't yet

Verified on this Mac, with the local signature (`PLUME_IDENTITY` empty = trial mode): assembly,
signing under the hardened runtime, the real microphone and a dictation in the app so signed,
building the `.dmg` and the feed, and an end-to-end update (a 0.9.0 app finds 1.0.0, downloads
it, checks its signature, installs it).

Not yet verified, for lack of an Apple account: the Developer ID signature, notarization, and
opening the `.dmg` on another Mac.

### Redoing the update trial

```sh
T=/tmp/update-trial
export PLUME_FEED_URL=http://127.0.0.1:8765/appcast.xml PLUME_DOWNLOAD_PREFIX=http://127.0.0.1:8765/
PLUME_DIST=$T/old PLUME_BUILD=1 ./scripts/release.sh 0.9.0
PLUME_DIST=$T/new PLUME_BUILD=2 ./scripts/release.sh 1.0.0
(cd $T/new/mises-a-jour && python3 -m http.server 8765 --bind 127.0.0.1 &)
PLUME_CHANNEL=trial PLUME_HEADLESS=1 PLUME_UPDATES=1 $T/old/Plume.app/Contents/MacOS/Plume &
# a few seconds later, the trial app is at 1.0.0:
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $T/old/Plume.app/Contents/Info.plist
grep "update" ~/Library/Logs/Plume/plume.log | tail -3
```

## Credits to display

`Resources/LICENSES.md` (opened from Settings › About) lists the models, libraries, fonts and
icons with their license. The models are under CC BY 4.0 or Apache 2.0: attribution is
required, use and distribution are free. Carry these credits over to the download page.
