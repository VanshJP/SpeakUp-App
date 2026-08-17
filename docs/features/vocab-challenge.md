# Vocab challenge — daily word workout

## Purpose

Spotlight a few words each day and ask the user to use each one in a sentence. Mixes the existing word bank, dictation dictionary, and a curated speaking lexicon so vocabulary grows without homework.

## Key files

| Role | Path |
|------|------|
| Preferences | `UserSettings` (`vocabChallengeEnabled`, word count, source toggles) |
| Pick / evaluate | `SpeakUp/Services/VocabChallengeService.swift` |
| Day cache / skips | `SpeakUp/Services/VocabChallengeStore.swift` |
| Safety | `SpeakUp/Services/WordSafety.swift` |
| Matching | `SpeakUp/Services/VocabMatcher.swift` (shared with transcript highlighting) |
| Lexicon | `SpeakUp/Data/DefaultVocabLexicon.swift` |
| Models | `SpeakUp/Models/VocabChallenge.swift` |
| Today card | `SpeakUp/Views/Today/VocabChallengeCard.swift` |
| Settings | `VocabChallengeSettingsCard` in `WordBankView.swift` |
| Overlay | `VocabOverlayPanel` in `RecordingView.swift` |
| Tests | `SpeakUpTests/VocabChallengeTests.swift` |

## Invariants

1. Off by toggle (`vocabChallengeEnabled`). Default on. Sources (bank / dictionary / new words) and count (1–3) are user-customizable in Settings → Words.
2. `WordSafety` blocks profanity and slurs on **add** (bank + dictionary) and on **pick**. Existing dirty entries are not deleted; they are never spotlighted. Fillers and the user's name are never spotlighted.
3. Today's pick is cached for the calendar day so a recording does not reshuffle the words. Skip replaces one word for the rest of the day.
4. Introduced lexicon words are merged into analysis `vocabWords` so they highlight in the transcript before the user taps Add.
5. Completion = every spotlight word appears in today's transcripts (inflection-aware). Progress can accumulate across sessions the same day.
6. Do not decode `Recording.analysis` in a view `body` to build the Today card — `TodayViewModel` projects usage off the main thread.

## Cross-links

[today-library.md](./today-library.md) · [settings.md](./settings.md) · [recording.md](./recording.md) · [recording-detail.md](./recording-detail.md) · [speech-pipeline.md](./speech-pipeline.md)
