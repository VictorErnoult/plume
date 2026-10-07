# Read the selection aloud: design

Status: draft for review, 2026-10-07.

## Goal

Select text in any app, press a shortcut, and hear a short spoken summary of it, generated and
spoken entirely on the Mac. Two uses, served by one shortcut:

- **Quick gist**: an email, a thread, a paragraph; know in ten seconds what it says.
- **Long reads, hands-free**: an article or a document; listen to the essentials while doing
  something else.

Speed comes first (time to the first sound), speech quality second.

### Non-goals (v1)

- No history: summaries are not saved, not even the last one after the next read starts.
- No Apple Intelligence or cloud backend. Both can come later behind the same interface.
- No MCP tool. The `plume read-aloud` command covers scripts and testing.
- No reading the selection word for word (summary only).

## Decisions and the evidence behind them

All measurements: Apple M5, 24 GB, macOS 26.6. Throwaway benchmarks on branch
`spike/selection-summary` (`bench/selection-summary/`).

| Topic | Choice | Why |
|---|---|---|
| Summary model | Qwen3.5-4B, GGUF Q4_K_M (`unsloth/Qwen3.5-4B-GGUF`, 2.74 GB, Apache 2.0) as the first catalog entry, not a fixed dependency | Met all constraints (sentence count, language, no markdown) in 7 of 7 French and English cases. Qwen3.5-2B made factual errors and ignored the requested language; Gemma 4 E4B was slightly better but is 5.2 GB. Models change fast, so the code depends on no particular model: see "Swapping models and services". |
| LLM runtime | llama.cpp, official XCFramework, embedded in the app | Builds with SwiftPM and the Command Line Tools. MLX reads prompts ~30% faster (1,160–1,370 vs 830–1,020 tokens/s) with the same generation speed (~36 tokens/s), but needs Xcode and only runs on Apple hardware. llama.cpp and GGUF also run on Windows, Linux, Android, iOS and the web, which keeps a future port open. |
| Runtime placement | In process, through llama.cpp's C API (not a `llama-server` helper) | Tokens stream straight into the voice, nothing extra to sign or supervise, matches "no runtime to install". |
| Voice | Supertonic-3 (FluidAudio 0.17.5, already a dependency), voice F1 by default, M2 as an option | Picked by ear among Supertonic F1/M2, Kokoro and PocketTTS at 1.5×. Synthesis runs at ~90× real time, the model is 162 MB for 31 languages. Licence OpenRAIL++ (downloaded, not bundled). |
| Numbers | FluidAudio's `NemoTextNormalizer` (fr, en) before the voice | Supertonic misreads digits ("du 14 au 21" → "du 14 au zoo 21"); written out, it reads them correctly. |
| Playback speed | Pitch-preserving time-stretch at playback (`AVAudioUnitTimePitch`), 0.75× to 2×, default 1.5× | Works for any engine and can change during playback. Measured intelligible at 1.5×. |
| Download | Optional: models are fetched only when the user turns the feature on (~2.9 GB) | Plume stays at its current size for everyone else. |
| New dependency | llama.cpp (MIT) | The owner waived the issue that `AGENTS.md` asks for. |

Measured latency of the summary on the M5 (time to first token, which is reading the prompt):
0.5 s for an email (~460 tokens), 2.2 s for 1,300 words, 6 s for 3,500 words. The first
sentence (~30 tokens) adds ~0.9 s, the voice ~0.05 s. Older Macs (M1, M2) will be noticeably
slower; this has not been measured.

## User experience

### Turning it on

Settings › Local AI gets a new block, "Read a summary of the selection aloud":

- A switch, off by default. Turning it on asks for confirmation: "Downloads 2.9 GB of models
  (summary and voice). Nothing leaves your Mac." On a Mac with less than 16 GB of memory, the
  confirmation adds: "This Mac has N GB of memory: summaries may be slow and other apps may
  slow down."
- Download progress shows in this block and on the Home model card, with Retry on failure.
- Rows below the switch (shortcut, length, language, voice, speed) are disabled until the
  models are ready.
- "Remove the models" deletes the files and turns the feature off.

The shortcut is unassigned by default, like "Transform the selection", and is also listed in
Settings › Shortcuts.

### Using it

1. Select text, press the shortcut. The selection is read at once, while the original app is
   still in front (same as Transform).
2. The island shows "Summarizing…" with a spinner, or "Loading the model…" if the model is not
   in memory yet (1.5 to 3 s).
3. As soon as the first sentence is written, it plays. The island shows "Reading" with a
   speaker icon and the progress ("2/4").
4. Hovering the island shows: pause/resume, replay, − and + for speed (remembered as the new
   speed setting), and **Show text**.
5. **Show text** opens the drawer with the summary, the sentence being read highlighted, and a
   Copy button. A setting, "Show the text while reading", opens it by default.
6. Pressing the shortcut again, or Esc, stops at any moment, including during "Summarizing…".
7. When the read ends, the island returns to idle after a few seconds. Until the next read
   starts, hovering the island offers Replay.

### Edge cases

| Situation | Island | Then |
|---|---|---|
| Empty selection, or the app does not expose it | "Select some text first" | Nothing is read. |
| Feature on, models still downloading | "Downloading the models… x%" | The read starts when they are ready, unless the user stops it. |
| Feature off | The shortcut is not registered. | |
| A dictation or meeting is recording | The shortcut is ignored. | |
| Selection over the input budget (~15,000 tokens, ~11,000 words) | "Summarizing the beginning (about 11,000 words)" | The text is cut at the last sentence that fits. |
| A dictation shortcut is pressed while reading | The read stops, the dictation starts. | |

The input budget is set by speed, not by memory: ~15,000 tokens take ~16 s to read on the M5
before the first sound. The model's context is set to 16,384 tokens (prompt + up to ~1,000
tokens of output).

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
each choice replaceable:

1. **Prompt as messages, not text.** `SummaryPrompt` produces a model-neutral request:
   `SummaryRequest { system: String, user: String, maxSentences: Int, language: String }`.
   Nothing upstream of a service knows any model's chat format.
2. **Services.** A `SummaryService` turns a request into a stream of text. v1 ships one,
   `LlamaSummaryService` (llama.cpp, any GGUF). Apple Intelligence (`LocalAI`), a cloud API or
   MLX would each be one more type conforming to the same protocol, with no change to the
   prompt, the cleaner, the splitter, the voice or the controller.

   ```swift
   protocol SummaryService: Sendable {
       var id: String { get }
       func prepare(progress: @escaping @Sendable (Double) -> Void) async throws  // download + load
       func stream(_ request: SummaryRequest) -> AsyncThrowingStream<String, Error>
       func unload() async
   }
   ```
3. **Model catalog.** For llama.cpp, a model is data, not code: a `SummaryModelEntry` in
   `SummaryModelCatalog`.

   ```swift
   struct SummaryModelEntry: Sendable, Identifiable {
       let id: String                 // "qwen3.5-4b-q4km", stored in settings
       let name: String               // "Qwen3.5 4B"
       let download: ModelDownload    // repo, pinned revision, file, byte size, SHA-256
       let licence: String            // "Apache 2.0", shown with a link in Settings
       let contextTokens: Int         // 16,384
       let assistantPrefix: String    // text appended after the chat template's assistant
                                      // header; Qwen3.5: "<think>\n\n</think>\n\n" (reasoning off)
       let temperature: Float         // 0.3
   }
   ```

   The chat format comes from the template embedded in the GGUF file, applied by llama.cpp's
   `llama_chat_apply_template` (it recognizes the common families: ChatML/Qwen, Gemma,
   Mistral, Llama 3, Phi…). `assistantPrefix` covers the one per-model quirk seen so far
   (turning reasoning off). Adding a model is one catalog entry plus its row in the catalog
   test; replacing Qwen is changing the default entry.

The selected model is stored in settings by id (`readAloudModel`). An id that is no longer in
the catalog falls back to the default entry, so removing a model never breaks a user's
settings. The model picker in Settings appears only when the catalog has more than one entry.

The voice follows the same pattern: `Voice` is a protocol, and a `VoiceEntry` (engine +
voice id + languages) lists Supertonic-3 F1 and M2 in v1. Kokoro, PocketTTS or an ONNX runtime
for another platform would be new entries or a new `Voice` type.

### PlumeKit

**`SummaryPrompt`** (pure)

- Input: the selection, the length setting, the language setting, the interface language.
- Language: "same as the text" uses `NLLanguageRecognizer`; if detection fails or returns a
  language other than French or English, it falls back to the interface language.
- Sentence budget from the selection's word count:

  | Words | Short | Automatic | Detailed |
  |---|---|---|---|
  | < 300 | 1 | 2 | 3 |
  | 300–1,500 | 2 | 4 | 6 |
  | > 1,500 | 3 | 6 | 8 |

- Output: a `SummaryRequest` (system instructions validated in the bench, in the target
  language; the user content truncated at the last sentence that fits the input budget; the
  sentence budget; the language), plus a `truncated` flag. No model-specific format.
- The input budget is in tokens of the selected service; `SummaryPrompt` receives a token
  counter from the service (llama.cpp's tokenizer), so the cut is exact for any model.

**`LlamaSummaryService`** (actor, wraps the llama.cpp C API; conforms to `SummaryService`)

- Built from a `SummaryModelEntry`. `prepare` downloads the entry's file (through
  `ReadAloudModels`) and loads it with all layers on the GPU (Metal), with the entry's context
  size and temperature.
- Renders the request with the GGUF's embedded chat template (`llama_chat_apply_template`),
  then appends the entry's `assistantPrefix`. If the template is missing or not recognized,
  `prepare` fails with a clear error, rather than guessing a format.
- Streams decoded text pieces; stops on end-of-generation, a token cap derived from the
  sentence budget, or task cancellation.
- Unloaded after 10 idle minutes, like the speech model (`scheduleUnload`).
- Calls llama.cpp's backend initialisation once per process.

**`SummaryCleaner`** (pure)

- Removes any `<think>…</think>` block, markdown markup (headings, bullets, bold, italics,
  code fences) and leading phrases like "Summary:".
- Stops the stream once the sentence budget + 2 is reached.
- An empty result raises "Couldn't summarize this text."

**`SentenceSplitter`** (pure, incremental)

- Fed text pieces, emits complete sentences as soon as they end.
- Does not split on decimals ("4,5", "3.2"), common abbreviations ("M.", "Mme", "Dr", "e.g.",
  "i.e.", "etc."), initials, or ellipses inside a sentence.
- Flushes the remaining text at the end of the stream.

**`Voice` and `SupertonicVoice`** (wraps FluidAudio)

```swift
protocol Voice: Sendable {
    var sampleRate: Double { get }
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws
    func speak(_ sentence: String, language: String) async throws -> [Float]  // mono
}
```

- `SupertonicVoice` is the v1 implementation, built from a `VoiceEntry` (F1 or M2).
- Normalizes the sentence (`NemoTextNormalizer`, French or English), then synthesizes with
  `Supertonic3Manager` and the chosen style (F1 or M2), at its native rate (speed 1.0).
- Speed is applied by the player, not here, so changing it never re-synthesizes.

**`ReadAloudModels`**

- Summary model: downloads the selected catalog entry's file from its pinned Hugging Face
  revision into `<support directory>/Models/`. The generic downloader knows nothing about the
  model. For the default entry: `unsloth/Qwen3.5-4B-GGUF` at
  `e87f176479d0855a907a41277aca2f8ee7a09523`, `Qwen3.5-4B-Q4_K_M.gguf`, 2,740,937,888 bytes,
  SHA-256 `00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4`.
  - `URLSession` download to a `.partial` file, resumed with an HTTP range request after an
    interruption.
  - Checks free disk space first (size + 10%).
  - Verifies size and SHA-256 at the end; a mismatch deletes the file and reports a failure
    with Retry.
- Voice: `Supertonic3Manager` downloads and compiles its own models (162 MB, FluidAudio cache).
- Reports one combined status: `downloading(fraction)`, `ready`, `failed(message)`, `absent`.
- Switching to another catalog entry downloads its file; the previous one is deleted once the
  new one is ready, so only one summary model is kept on disk.
- `remove()` deletes the GGUF. The Supertonic files stay in FluidAudio's shared cache (162 MB),
  which Plume does not own.

### App

**`ReadAloudPlayer`**

- One `AVAudioEngine`: player node → `AVAudioUnitTimePitch` (rate = speed) → main mixer.
- `enqueue(samples)` schedules one sentence buffer; keeps all buffers of the current summary
  for Replay, and drops them when the next read starts.
- `pause()`, `resume()`, `replay()`, `stop()`, `setRate(_:)` (live).
- Reports which sentence is playing (for "2/4" and the highlight) and when the queue empties
  after the stream ended.
- On an audio configuration change (headphones unplugged, Bluetooth), pauses instead of
  continuing on another output.

**`ReadAloudController`** (`@MainActor`)

- Owns the read: selection → prompt → stream → cleaner → splitter → voice → player, with one
  cancellable task.
- Synthesis of the next sentence runs while the current one plays.
- A sentence that fails in the voice is skipped; if every sentence fails, the read fails.
- Publishes the state the island renders: `idle`, `loadingModel`, `summarizing`,
  `reading(index, count, paused)`, `finished`, `failed(message)`, plus the summary text.
- Toggle: the shortcut during `loadingModel`, `summarizing` or `reading` stops.
- Starting a dictation or a meeting stops the read.

**Island**

- New phases or a read-aloud overlay on the existing ones (`processing` is reused for
  "Summarizing…" and "Loading the model…").
- A "Reading" state with a speaker icon and progress, hover controls (pause/resume, replay,
  −/+, Show text), and the drawer showing the summary text.
- Esc is enabled while a read is in progress (today it is enabled only while dictating).

**Shortcut and triggers**

- New `HotkeyAction.readAloud`, registered only when the feature is on and the models are
  ready.
- `plume://read-aloud` (reads the current selection) and the Remote action `read-aloud`.

**Command line**

`plume read-aloud` reads text from stdin (or the current selection when stdin is a terminal),
then summarizes and speaks it with the current settings; `--text` prints the summary without
speaking; `--json` prints the summary and timings. It needs the models; without them it exits
with an error saying how to turn the feature on.

**Doctor**

`plume doctor` adds "Read-aloud models: ready / missing / downloading".

## Settings

Through `PlumeSettings` and `SettingsModel`, all included in the settings backup. Every new
field is optional when read from a backup, so older backups still load.

| Key | Type | Default |
|---|---|---|
| `readAloudEnabled` | Bool | false |
| `readAloudShortcut` | Shortcut | none |
| `readAloudModel` | catalog id; unknown ids fall back to the default | `qwen3.5-4b-q4km` |
| `readAloudLength` | `short` / `automatic` / `detailed` | `automatic` |
| `readAloudLanguage` | `sameAsText` / `interface` / `fr` / `en` | `sameAsText` |
| `readAloudVoice` | `F1` / `M2` | `F1` |
| `readAloudSpeed` | Double, 0.75…2.0, step 0.25 | 1.5 |
| `readAloudShowText` | Bool | false |

All interface strings go through `tr("…")` with their French translation in `L10nTable`.

## Privacy

- The selection and the summary are never written to disk.
- Plume's log records sizes, languages and timings for a read, never its text.
- Nothing is sent anywhere; the only network access is the model download from Hugging Face.

## Testing

Everything runs with `./scripts/test.sh`, in seconds, with no model, no network and no audio
device:

- `SummaryPrompt`: a table of word counts × length settings → sentence budget; language choice
  (detected French, detected English, undetected, other language → interface language);
  truncation at a sentence boundary with a fake token counter; the request carries no
  model-specific markup.
- `SummaryModelCatalog`: every entry has a pinned 40-character revision, a 64-character SHA-256,
  a positive size and a unique id; an unknown id resolves to the default entry.
- Swappability: the controller runs end to end with a second fake `SummaryService` and a fake
  `Voice`, proving nothing depends on llama.cpp or Supertonic.
- `SentenceSplitter`: a table of tricky inputs ("4,5 %", "M. Dupont", "e.g.", "U.S.", "…",
  quotes, a sentence split across pieces) and the plain sentence closest to each, which must
  not change.
- `SummaryCleaner`: think blocks, markdown, preambles, over-long output, empty output.
- `ReadAloudModels`: resume after an interrupted download, checksum mismatch, insufficient disk
  space, using a stub `URLProtocol` and temporary folders.
- `ReadAloudController` with a fake `SummaryService`, `Voice` and player: toggle stops, Esc stops,
  a failing sentence is skipped, all failing → error, dictation start stops the read, state
  sequence for the island.
- Settings: backup round trip with the new keys, a backup without them still loads, French
  translations present, the new shortcut.
- Command line: `read-aloud` is in the known commands; without models it fails with the
  expected message.

Real models are exercised by hand: `plume read-aloud < text.txt`, plus a short checklist in the
PR (French and English selections, Esc, pause, speed, Show text, unplugging headphones).

## Packaging and release

- `Package.swift`: a `binaryTarget` for `llama.xcframework` from a pinned llama.cpp release
  URL with its checksum, used by PlumeKit.
- `scripts/build.sh`: strip the framework to arm64 (`lipo -thin`), copy it into
  `Contents/Frameworks` next to Sparkle, sign it the same way. The app already has the
  `@executable_path/../Frameworks` rpath.
- `scripts/release.sh` signs it with the release identity.
- About/credits: llama.cpp MIT notice; model licences (Qwen3.5 Apache 2.0, Supertonic-3
  OpenRAIL++) linked from the settings block.
- App size: about +12 MB.

## Documentation

- README: the feature in "What it does" and the optional download in "Privacy, concretely".
- `docs/GUIDE.md`: a "Read the selection aloud" section.
- `docs/PLAN.md`: rows "Summary for reading aloud: Qwen3.5-4B via llama.cpp (MLX rejected:
  Xcode, Apple-only)" and "Voice: Supertonic-3 + number normalizer".
- `docs/DEVELOPMENT.md`: the new files.
- `CHANGELOG.md`: one line per PR.

## Delivery

Three PRs, each releasable on its own:

1. **PlumeKit pipeline**: `SummaryPrompt`, `SentenceSplitter`, `SummaryCleaner`,
   `SummaryService` + `LlamaSummaryService`, `SummaryModelCatalog`, `Voice` +
   `SupertonicVoice`, `ReadAloudModels`, the llama.cpp dependency and packaging, and
   `plume read-aloud` (download triggered from the command line until the settings UI exists).
   Tests the pipeline end to end from the terminal.
2. **App**: `ReadAloudPlayer`, `ReadAloudController`, island states and controls, shortcut,
   URL and Remote action.
3. **Settings and docs**: the settings block, Home card, doctor, documentation.

## Risks

- **Older Macs**: speeds are measured on an M5 only. Measure on a base M1 or M2 before
  deciding whether to warn or restrict.
- **llama.cpp C API**: it changes between releases; the version is pinned and updated on
  purpose.
- **Chat templates**: `llama_chat_apply_template` recognizes common families only. A future
  model with an unusual template fails at `prepare` with a clear error; supporting it means
  adding a format to `LlamaSummaryService`, not touching the rest.
- **English words in French text** (e.g. "bugs") are sometimes misread by the voice.
- **Quality on real selections**: the bench used 7 texts. Before the release, run 30 to 50
  real selections (mail, Slack, articles) in French and English.
- **Supertonic-3's OpenRAIL++ licence** carries use restrictions that pass on to users; check
  the wording to show in the app.
