# Read the selection aloud: design

Status: draft for review, 2026-10-07 (revision 2, after an independent review).

## Goal

Select text in any app, press a shortcut, and hear a short spoken summary of it, generated and
spoken entirely on the Mac. Two uses, served by one shortcut:

- **Quick gist**: an email, a thread, a paragraph; know in a few seconds what it says.
- **Long reads, hands-free**: an article or a document; listen to the essentials while doing
  something else.

Speed comes first (time to the first sound), speech quality second.

### Performance target

The feature must be comfortable on a **base M2** (8 or 10 GPU cores, 8 GB), not only on the
M5 it was benchmarked on:

- an email or a short thread (~500 tokens): first sound in **≤ 3 s**;
- a 1,300-word article (~2,200 tokens): first sound in **≤ 10 s**;
- anything longer: progress shown while the text is read, with the remaining time.

### Non-goals (v1)

- No history: summaries are not saved.
- No Apple Intelligence or cloud backend. The design leaves room for both (see "Swapping
  models and services").
- No MCP tool.
- No reading the selection word for word (summary only).

## Decisions and the evidence behind them

Measurements: base Apple M5 (10 GPU cores), 24 GB, macOS 26.6. Throwaway benchmarks on branch
`spike/selection-summary` (`bench/selection-summary/`).

| Topic | Choice | Why |
|---|---|---|
| Summary model | **Chosen by the user** from a small catalog, with one entry marked "Recommended". Candidates: Qwen3.5-4B Q4_K_M (2.74 GB) and Gemma 4 E2B Q4_0 (2.8 GB), both Apache 2.0. Which ones ship, and which is recommended, is decided by the quality eval below. | Qwen3.5-4B met all constraints in 7 of 7 bench cases; Gemma 4 E2B met 6 of 7 (once answered in French when English was asked) and is ~1.7× faster. Gemma 4 E4B was slightly better than both but is 5.2 GB and as slow as Qwen, so it is out. |
| LLM runtime | llama.cpp, official XCFramework, embedded in the app | Builds with SwiftPM and the Command Line Tools (verified: `binaryTarget` → library → executable builds and runs). MLX reads prompts ~30% faster with the same generation speed, but needs Xcode and only runs on Apple hardware. llama.cpp and GGUF also run on Windows, Linux, Android, iOS and the web. |
| Runtime placement | In process, through llama.cpp's C API | Tokens stream straight into the voice; nothing extra to sign or supervise. |
| Voice | Supertonic-3 (FluidAudio 0.17.5, already a dependency), voice F1 by default, M2 as an option | Picked by ear among Supertonic F1/M2, Kokoro and PocketTTS at 1.5×. ~90× real time on the M5, 162 MB for 31 languages, licence OpenRAIL++. |
| Numbers | FluidAudio's `NemoTextNormalizer` (fr, en) before the voice | Supertonic misreads digits ("du 14 au 21" → "du 14 au zoo 21"); written out, it reads them correctly. |
| Playback speed | Pitch-preserving time-stretch at playback (`AVAudioUnitTimePitch`), 0.75× to 2×, default 1.5× | Works for any voice engine and can change during playback. Intelligible at 1.5×. |
| Downloads | Nothing is downloaded until the user picks a model and confirms | Plume stays at its current size for everyone else. |
| New dependency | llama.cpp (MIT) | The owner waived the issue that `AGENTS.md` asks for. |

### Projected speed on typical Macs

Projected from this M5's measurements with the per-chip ratios of llama.cpp's public Apple
Silicon benchmark (discussion #4167, Llama 7B Q4_0). The older chips there were measured on an
older llama.cpp, so these numbers are pessimistic. Time to first sound = reading the selection
+ writing the first sentence (~30 tokens) + 0.05 s of voice.

| Chip | Qwen3.5-4B: email / 1,300 w / 3,500 w | Gemma 4 E2B: email / 1,300 w / 3,500 w |
|---|---|---|
| M1 | 4.8 / 15.5 / 39 s | 2.9 / 9.4 / 24 s |
| **M2** | **3.1 / 10.2 / 26 s** | **1.9 / 6.2 / 15 s** |
| M4 | 2.7 / 8.4 / 21 s | 1.6 / 5.1 / 13 s |
| M4 Pro | 1.3 / 4.2 / 11 s | 0.8 / 2.6 / 6 s |
| M5 (measured basis) | 1.3 / 3.1 / 7 s | 0.8 / 1.9 / 4 s |

Qwen3.5-4B sits right at the M2 target's limit; Gemma 4 E2B meets it with margin. The voice is
not the bottleneck (~90× real time on the M5; even 10× slower would keep up).

### Quality eval (gate before choosing the catalog)

Before the catalog is fixed (PR 1), both candidates summarize the same 30 to 50 real
selections provided by the owner (mail, Slack, articles, documentation; French and English;
short and long), through Plume's own in-process path (`plume read-aloud --text`), not the
bench's `llama-server`. For each selection: does the summary keep the main point, invent
nothing, respect the language and the length? The owner judges; Plume records the timings.

Outcome:

- both acceptable → both ship; the recommendation depends on the Mac (below);
- one clearly worse → only the other ships;
- neither acceptable → the prompt is revised and the eval re-run, or another model is tried
  (one catalog entry).

The selections stay on the owner's Mac and are never committed.

## User experience

### Turning it on

Settings › Local AI gets a new block, "Read a summary of the selection aloud":

- **Off by default. Nothing is downloaded until the user picks a model.** The block lists the
  catalog's models: name, size, licence, a one-line description ("Faster", "More accurate"),
  and a **Recommended** badge on one of them. Each has a **Download** button. The voice
  (162 MB) is part of every download and is said so.
- **The recommendation** is based on this Mac: the more accurate model on a Pro, Max or Ultra
  chip or an M5 or later, with at least 16 GB of memory; the faster one otherwise (base M1 to M4,
  or less than 16 GB). If the eval keeps one model only, it is the recommendation everywhere.
- Download asks for confirmation: "Downloads N GB (summary model and voice). Nothing leaves
  your Mac.", N being the chosen model plus the voice (about 3 GB for both candidates). With less than 16 GB of memory, the confirmation adds: "This Mac has N GB of
  memory: other apps may slow down while a summary is being written."
- Download progress shows in the block and on the island if the user triggers a read meanwhile;
  Cancel and Retry are next to it.
- Once a model is ready, the feature turns on, and the rows below become available: shortcut,
  length, language, voice, speed, show text.
- **Switching model**: downloading another model replaces the current one once it is ready (one
  summary model on disk at a time).
- **Remove**: deletes the summary model and the voice, and turns the feature off.

The shortcut is unassigned by default, like "Transform the selection", and is also listed in
Settings › Shortcuts.

### Using it

1. Select text, press the shortcut. The selection is read at once, while the original app is
   still in front (same as Transform).
2. The island shows:
   - "Loading the model…" when the model is not in memory (1.5 to 3 s; ~4 s more the very first
     time, while Metal compiles its kernels);
   - "Reading the text… 40%" with the remaining time when reading the selection takes more than
     about 2 s (progress comes from the batches llama.cpp processes);
   - "Summarizing…" while the first sentence is written.
3. The first sentence plays as soon as it is written. The island shows "Reading" with a speaker
   icon and the progress ("2/4").
4. Hovering the island shows: pause/resume, replay, − and + for speed (saved as the new speed
   setting), and **Show text**.
5. **Show text** opens the drawer with the summary, the sentence being read highlighted, and a
   Copy button. A setting, "Show the text while reading", opens it by default.
6. Pressing the shortcut again, or Esc, stops at any moment, including while the text is being
   read by the model.
7. When the read ends, the island stays in a "Finished" state for 8 seconds with Replay and Show
   text, then closes. After that, the summary is gone.

### Edge cases

| Situation | Island | Then |
|---|---|---|
| Empty selection, or the app does not expose it | "Select some text first" | Nothing is read. |
| No model downloaded | The shortcut is not registered. | |
| A model is downloading (after the user chose it) | "Downloading the model… x%" | The shortcut is registered from the moment the download starts; the read starts when it is ready, unless stopped. |
| A dictation or meeting is recording | The shortcut is ignored. | |
| A dictation starts while reading | The read stops, the dictation starts. | |
| Selection over the input budget (context minus the output reserve, ~15,000 tokens) | "Summarizing the beginning (about N words)" | The text is cut at the last sentence that fits. |

## Architecture

```
shortcut ─▶ Paster.selectedText() ─▶ SummaryPrompt (messages) ─▶ SummaryService (token stream)
          ─▶ SummaryCleaner ─▶ SentenceSplitter ─▶ NemoTextNormalizer ─▶ Voice
          ─▶ ReadAloudPlayer (AVAudioEngine + AVAudioUnitTimePitch)
```

Everything that can be tested without a model or the UI lives in PlumeKit. The LLM, the voice
and the player sit behind small protocols so the controller can be tested with fakes.

### Swapping models and services

The owner does not want Plume tied to Qwen, or to any one model or runtime. Three layers keep
each choice replaceable.

**1. The prompt is messages, not text.** `SummaryPrompt` produces a model-neutral request:

```swift
struct SummaryRequest: Sendable {
    let system: String
    let user: String
    let maxSentences: Int
    let language: String        // "fr" or "en"
    let truncated: Bool
}
```

**2. Services.** A `SummaryService` turns a request into a stream of events. v1 ships one,
`LlamaSummaryService`. Apple Intelligence (`LocalAI`), a cloud API or MLX would each be one more
type conforming to the protocol, with no change to the prompt, the cleaner, the splitter, the
voice or the controller.

```swift
protocol SummaryService: Sendable {
    var isLoaded: Bool { get async }
    /// Loads the model (already downloaded); the first load may compile GPU kernels.
    func load() async throws
    /// Tokens the service can take as input, and a counter in its own tokens.
    var inputBudget: Int { get async }
    func countTokens(_ text: String) async throws -> Int
    func stream(_ request: SummaryRequest) -> AsyncThrowingStream<SummaryEvent, Error>
    func unload() async
}

enum SummaryEvent: Sendable {
    case readingInput(fraction: Double)   // prompt processing progress
    case text(String)                     // a decoded piece of the summary
}
```

The prompt needs the token counter, so the controller loads the service before building the
request.

**3. One engine catalog.** What the user picks is an **engine entry**; its `kind` says which
service runs it, and a factory builds the service.

```swift
struct SummaryEngineEntry: Sendable, Identifiable {
    let id: String                // "qwen3.5-4b-q4km", stored in settings
    let name: String              // "Qwen3.5 4B"
    let blurb: String             // "More accurate", shown in Settings (localized)
    let tier: Tier                // .accurate or .fast, drives the recommendation
    let licence: License          // name + URL
    let kind: Kind
    enum Kind: Sendable {
        case llama(LlamaModelSpec)
        // later: .appleIntelligence, .cloud(…), .mlx(…)
    }
}

struct LlamaModelSpec: Sendable {
    let download: ModelDownload   // repo, pinned revision, file name, byte size, SHA-256
    let promptFormat: PromptFormat
    let contextTokens: Int        // 16,384
    let sampling: Sampling        // see LlamaSummaryService
}

enum PromptFormat: Sendable {
    /// The template embedded in the GGUF, applied by llama.cpp's built-in formatter.
    /// Only the families llama.cpp recognises (ChatML/Qwen, Gemma 1–3, Mistral, Llama 3, Phi…).
    case embedded(assistantPrefix: String)
    /// An explicit format with {system} and {user} placeholders, for models whose template
    /// llama.cpp does not recognise (Gemma 4: verified unrecognised).
    case explicit(template: String)
}
```

- llama.cpp's C formatter does not run Jinja templates; it matches the template against known
  families. Qwen3.5 is recognised as ChatML; Gemma 4 is not. `promptFormat` keeps adding a
  model a data change either way.
- Qwen3.5 uses `.embedded(assistantPrefix: "<think>\n\n</think>\n\n")`: the empty think block
  turns its reasoning off, exactly as its own template does when `enable_thinking` is false.
- Gemma 4 E2B uses `.explicit(…)` with its turn markers; the exact string is copied from its
  official template during PR 1 and checked by the catalog test.

The selected engine is stored by id (`readAloudEngine`). An id that is no longer in the catalog
resolves to "no model": the feature turns off and Settings offers the current models, so
removing a model from the catalog never breaks a user's settings.

The voice follows the same pattern: `Voice` is a protocol, and `VoiceEntry` (id, engine, voice
name, languages) lists `supertonic3-f1` and `supertonic3-m2` in v1.

### PlumeKit

**`SummaryPrompt`** (pure)

- Input: the selection, the length setting, the language setting, the interface language, the
  service's token counter and input budget.
- Language: "same as the text" uses `NLLanguageRecognizer`; if detection fails or returns a
  language other than French or English, it falls back to the interface language.
- Sentence budget from the selection's word count:

  | Words | Short | Automatic | Detailed |
  |---|---|---|---|
  | < 300 | 1 | 2 | 3 |
  | 300–1,500 | 2 | 4 | 6 |
  | > 1,500 | 3 | 6 | 8 |

- System instructions: the ones validated in the bench, in the target language.
- Truncation: if the selection is over the input budget, it is cut at the last sentence end
  that fits, and `truncated` is set.

**`LlamaSummaryService`** (conforms to `SummaryService`)

- Built from a `SummaryEngineEntry` of kind `.llama`. Loads the GGUF with all layers on the GPU
  (Metal), the entry's context size.
- **Threading.** All llama.cpp calls run on one dedicated serial thread (not Swift's
  cooperative pool), because `llama_decode` blocks for seconds. The service's async methods hop
  onto that thread and back.
- **Prompt.** `.embedded`: reads the GGUF's template with `llama_model_chat_template`; if it is
  NULL, `load` fails with "This model has no chat template" (llama.cpp would otherwise silently
  use ChatML). Renders with `llama_chat_apply_template(add_ass: true)` and appends the prefix; a
  return of −1 fails with "Unsupported chat template". `.explicit`: substitutes the
  placeholders.
- **Tokenization.** The rendered prompt is tokenized with special tokens parsed for the
  template parts only; the selection itself is tokenized with `parse_special = false`, so a
  selection containing a control token (e.g. `<|im_end|>`) stays plain text.
- **Reading the input** in batches of `n_batch` tokens, emitting `readingInput(fraction)` after
  each batch and checking cancellation between batches. `llama_set_abort_callback` reads the
  same cancellation flag, so Esc also interrupts a batch in progress.
- **Sampling** (same as `llama-server`'s defaults, which the bench used): top-k 40, top-p 0.95,
  min-p 0.05, temperature 0.3, then random draw; repetition penalty off.
- **Generation** stops on end-of-generation, a token cap of 60 tokens per budgeted sentence +
  100, or cancellation.
- `llama_backend_init` once per process; llama.cpp's own log goes through `llama_log_set` into
  Plume's log (sizes and timings only).
- `unload()` frees the model and context; it waits for any decode to stop first.

**`SummaryCleaner`** (pure)

- Removes any `<think>…</think>` block, markdown markup (headings, bullets, bold, italics, code
  fences) and leading labels like "Summary:".
- Ends the stream once the sentence budget + 2 is reached.
- An empty result raises "Couldn't summarize this text."

**`SentenceSplitter`** (pure, incremental)

- Fed text pieces, emits complete sentences as soon as they end.
- Does not split on decimals ("4,5", "3.2"), common abbreviations ("M.", "Mme", "Dr", "e.g.",
  "i.e.", "etc."), initials, or ellipses inside a sentence.
- Flushes the remaining text at the end of the stream.

**`Voice` and `SupertonicVoice`**

```swift
protocol Voice: Sendable {
    var sampleRate: Double { get }
    func load() async throws
    func speak(_ sentence: String, language: String) async throws -> [Float]  // mono
    func unload() async
}
```

- `SupertonicVoice` is built from a `VoiceEntry`. It normalizes the sentence
  (`NemoTextNormalizer`, French or English), then synthesizes with `Supertonic3Manager` at
  `speed: 1.0` (Supertonic's own default is 1.05), 44.1 kHz.
- The manager is created with `directory: <support directory>/Models/supertonic-3`, so Plume
  owns the files: "Remove" deletes them, and `PLUME_SUPPORT` isolates trials. (FluidAudio's
  default on macOS is `~/.cache/fluidaudio`, outside Plume's control.)
- Speed is applied by the player, never here.

**`ReadAloudModels`** (downloads)

- One download = the chosen engine's model file + the voice files, with one progress weighted
  by bytes.
- Model file: fetched from `https://huggingface.co/<repo>/resolve/<revision>/<file>` (the
  pinned revision), re-resolved on each attempt because the CDN's redirect URLs are signed and
  expire. Written to `<support directory>/Models/<file>.partial` with HTTP `Range` requests to
  resume; a `200` reply instead of `206` (range ignored) restarts from zero.
- Before starting: free disk space ≥ total size + 10%.
- At the end: size and SHA-256 checked; a mismatch deletes the file and reports a failure with
  Retry. Then the `.partial` is renamed.
- Voice: `Supertonic3ResourceDownloader.ensureModels(directory:…, progressHandler:)` with the
  default vector-estimator variant, and `downloadVoiceStyle` for F1 and M2 (a few kB each).
- The download is owned by the app. A lock file next to the `.partial` (`flock`) prevents a
  second process (the command line) from writing the same file.
- **Lifecycle.** Quitting mid-download keeps the `.partial`; at the next launch, if the user had
  started a download, it resumes automatically and the island shows nothing until a read is
  requested. "Cancel" stops it and deletes the `.partial`. "Remove" cancels any download first.
- Status: `absent`, `downloading(fraction)`, `ready`, `failed(message)`.

**Recommendation** (pure): `recommendedEngine(chip:memoryGB:catalog:)` returns the `.accurate`
entry on (Pro, Max, Ultra, or M5 and later) with ≥ 16 GB, the `.fast` entry otherwise, or the only
entry if there is one. The chip name comes from `machdep.cpu.brand_string`.

### App

**`ReadAloudPlayer`**

- One `AVAudioEngine`: player node → `AVAudioUnitTimePitch` (rate = speed) → main mixer.
- `enqueue(samples)` schedules one sentence; keeps the current summary's buffers for Replay, and
  drops them when the next read starts or the "Finished" state ends.
- `pause()`, `resume()`, `replay()`, `stop()`, `setRate(_:)` (live).
- Reports which sentence is playing and when the queue empties after the stream ended.
- On an audio configuration change (headphones unplugged, Bluetooth), pauses instead of
  continuing on another output.

**`ReadAloudController`** (`@MainActor`)

- Owns a read: selection → load service and voice → prompt → stream → cleaner → splitter →
  voice → player, in one cancellable task. The next sentence is synthesized while the current
  one plays.
- A sentence that fails in the voice is skipped; if every sentence fails, the read fails.
- Publishes `ReadAloudState`: `idle`, `downloading(fraction)`, `loadingModel`,
  `readingInput(fraction, remaining)`, `summarizing`, `reading(index, count, paused)`,
  `finished`, `failed(message)`, plus the summary text.
- Toggle: the shortcut during any active state stops.
- Starting a dictation or a meeting stops the read.
- Its own idle timer unloads the service and the voice after 10 minutes without a read
  (`SessionController.scheduleUnload` belongs to dictation).

**Island**

- Today the island renders only `SessionController.displayPhase`, and `.processing` already
  swaps its label for the speech model's loading state, so it is not reused.
- The island gets a combined state: if the session is not idle, the session wins (a dictation
  always takes the island); otherwise the read-aloud state is shown.
- New renderings: downloading, loading, reading the input (with %), summarizing, reading (icon,
  "2/4", hover controls), finished (Replay, Show text, 8 s), failed; the drawer with the summary
  text and the highlighted sentence.
- Shortcut routing: `onPress`/`onRelease` dispatch on the hotkey action; Esc is enabled while a
  read is active (today: only while dictating), and `onCancelShortcut` stops the read when no
  dictation is running.
- `UIRender` gets demo states for each new rendering (`plume render … --demo`), as `AGENTS.md`
  requires for interface changes.

**Shortcut and triggers**

- New `HotkeyAction.readAloud`, registered when a model is ready or downloading.
- `plume://read-aloud` and the Remote action `read-aloud` trigger a read of the current
  selection (through the app, which has the permissions).

**Command line** (`plume read-aloud`, in-process, no app needed)

- Reads text from stdin, summarizes and speaks it with the current settings.
- `--text`: prints the summary without speaking. `--json`: summary and timings (load, reading
  the input, first sentence, total). `--engine <id>`: uses another downloaded engine (for the
  quality eval).
- `--download <id>`: downloads that engine (with the lock); without it, the command never
  downloads, and fails with a message naming `--download` and Settings.
- No reading of the selection from the command line (it would read the terminal's own
  selection); `plume://read-aloud` does that.

**Doctor**: "Read-aloud: <model> ready / downloading x% / not installed".

## Settings

Through `PlumeSettings` and `SettingsModel`. New fields are optional when read from a backup.

| Key | Type | Default | In backup |
|---|---|---|---|
| `readAloudEngine` | engine id or empty | empty (no model) | **no**: restoring a backup on a new Mac must not start a 3 GB download; the user picks again |
| `readAloudShortcut` | Shortcut | none | yes |
| `readAloudLength` | `short` / `automatic` / `detailed` | `automatic` | yes |
| `readAloudLanguage` | `sameAsText` / `interface` / `fr` / `en` | `sameAsText` | yes |
| `readAloudVoice` | voice id | `supertonic3-f1` | yes |
| `readAloudSpeed` | Double, 0.75…2.0, step 0.25 | 1.5 | yes |
| `readAloudShowText` | Bool | false | yes |

The feature is on when `readAloudEngine` names a downloaded engine. All interface strings go
through `tr("…")` with their French translation in `L10nTable`.

## Privacy

- The selection and the summary are never written to disk.
- Plume's log records sizes, languages and timings for a read, never its text; llama.cpp's log
  is routed through the same filter.
- Nothing is sent anywhere; the only network access is the model download from Hugging Face,
  started by the user.

## Testing

Everything runs with `./scripts/test.sh`, in seconds, with no model, no network and no audio
device:

- `SummaryPrompt`: word counts × length settings → sentence budget; language choice (detected
  French, detected English, undetected, other → interface language); truncation at a sentence
  end with a fake token counter; no model-specific markup in the request.
- `SentenceSplitter`: a table of tricky inputs ("4,5 %", "M. Dupont", "e.g.", "U.S.", "…",
  quotes, a sentence split across pieces) and the plain sentence closest to each, which must
  not change.
- `SummaryCleaner`: think blocks, markdown, labels, over-long output, empty output.
- Engine catalog: unique ids; pinned 40-character revisions; 64-character SHA-256; positive
  sizes; each `.explicit` template contains `{system}` and `{user}`; each `.embedded` entry
  renders a sample request through the same formatting code (with the template string stored
  in the test); an unknown id resolves to "no model".
- Recommendation: a table of chips × memory → expected entry, including a one-entry catalog.
- `ReadAloudModels`: resume with `206`, restart on `200`, checksum mismatch, insufficient disk
  space, cancel, the lock held by another process; with a stub `URLProtocol` and temporary
  folders.
- `ReadAloudController` with a fake `SummaryService`, `Voice` and player: toggle stops, Esc
  stops during input reading, a failing sentence is skipped, all failing → error, dictation
  start stops the read, the state sequence for the island.
- Settings: the new keys in `SettingsBackup` and in `FixtureSamples.backup` (enforced by
  `SavedFormatTests.samplesCoverEveryValue`), `readAloudEngine` excluded from the backup; the
  backup fixture of the unreleased version (1.0.2, no tag) regenerated; French translations
  present; the new shortcut.
- Command line and Remote: `read-aloud` in `CLI.commands` and in `RemoteTests`; without a
  downloaded model it fails with the expected message and starts no download.

Real models are exercised by hand: the quality eval, then a PR checklist (French and English
selections, Esc during input reading, pause, speed, Show text, unplugging headphones,
quitting mid-download and resuming).

## Packaging and release

- `Package.swift`: a `binaryTarget` for `llama.xcframework` from a pinned llama.cpp release URL
  with its checksum, used by PlumeKit. (The zip nests the framework under `build-apple/`; SwiftPM
  accepts it, verified.)
- `scripts/assemble.sh` (called by both `build.sh` and `release.sh`): copy `llama.framework`
  into `Contents/Frameworks` next to Sparkle, thinned to arm64 with `lipo -thin`, and sign it
  the same way. The app already has the `@executable_path/../Frameworks` rpath.
- `Resources/LICENSES.md`: llama.cpp's MIT notice. Model and voice licences (Apache 2.0,
  OpenRAIL++) are linked from the model list in Settings.
- App size: about +12 MB.

## Documentation

- README: the feature in "What it does", the optional download in "Privacy, concretely".
- `docs/GUIDE.md`: a "Read the selection aloud" section.
- `docs/PLAN.md`: rows for the summary engine (llama.cpp, models chosen by the user; MLX
  rejected: Xcode, Apple-only) and the voice (Supertonic-3 + number normalizer).
- `docs/DEVELOPMENT.md`: the new files.
- `CHANGELOG.md`: one line per PR.

## Delivery

1. **PlumeKit pipeline and command line**: prompt, cleaner, splitter, `SummaryService` +
   `LlamaSummaryService`, engine catalog, `Voice` + `SupertonicVoice`, `ReadAloudModels`, a
   minimal player (play and stop), the llama.cpp dependency and packaging, and
   `plume read-aloud` with `--download`, `--engine`, `--text`, `--json`. **The quality eval runs
   on this PR**, and its outcome fixes the catalog before merging.
2. **App**: full `ReadAloudPlayer`, `ReadAloudController`, island states and controls, shortcut,
   URL and Remote action, render demo states.
3. **Settings and docs**: the model list with the recommendation, download, switch and remove,
   doctor, documentation.

## Risks

- **Projections, not measurements, for older Macs.** The M2 target rests on public ratios; the
  first users on older Macs will tell. The `--json` timings make a real measurement one command
  away.
- **llama.cpp C API**: it changes between releases; the version is pinned and updated on
  purpose.
- **Prompt formats**: the in-process formatter is not the bench's Jinja path; the quality eval
  runs on the in-process path to catch differences.
- **English words in French text** (e.g. "bugs") are sometimes misread by the voice.
- **Supertonic-3's OpenRAIL++ licence** carries use restrictions that pass on to users; check the
  wording to show in Settings.
