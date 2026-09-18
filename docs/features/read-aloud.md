# Read Aloud

**Summary:** Practice reading scripted text with word-level accuracy scoring. Pick a catalog passage or a saved passage, or add personal text in a focused composer. The composer accepts typing, Clipboard paste, and TXT, RTF, RTFD, or PDF imports. Users can hear a TTS model, optionally open the system dictionary for a single word, then record and match against the source.

Also supports **Shadow mode** (hear the TTS model, then speak it back) and **Minimal pairs** packs.

**Key symbols:** `ReadAloudPassage`, `ReadAloudCategory`, `ReadAloudSelectionView`, `ReadAloudSessionView`, `ReadAloudResultView`, `ReadAloudService`, `PronunciationService`, `DictionaryView`

**Related:** [SPEECH.md](../../SPEECH.md) (alignment), [practice-tools.md](practice-tools.md), [monetization.md](monetization.md)

---

## Product intent

**Accuracy under a known script**, not impromptu invention. Catalog passages train fluency on fixed text. **Your passages** covers dictionary-style single-word drills and self-chosen excerpts without a sixth practice-tool kind.

Free: catalog + custom. Same scoring path for both.

---

## Entry

Library (`PracticeHubView`) → **Read Aloud** (`PracticeToolKind.readAloud`) → `ReadAloudSelectionView` → `ReadAloudSessionView` → `ReadAloudResultView`.

`ReadAloudSelectionView(initialPracticeText:)` opens a scored session immediately on an ephemeral `ReadAloudPassage.custom(from:)`, skipping the list and composer. Recording detail's word swaps use it to rehearse a rewritten line (see [recording-detail.md](./recording-detail.md)). Same auto-start shape as `DrillSelectionView(initialMode:)`: a `.task` on the selection view, so the cover presents after the sheet has settled.

Hub outcome: *Train clarity against a script — ours or your own.* Format line (`PracticeToolKind.format`): *Mic on · scored word by word.*

---

## Selection UI (`ReadAloudSelectionView`)

### Your passages

**Adding lives in the nav bar** — a `ToolPageAction(icon: "plus")` handed to
`ToolPage`, which renders it `.topBarTrailing` in both presentations. It used to
be a full-width glass card pinned above the catalog, so a page for reading
passages opened on a form for writing one and the passages started below the
fold. Library already puts "add" in the chrome for Prompts and Stories; this is
the pushed-page equivalent. Do not move it back into the column.

The **Your passages** rail renders only when there is something saved, and ends
with a compact "Add your own" card — a second door for people who already have
passages. Tapping a card starts practice; its visible actions menu supports edit
and confirmed deletion without requiring a hidden context menu.

### Passage composer

`ReadAloudComposerSheet` owns the creation flow:

1. **Paste** reads Clipboard text after an explicit tap.
2. **Import File** accepts TXT, RTF, RTFD, and text-based PDF documents through `ReadAloudDocumentImporter`.
3. **Type or edit** uses a dedicated editor with live word and character counts.
4. **Hear It** uses `PronunciationService.speak(word:)`. Multi-word phrases speak as one utterance; more than three tokens use rate `0.32`, otherwise `0.35`.
5. **Define** appears only when `PronunciationService.canDefine` is true. It opens `DictionaryView` and then `UIReferenceLibraryViewController`.
6. **Save and Practice** keeps the text and starts the normal scored session after the composer dismisses.
7. **Save for Later** stores the text without starting a session.

Replacing non-empty editor text through Paste or Import requires confirmation. Empty, under-minimum, whitespace-only, and over-limit drafts cannot be saved, heard, or practiced.

The scoring engine is designed for one focused section. If imported text exceeds `customMaxCharacters` (800), the importer selects an opening at the nearest sentence, paragraph, or word boundary and tells the user. Pasted or typed over-limit text offers the same one-tap **Use First Practice Section** recovery. Scanned PDFs fail with a clear OCR-specific message instead of appearing to import empty content.

### Catalog

**Grouped by `PracticeFocus`**, not by source material. `news` → `.pace`,
`literature` → `.presence`, `technical` / `tongueTwister` / `minimalPairs` /
`custom` → `.clarity`. "News" and "Literature" say where the words came from,
which is not why anyone picks a passage; the category is now the row's tag.

Two filter bars: a shared `FocusFilterBar` over `viewModel.availableFocuses`
(= `PracticeToolKind.readAloud.focuses`, counted from the seed array so a pill
can never filter to nothing), then length pills from `ReadAloudDifficulty`.
Sections are the shared `FocusSection`; rows are `PracticeItemRow`.
`initialFocus:` arrives from the Library outcome browser.

See [practice-tools.md](practice-tools.md) invariants 17–20 for the shared axis and its components.

---

## Custom passage model

```swift
ReadAloudPassage.custom(from: text) // id: "custom-<uuid>", category: .custom, ephemeral
ReadAloudPassage.saved(from: text)  // id: "saved-<text>", category: .custom, kept
```

Both run the same title / difficulty / cap rules (`make(text:id:)`); only the id differs. `custom` gets a fresh UUID per call because it is thrown away after the take; `saved` derives its id from the text so a kept row keeps one identity across renders and launches. Saved texts are de-duplicated case-insensitively, which is what makes the text a sound key.

| Rule | Value |
|------|--------|
| Min length | `customMinCharacters` (2) |
| Max length | `customMaxCharacters` (800), prefix-capped |
| Title | 1 word: "Word practice"; 2 to 20: "Sentence practice"; otherwise "Paragraph practice" |
| Difficulty | 1 to 8 words: `.easy`; 9 to 40: `.medium`; otherwise `.hard` |

Not in `DefaultReadAloudPassages.all`. `isCustom` is `category == .custom`.

### Saved passages

| Where | What |
|-------|------|
| Storage | `UserSettings.savedReadAloudTexts: [String]`, additive, defaulted, raw text only |
| List rules | `SavedReadAloudTexts.adding/removing/contains`, a `nonisolated enum` in `ReadAloudPassage.swift`, so the rules are testable without a `ModelContainer` (gotcha §12) |
| Order | Newest first |
| Derived | Title, difficulty and id all come from the text and are never stored, so they cannot drift from `custom(from:)`'s rules |

The seed catalog is still static: saving writes to `UserSettings`, never to `DefaultReadAloudPassages.all`.

`ReadAloudCategory.custom` is for typing only; catalog listings use `catalogCases` / `catalogCases(for:)` and never `allCases`.

---

## Session & scoring

Unchanged for custom vs catalog:

1. Show source text; record via `AudioService`.
2. Transcribe (`SpeechService`).
3. `ReadAloudService.computeAlignment(reference:normalizedReference:spokenWords:)` — matched / missed / extra.
4. Show `ReadAloudResultView`, then reset on Done or run the same passage on Retry.

Current code does **not** persist a SwiftData `Recording`; Read-Aloud results
are session-local and therefore absent from History and longitudinal clarity
charts. Successful matching still writes the curriculum activity signal. Treat
History persistence as future product work, not as an implemented contract.

**Recognition survives its own request boundaries.** `SFSpeechRecognizer`
closes a request after a pause in speech and again at the request's own
audio-duration ceiling; a reader working through a paragraph triggers both,
several times. `ReadAloudService` re-arms on the same engine and tap
(`armRecognition`) and keeps one transcript slot per request
(`segmentTranscripts`, joined by the pure `joinTranscripts`), so alignment sees
one continuous read and the reader never loses their place. It also rolls over
proactively every 45 s, and rebuilds the whole capture graph on an
`AVAudioEngineConfigurationChange` or after an interruption. Only a recognizer
that fails three times in a row inside a second — a device missing its on-device
assets — ends the session. See gotchas §9 and §26.

Silence-is-not-a-score applies (see practice-tools invariant 14).

---

## Pronunciation service

| API | Behavior |
|-----|----------|
| `speak(word:)` | Strip edge punctuation; rate by token count (>3 tokens → `0.32`, else `0.35`) |
| `speak(text:rate:)` | Keeps punctuation for prosody in shadow mode's model line |
| `canDefine(_:)` | Single token only; then `UIReferenceLibraryViewController.dictionaryHasDefinition` |
| `stripPunctuation(_:)` | Shared with `DictionaryView` |

---

## Files

| Path | Role |
|------|------|
| `SpeakUp/Models/ReadAloudPassage.swift` | Catalog types + `custom(from:)` / `saved(from:)` + `SavedReadAloudTexts` |
| `SpeakUp/Views/ReadAloud/ReadAloudSelectionView.swift` | Toolbar add action, saved rail, focus-grouped catalog |
| `SpeakUp/Views/ReadAloud/ReadAloudComposerSheet.swift` | Paste, import, edit, preview, save, and practice flow |
| `SpeakUp/Views/ReadAloud/ReadAloudSessionView.swift` | Record + score |
| `SpeakUp/Views/ReadAloud/DictionaryView.swift` | System dictionary sheet |
| `SpeakUp/Services/ReadAloudDocumentImporter.swift` | On-device TXT, rich text, and PDF extraction |
| `SpeakUp/Services/PronunciationService.swift` | TTS + define gate |
| `SpeakUp/Services/ReadAloudService.swift` | Session listening + `computeAlignment` |
| `SpeakUp/ViewModels/ReadAloudViewModel.swift` | Selection / session VM |
| `SpeakUpTests/ReadAloudAlignmentTests.swift` | Alignment core + request-boundary stitching |
| `SpeakUpTests/ReadAloudCustomPassageTests.swift` | Custom factory + define gate |
| `SpeakUpTests/PracticeFocusTests.swift` | Focus axis + derived catalog listings |

---

## Agent notes

- Presented from Practice Hub **tools** section (pushed full page through `ToolPresentation.pushed` via `navigationDestination`), Today, and RecordingDetail next-steps as sheets, not its own tab.
- Difficulty coloring uses `AppColors.difficultyColor`, not raw system colors.
- Keep passage seed data in `Data/`, not inline in views. Custom “Practice anything” passages are ephemeral (`ReadAloudPassage.custom`); kept ones persist on `UserSettings.savedReadAloudTexts`. Neither is appended to the seed array.
- Shadow mode plays `PronunciationService.speak(text:rate:)` before `startSession`; copy must not claim accent therapy because the score remains alignment and clarity. **Neither shadow control may be disabled while the model line plays.** Both carried `.disabled(pronunciationService.isSpeaking)`, which is exactly when a user reaches for them — the only way past the voiceover was to sit through it. "Start speaking" stops the synthesiser and opens the mic ("Skip & speak" while audio plays); the secondary button becomes Stop.
- Minimal pairs (`ReadAloudCategory.minimalPairs`) score word hits via the same alignment engine, not phoneme accuracy.
- **Silence is not a score.** Mic permission + the record-capable session come from a session-scoped `AudioService.requestPermission()` before the engine starts; recognition failure sets `service.recognitionFailureMessage`, ends the session within 250 ms, and lands on the result screen as a warning notice, never a confident "0% · Complete". A session that heard nothing for >3 s gets the "didn't catch any words" notice and `Haptics.warning()`.
- **A dead mic must never sit under a live clock.** `ReadAloudViewModel.startTimer` also ends the session when `service.isListening` goes false while the state still says `.listening`. Recognition now survives its own request boundaries, so that only fires for something unforeseen — and the old behaviour there (frozen passage, "Not listening", a disabled Done button, restart from the top) is precisely what a dropped read felt like.
- **The session cover is presented on the passage, the result cover on the result** (`fullScreenCover(item:)`). Both used to be `isPresented:` flags over state that `viewModel.reset()` or Retry clears, which drew an empty cover for the length of a dismissal. Gotcha §27.
- The alignment engine (`ReadAloudService.computeAlignment`) is pure/static and pinned by `SpeakUpTests/ReadAloudAlignmentTests.swift`: reference-skips via lookahead, single-word insertion tolerance (fillers do not consume words), and number normalization (page "seventy-two" matches recognizer "72"). Change behavior through tests.
- Result screen reports actual wpm against the ≈150 promise when the take is long enough to mean it (>5 s).
- Results are ephemeral today. Adding History support requires a deliberate `Recording`/analysis shape and media-storage lifecycle; do not imply persistence in UI copy until that exists.
- Word texts carry state-aware accessibility labels in both session and review ("missed X, you said Y"); upcoming words are hidden from VoiceOver.
- **Nothing about a word's match state may change its measured size.** The whole passage draws at one weight (`Self.passageWeight`); position is carried by the highlight fill and the colour ramp. The current word used to render `.bold` against `.regular` neighbours, and because bold glyphs are wider, every cursor advance re-flowed the rest of the line — the passage visibly squirmed while being read. Auto-scroll re-centres once per `scrollAdvanceWords` (8) rather than every second word, which was the other half of the same complaint.
- `WrappingHStack` caches its measurement pass per (width, `metricsKey`), with a first-subview probe as a tripwire for callers that do not pass a key. Without the cache it re-measured every subview in **both** `sizeThatFits` and `placeSubviews`, so a 150-word passage cost ~300 text measurements per layout pass, on every partial recognition result. See gotchas §25.
- Transcript updates **coalesce latest-wins** with at most one drain task in flight (`pendingTranscript` / `isDrainScheduled`), and the recognition callback lifts a `String` out before hopping actors — `SFSpeechRecognitionResult` and `any Error` are not `Sendable`.

- Do **not** add a sixth `PracticeToolKind` for “pronounce word”. Extend Read Aloud.
- Passages the user *types* stay ephemeral (UUID id). Passages the user *keeps* live on `UserSettings`, which is still not the static catalog. Never append to `DefaultReadAloudPassages.all`.
- `canDefine` must stay single-word; sentences use Hear + Practice only.
- Filter chips: `catalogCases`, never `allCases` (would show a useless Custom chip).
