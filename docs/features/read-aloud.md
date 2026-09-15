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

Hub outcome: *Train clarity on a passage, including your own text.*

---

## Selection UI (`ReadAloudSelectionView`)

### Your passages

The selection page starts with one compact **Add Your Own Passage** row. The editor is not inline, so catalog passages remain visible near the top of the page.

Saved passages appear in a bounded horizontal rail. Tapping a card starts practice. Its visible actions menu supports edit and confirmed deletion without requiring a hidden context menu.

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

Category chips from `ReadAloudCategory.catalogCases` (excludes `.custom`). Difficulty + category filter pills; rows are `PracticeItemRow`.

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

`ReadAloudCategory.custom` is for typing only; filters use `catalogCases`.

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
| `SpeakUp/Views/ReadAloud/ReadAloudSelectionView.swift` | Compact custom entry, saved rail, and catalog |
| `SpeakUp/Views/ReadAloud/ReadAloudComposerSheet.swift` | Paste, import, edit, preview, save, and practice flow |
| `SpeakUp/Views/ReadAloud/ReadAloudSessionView.swift` | Record + score |
| `SpeakUp/Views/ReadAloud/DictionaryView.swift` | System dictionary sheet |
| `SpeakUp/Services/ReadAloudDocumentImporter.swift` | On-device TXT, rich text, and PDF extraction |
| `SpeakUp/Services/PronunciationService.swift` | TTS + define gate |
| `SpeakUp/Services/ReadAloudService.swift` | Session listening + `computeAlignment` |
| `SpeakUp/ViewModels/ReadAloudViewModel.swift` | Selection / session VM |
| `SpeakUpTests/ReadAloudCustomPassageTests.swift` | Custom factory + define gate |

---

## Agent notes

- Presented from Practice Hub **tools** section (pushed full page through `ToolPresentation.pushed` via `navigationDestination`), Today, and RecordingDetail next-steps as sheets, not its own tab.
- Difficulty coloring uses `AppColors.difficultyColor`, not raw system colors.
- Keep passage seed data in `Data/`, not inline in views. Custom “Practice anything” passages are ephemeral (`ReadAloudPassage.custom`); kept ones persist on `UserSettings.savedReadAloudTexts`. Neither is appended to the seed array.
- Shadow mode plays `PronunciationService.speak(text:rate:)` before `startSession`; copy must not claim accent therapy because the score remains alignment and clarity.
- Minimal pairs (`ReadAloudCategory.minimalPairs`) score word hits via the same alignment engine, not phoneme accuracy.
- **Silence is not a score.** Mic permission + the record-capable session come from a session-scoped `AudioService.requestPermission()` before the engine starts; recognition failure sets `service.recognitionFailureMessage`, ends the session within 250 ms, and lands on the result screen as a warning notice, never a confident "0% · Complete". A session that heard nothing for >3 s gets the "didn't catch any words" notice and `Haptics.warning()`.
- The alignment engine (`ReadAloudService.computeAlignment`) is pure/static and pinned by `SpeakUpTests/ReadAloudAlignmentTests.swift`: reference-skips via lookahead, single-word insertion tolerance (fillers do not consume words), and number normalization (page "seventy-two" matches recognizer "72"). Change behavior through tests.
- Result screen reports actual wpm against the ≈150 promise when the take is long enough to mean it (>5 s).
- Results are ephemeral today. Adding History support requires a deliberate `Recording`/analysis shape and media-storage lifecycle; do not imply persistence in UI copy until that exists.
- Word texts carry state-aware accessibility labels in both session and review ("missed X, you said Y"); upcoming words are hidden from VoiceOver.

- Do **not** add a sixth `PracticeToolKind` for “pronounce word”. Extend Read Aloud.
- Passages the user *types* stay ephemeral (UUID id). Passages the user *keeps* live on `UserSettings`, which is still not the static catalog. Never append to `DefaultReadAloudPassages.all`.
- `canDefine` must stay single-word; sentences use Hear + Practice only.
- Filter chips: `catalogCases`, never `allCases` (would show a useless Custom chip).
