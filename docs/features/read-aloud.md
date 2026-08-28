# Read-Aloud

## Purpose

Practice delivering a passage vs a reference text. Pronunciation score + per-word dictionary lookup.

## Key files

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/ReadAloud/` — `ReadAloudSelectionView`, `ReadAloudSessionView`, `ReadAloudResultView`, `DictionaryView`, `WordDetailSheet` |
| VM | `SpeakUp/ViewModels/ReadAloudViewModel.swift` |
| Scoring | `SpeakUp/Services/ReadAloudService.swift` |
| Speak / define | `SpeakUp/Services/PronunciationService.swift` (`AVSpeechSynthesizer`, `UIReferenceLibraryViewController`) |
| Model / data | `ReadAloudPassage.swift`, `Data/DefaultReadAloudPassages.swift` |

## Invariants

- Presented from Practice Hub **tools** section (pushed full page), Today, and RecordingDetail next-steps as sheets — not its own tab.
- Difficulty coloring via `AppColors.difficultyColor` — not raw system colors.
- Keep passage seed data in `Data/`, not inline in views.
- **Silence is not a score.** Mic permission + the record-capable session come from a session-scoped `AudioService.requestPermission()` before the engine starts; recognition failure sets `service.recognitionFailureMessage`, ends the session within 250 ms, and lands on the result screen as a warning notice — never a confident "0% · Complete". A session that heard nothing for >3 s gets the "didn't catch any words" notice and `Haptics.warning()`.
- The alignment engine (`ReadAloudService.computeAlignment`) is pure/static and pinned by `SpeakUpTests/ReadAloudAlignmentTests.swift`: reference-skips via lookahead, single-word insertion tolerance (fillers don't consume words), and number normalization (page "seventy-two" matches recognizer "72") — change behavior through tests.
- Result screen reports actual wpm against the ≈150 promise when the take is long enough to mean it (>5 s).
- Word texts carry state-aware accessibility labels in both session and review ("missed X, you said Y"); upcoming words are hidden from VoiceOver.

## Cross-links

[today-library.md](./today-library.md) · [ui-design-system.md](./ui-design-system.md) · [practice-tools.md](./practice-tools.md)
