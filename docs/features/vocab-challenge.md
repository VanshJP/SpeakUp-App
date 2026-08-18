# Vocab challenge — daily word workout

## Purpose

Spotlight a few words each day and ask the user to use each one in a sentence. Mixes the existing word bank, dictation dictionary, and a curated speaking lexicon so vocabulary grows without homework.

An FSRS schedule decides *when* a word comes back, so words the user has already met resurface just before they would fade instead of only when the shuffle happens to pick them. Speaking a word is its review — there is no rating UI.

## Key files

| Role | Path |
|------|------|
| Preferences | `UserSettings` (`vocabChallengeEnabled`, `vocabChallengeWordCount`, `vocabChallengeIntroduceNew`) |
| Pick / evaluate / grade | `SpeakUp/Services/VocabChallengeService.swift` |
| FSRS scheduler | `SpeakUp/Services/VocabScheduler.swift` (`VocabReviewState`, `VocabGrade`) |
| Day cache / skips / schedule | `SpeakUp/Services/VocabChallengeStore.swift` |
| Safety | `SpeakUp/Services/WordSafety.swift` |
| Matching | `SpeakUp/Services/VocabMatcher.swift` (shared with transcript highlighting) |
| Lexicon | `SpeakUp/Data/DefaultVocabLexicon.swift` |
| Models | `SpeakUp/Models/VocabChallenge.swift` |
| Today card | `SpeakUp/Views/Today/VocabChallengeCard.swift` |
| Settings | `VocabChallengeSettingsCard` in `WordBankView.swift` |
| Recording strip | `VocabStrip` in `RecordingView.swift` — chips light when live transcription matches via `VocabMatcher` |
| Tests | `SpeakUpTests/VocabChallengeTests.swift` |

## Invariants

1. Off by toggle (`vocabChallengeEnabled`). Default on. Settings → Words exposes exactly three things: the master toggle, words per day (1–3), and whether the app teaches words the user does not already track. `vocabChallengeUseBank` / `UseDictionary` / `SpacedReview` are still stored and still honoured by the picker, but nothing writes them anything but `true` — they were knobs with only one sensible answer sitting on the page that manages the words themselves.
2. `WordSafety` blocks profanity and slurs on **add** (bank + dictionary) and on **pick**. Existing dirty entries are not deleted; they are never spotlighted. Fillers and the user's name are never spotlighted.
3. Today's pick is cached for the calendar day so a recording does not reshuffle the words. Skip replaces one word for the rest of the day, and the replacement is written back into the skipped word's slot — the refill appends, so without that the row jumps to the bottom of the card under the user's finger.
4. Introduced lexicon words are merged into analysis `vocabWords` so they highlight in the transcript before the user taps Add.
5. Completion = every spotlight word appears in today's transcripts (inflection-aware). Progress can accumulate across sessions the same day.
6. Do not decode `Recording.analysis` in a view `body` to build the Today card — `TodayViewModel` projects usage off the main thread.
7. Spacing is always on in the app. `spacedReviewEnabled: false` still works and restores the old pick — a fresh word first, then the least-used ones, with no schedule written — but only tests take that path.
8. Review state lives in `UserDefaults`, not SwiftData. It is a few doubles per word, has to be readable off the main actor while picking, and does not sync.
9. Grading happens in exactly two places, both idempotent per day via `lastGradedDay`: `RecordingProcessingCoordinator` calls `recordUsage` when analysis lands (spoken = pass), and `settleUnusedWords` grades a previous day's untouched pick as a lapse when the next day's challenge is built. Never grade from a view `body`.
10. A word missed four days running stops leading the day (`leechThreshold`) so ignoring the workout cannot pin the same words on screen forever.
11. When more than one word a day is on and new words are enabled, one slot is always reserved for a fresh word — a backlog of due reviews must never starve out learning.

## Scheduling shape

Grades come from usage alone: spoken once or twice = `good`, three or more times in a day = `easy`, never spoken on the day it was spotlighted = `again`. Retention is fixed at 0.9 and intervals are capped at 90 days. A word spoken every time it comes up moves out roughly 4 → 15 → 50 → 90 days; a missed word returns the next day.

Words the workout introduced are scheduled too, even when the user never taps Add — otherwise a new word would be shown once and only return by chance. The random intro draw excludes anything that already has a schedule.

## Cross-links

[today-library.md](./today-library.md) · [settings.md](./settings.md) · [recording.md](./recording.md) · [recording-detail.md](./recording-detail.md) · [speech-pipeline.md](./speech-pipeline.md)
