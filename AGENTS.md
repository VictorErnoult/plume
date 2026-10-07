# Plume — instructions for AI assistants

This file is for coding agents (Claude Code, Codex, Cursor…). Humans will find the essentials in
the README.

## The project

macOS app (menu bar + an "island" in the notch) for voice dictation and meeting transcription,
fully local. Swift 6 (language mode 5), SwiftPM only: **no Xcode project**, everything builds
with the Command Line Tools. Apple Silicon Mac, macOS 15+.

- `Sources/PlumeKit/`: core with no interface (FluidAudio/CoreML engine, pipeline, library,
  settings). Tested in `Tests/PlumeKitTests`.
- `Sources/Plume/`: the app (SwiftUI/AppKit interface, shortcuts, audio capture, sounds, CLI,
  MCP server, Sparkle updates). Whatever can be isolated from it is tested in `Tests/PlumeTests`.
- File-by-file map: `docs/DEVELOPMENT.md`; technical choices: `docs/PLAN.md`; features:
  `docs/GUIDE.md`; releasing: `docs/RELEASING.md`.

## Commands

```sh
swift build -c release          # build (without Xcode, macOS 27 SDK: see docs/DEVELOPMENT.md)
./scripts/test.sh               # tests (Swift Testing; the script sets the paths without Xcode)
./scripts/build.sh --install    # full app into /Applications, relaunched
.build/release/Plume doctor     # state of permissions, model, screens
.build/release/Plume render <folder> --demo   # interface screenshots, invented data
```

Before saying a change works: build, run the tests, and if the interface changes, look at a
`plume render … --demo` output.

## Conventions

- Code, comments, commit messages, PR descriptions and docs **in English**. UI strings are
  written in English in the code, wrapped in `tr("…")`, with their French translation in
  `PlumeKit/L10nTable.swift`: English is the app's default language, French is chosen in
  Settings. French UI text uses the informal "tu". Comments are `///` and explain why. Match the
  style of the file you are in.
- No new dependency without discussing it in an issue first.
- Settings go through `PlumeSettings` (PlumeKit) and `SettingsModel` (app).
- Sounds: `Sounds.swift` (synthesis) and `SoundPack` (recorded packs, `Resources/Sounds`).
- Trial environment variables (`PLUME_LIBRARY`, `PLUME_DEFAULTS`, `PLUME_SUPPORT`,
  `PLUME_CHANNEL`, `PLUME_HEADLESS`, `PLUME_FAKE_MIC`, `PLUME_FAKE_SYSTEM`, `PLUME_FAKE_CALL`,
  `PLUME_NO_PASTE`, `PLUME_VERBOSE`…): see `docs/DEVELOPMENT.md`, section "Testing without a
  microphone". They let you test everything without touching the installed app, its settings or
  the real library. Always set `PLUME_DEFAULTS` for a trial: without it, the development binary
  writes to the installed app's settings.
- Each PR, or each stack of PRs merged together, adds a line at the top of `CHANGELOG.md`:
  `- Area: effect, in a few words (#number)`, under today's `### <date>` (create it if missing);
  a stack cites its first PR. The effect, not the how. Only a very minor PR (typo, a tweak with
  no effect) adds none: tests, scripts and tooling get their line. The line goes in the top
  version while it is unreleased (no `v<version>` tag); otherwise, in a new `## <next version>`
  section. Release the top version; its heading then takes the release date:
  `## <version> — <date>`.

## Tests

Always `./scripts/test.sh`, never bare `swift test` (CI runs `swift test` with the same
variables): the script keeps settings, library, support folder and command channel apart.
Everything passes in a few seconds, with no model and no microphone; CI does the same on every
push and every PR, and `scripts/release.sh` stops if a test fails. A change in behavior adds or
adapts a test; a bug fix starts with a failing test.

What to test:
- What users and scripts depend on (saved files, command-line and MCP server output, dictation
  text, clipboard), not layout.
- Logic is tested on its own: in PlumeKit, or in a function that receives its dependencies;
  views stay thin. App code is tested in `Tests/PlumeTests` (`@testable import Plume`). When a
  behavior change touches app logic that can be isolated into one function without moving the
  rest, isolate it with its test; otherwise, don't force it.
- Saved files (transcriptions, cancelled recordings, vocabulary, rules, voiceprint, settings
  backup): a file written by a released version must still be read back without losing
  anything. A new field is optional (`T?`), or read with `decodeIfPresent(…) ?? value` in a
  hand-written `init(from:)`, like `AppRule`; a default value on the property is not enough.
  Never touch a sample in `Tests/Fixtures/`: a format change adds the folder for the version
  that releases it (`FIXTURES_VERSION=<version> ./scripts/test.sh --filter FixtureGenerator`);
  the one for a not-yet-released version (no `v<version>` tag) is deleted and regenerated. A
  field or setting removed on purpose goes in `removedOnPurpose` (`SavedFormatTests`), with its
  `CHANGELOG.md` line.
- Command line (`--json`), MCP server tools, `index.jsonl` and `latest.md` (and its deprecated copy
  `dernier.md`): scripts and AIs read them. Adding a key or a tool is fine; renaming or removing
  one breaks them: note it in `CHANGELOG.md` and `docs/GUIDE.md`, and reflect it in the tests
  (`CommandLineTests`, `MCPServerTests`; the binary is only launched through `PlumeBinary.run`).
- Dictation text (clean-up, voice commands, vocabulary, styles): each fix or new command adds
  rows to the `DictationCorpusTests` table, the case handled and the closest ordinary sentence,
  which must not change. A known defect is noted there with `withKnownIssue`, around the one
  expectation that fails.

To keep tests safe and reliable:
- Never the real data. In a test: temporary folders; no `PlumeSettings.shared`, neither
  directly, nor through a `settings:` parameter left at its default, nor through
  `SettingsModel`; no `load`/`save` on `ReplacementStore`, `AppRuleStore` or `VoiceprintStore`
  (their pure functions and `read(from:)`/`write(_:to:)` are allowed); `replacements:` always
  explicit with `Pipeline.format`; no `TranscriptStore.delete` (real Trash).
- Not the general pasteboard (a named pasteboard, released at the end), no keyboard event, no
  `Remote.send`. The binary is only launched with a read command (`path`, `last`, `list`,
  `show`, `search`, `export` without `-o`, `mcp` without its `listen` and `summarize_transcript`
  tools): with no argument or an unknown command, it launches the app.
- Nothing implicit: no time, no time zone, no keyboard layout, no interface language. Pass the
  dates; for text the UI shows, set the language with `L10n.$override.withValue(.english) { … }`
  (or `.french`), never `L10n.current = …` (tests run in parallel).

## Never do

- Commit a recording, a transcription or the contents of `~/Plume`: they are personal data.
  Tests use invented sentences.
- Publish a `plume render` output without `--demo`: it shows the real library.
- Edit `scripts/release.env` (repository, public update key) or the identifier
  `studio.brigode.plume`: already-installed apps would stop receiving updates.
- Run `scripts/release.sh` or `scripts/publish.sh` unless you are asked to: they sign and
  publish a version.
