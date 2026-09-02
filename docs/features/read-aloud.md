# Read Aloud

**Summary:** Practice reading scripted text with word-level accuracy scoring. Pick a catalog passage **or type any word, sentence, or short paragraph**, hear a TTS model, optionally open the system dictionary for a single word, then record and match against the source.

Also supports **Shadow mode** (hear the TTS model, then speak it back) and **Minimal pairs** packs.

**Key symbols:** `ReadAloudPassage`, `ReadAloudCategory`, `ReadAloudSelectionView`, `ReadAloudSessionView`, `ReadAloudResultView`, `WordAlignmentScorer`, `PronunciationService`, `DictionaryView`

**Related:** [SPEECH.md](../../SPEECH.md) (alignment), [practice-tools.md](practice-tools.md), [monetization.md](monetization.md)

---

## Product intent

**Accuracy under a known script** — not impromptu invention. Catalog passages train fluency on fixed text. **Practice anything** covers dictionary-style single-word drills and self-chosen sentences or paragraphs without a sixth practice-tool kind.

Free: catalog + custom. Same scoring path for both.

---

## Entry

Library (`PracticeHubView`) → **Read Aloud** (`PracticeToolKind.readAloud`) → `ReadAloudSelectionView` → `ReadAloudSessionView` → `ReadAloudResultView`.

Hub outcome: *Train clarity on a passage — or your own word.*

---

## Selection UI (`ReadAloudSelectionView`)

### Practice anything (custom)

Top `GlassCard`:

1. **Text field** — word, sentence, or short paragraph (`axis: .vertical`, 2–6 lines). Cap `ReadAloudPassage.customMaxCharacters` (800).
2. **Hear it** — `PronunciationService.speak(word:)` via `AVSpeechSynthesizer`. Multi-word phrases speak as one utterance; >3 tokens use rate `0.32`, else `0.35`.
3. **Define** — shown only when `PronunciationService.canDefine` is true (single token + system dictionary has a definition). Opens `DictionaryView` → `UIReferenceLibraryViewController`. Phrases/sentences stay Hear + Practice only.
4. **Practice saying it** — `ReadAloudPassage.custom(from:)` → same session sheet as catalog rows.

Empty / under-min / whitespace-only Practice and Hear are disabled.

### Catalog

Category chips from `ReadAloudCategory.catalogCases` (excludes `.custom`). Difficulty + category filter pills; rows are `PracticeItemRow`.

---

## Custom passage model

```swift
ReadAloudPassage.custom(from: text) // id: "custom-<uuid>", category: .custom
```

| Rule | Value |
|------|--------|
| Min length | `customMinCharacters` (2) |
| Max length | `customMaxCharacters` (800), prefix-capped |
| Title | 1 word → "Word practice"; 2–20 → "Sentence practice"; else "Paragraph practice" |
| Difficulty | 1–8 words → `.easy`; 9–40 → `.medium`; else `.hard` |

Not in `DefaultReadAloudPassages.all` — ephemeral only. `isCustom` is `category == .custom`.

`ReadAloudCategory.custom` is for typing only; filters use `catalogCases`.

---

## Session & scoring

Unchanged for custom vs catalog:

1. Show source text; record via `AudioService`.
2. Transcribe (`SpeechService`).
3. `WordAlignmentScorer.score(reference:transcript:)` — matched / missed / extra.
4. Persist `Recording` with `promptCategory: "Read Aloud"`, analysis JSON including alignment.

Silence-is-not-a-score applies (see practice-tools invariant 14).

---

## Pronunciation service

| API | Behavior |
|-----|----------|
| `speak(word:)` | Strip edge punctuation; rate by token count (>3 tokens → `0.32`, else `0.35`) |
| `speak(text:rate:)` | Keeps punctuation for prosody — shadow mode's model line |
| `canDefine(_:)` | Single token only; then `UIReferenceLibraryViewController.dictionaryHasDefinition` |
| `stripPunctuation(_:)` | Shared with `DictionaryView` |

---

## Files

| Path | Role |
|------|------|
| `SpeakUp/Models/ReadAloudPassage.swift` | Catalog types + `custom(from:)` |
| `SpeakUp/Views/ReadAloud/ReadAloudSelectionView.swift` | Practice anything + catalog |
| `SpeakUp/Views/ReadAloud/ReadAloudSessionView.swift` | Record + score |
| `SpeakUp/Views/ReadAloud/DictionaryView.swift` | System dictionary sheet |
| `SpeakUp/Services/PronunciationService.swift` | TTS + define gate |
| `SpeakUpTests/ReadAloudCustomPassageTests.swift` | Custom factory + define gate |

---

## Agent notes

- Presented from Practice Hub **tools** section (pushed full page), Today, and RecordingDetail next-steps as sheets — not its own tab.
- Difficulty coloring via `AppColors.difficultyColor` — not raw system colors.
- Keep passage seed data in `Data/`, not inline in views. Custom “Practice anything” passages are ephemeral (`ReadAloudPassage.custom`) and never appended to the seed array.
- Shadow mode plays `PronunciationService.speak(text:rate:)` before `startSession`; copy must not claim accent therapy — score remains alignment / clarity.
- Minimal pairs (`ReadAloudCategory.minimalPairs`) score word hits via the same alignment engine, not phoneme accuracy.
- **Silence is not a score.** Mic permission + the record-capable session come from a session-scoped `AudioService.requestPermission()` before the engine starts; recognition failure sets `service.recognitionFailureMessage`, ends the session within 250 ms, and lands on the result screen as a warning notice — never a confident "0% · Complete". A session that heard nothing for >3 s gets the "didn't catch any words" notice and `Haptics.warning()`.
- The alignment engine (`ReadAloudService.computeAlignment`) is pure/static and pinned by `SpeakUpTests/ReadAloudAlignmentTests.swift`: reference-skips via lookahead, single-word insertion tolerance (fillers don't consume words), and number normalization (page "seventy-two" matches recognizer "72") — change behavior through tests.
- Result screen reports actual wpm against the ≈150 promise when the take is long enough to mean it (>5 s).
- Word texts carry state-aware accessibility labels in both session and review ("missed X, you said Y"); upcoming words are hidden from VoiceOver.

- Do **not** add a sixth `PracticeToolKind` for “pronounce word” — extend Read Aloud.
- Custom passages are ephemeral (UUID id); never append to the static catalog.
- `canDefine` must stay single-word; sentences use Hear + Practice only.
- Filter chips: `catalogCases`, never `allCases` (would show a useless Custom chip).
