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

- Presented from Practice Hub **tools** section (local sheet), not its own tab.
- Difficulty coloring via `AppColors.difficultyColor` — not raw system colors.
- Keep passage seed data in `Data/`, not inline in views.

## Cross-links

[today-library.md](./today-library.md) · [ui-design-system.md](./ui-design-system.md) · [practice-tools.md](./practice-tools.md)
