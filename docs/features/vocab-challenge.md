# Vocab challenge — daily word workout

## Purpose

Spotlight a few words each day and ask the user to use each one in a sentence. Mixes the existing word bank, dictation dictionary, a curated speaking lexicon (~400 words across three tiers), and — when an on-device model is available — freshly generated words validated against the same safety rules, so vocabulary grows without homework and the pool never runs dry.

An FSRS schedule decides *when* a word comes back, so words the user has already met resurface just before they would fade instead of only when the shuffle happens to pick them. Speaking a word is its review — there is no rating UI.

The user controls **how hard** the fresh words are (`vocabChallengeLevelOverride`: Auto follows their speaker level, Easy/Medium/Hard pin a tier) while FSRS keeps owning *when* anything returns.

## Key files

| Role | Path |
|------|------|
| Preferences | `UserSettings` (`vocabChallengeEnabled`, `vocabChallengeWordCount`, `vocabChallengeIntroduceNew`, `vocabChallengeLevelOverride`) |
| Pick / evaluate / grade | `SpeakUp/Services/VocabChallengeService.swift` |
| Fresh-word generation / validation / storage | `SpeakUp/Services/VocabFreshWords.swift` (`VocabFreshWordGenerator`, `FreshWordSanitizer`, `GeneratedVocabStore`) |
| FSRS scheduler | `SpeakUp/Services/VocabScheduler.swift` (`VocabReviewState`, `VocabGrade`) |
| Day cache / skips / schedule | `SpeakUp/Services/VocabChallengeStore.swift` |
| Safety | `SpeakUp/Services/WordSafety.swift` |
| Matching | `SpeakUp/Services/VocabMatcher.swift` (shared with transcript highlighting) |
| Lexicon | `SpeakUp/Data/DefaultVocabLexicon.swift` (three tiers, `level` 0/1/2) |
| Models | `SpeakUp/Models/VocabChallenge.swift` (`VocabChallengePreferences.resolvedIntroLevel`) |
| Per-recording snapshot | `Recording.vocabChallengeDayStamp` / `.vocabChallengeWords` (additive optionals) |
| Today brief strip | `SpeakUp/Views/Today/SessionBriefRow.swift` |
| Session result card | `SpeakUp/Views/Today/VocabChallengeResultCard.swift` |
| Settings | `WordWorkoutSettingsView` (hosts `VocabChallengeSettingsCard`, still defined in `WordBankView.swift`) |
| Recording strip | `VocabStrip` in `RecordingView.swift` |
| Tests | `SpeakUpTests/VocabChallengeTests.swift` |

## Invariants

1. Off by toggle (`vocabChallengeEnabled`). Default on. Settings → Word Workout exposes exactly four things: the master toggle, words per day (1–3), word level (Auto/Easy/Medium/Hard), and whether the app teaches words the user does not already track. `vocabChallengeUseBank` / `UseDictionary` / `SpacedReview` are still stored and still honoured by the picker, but nothing writes them anything but `true` — they were knobs with only one sensible answer sitting on the page that manages the words themselves.
2. `WordSafety` blocks profanity and slurs on **add** (bank + dictionary) and on **pick** — including every LLM-generated candidate, which must clear `allowsForChallenge` plus shape checks (single ASCII token, no digits/hyphens/apostrophes) before it can enter the store. Existing dirty entries are not deleted; they are never spotlighted. Fillers and the user's name are never spotlighted.
3. Today's pick is cached for the calendar day so a recording does not reshuffle the words. Skip replaces one word for the rest of the day, and the replacement is written back into the skipped word's slot — the refill appends, so without that the chip jumps to the end of the strip under the user's finger. Skip is reached by long-pressing a chip in `SessionBriefRow`.
4. Introduced lexicon words are merged into analysis `vocabWords` so they highlight in the transcript before the user taps Add.
5. Completion = every spotlight word appears in today's transcripts (inflection-aware). Progress can accumulate across sessions the same day.
6. Do not decode `Recording.analysis` in a view `body` to build the Today brief — `TodayViewModel` projects usage off the main thread.
7. Spacing is always on in the app. `spacedReviewEnabled: false` still works and restores the old pick — a fresh word first, then the least-used ones, with no schedule written — but only tests take that path.
8. Review state lives in `UserDefaults`, not SwiftData. It is a few doubles per word, has to be readable off the main actor while picking, and does not sync.
9. Grading happens in exactly two places, both idempotent per day via `lastGradedDay`: `RecordingProcessingCoordinator` calls `recordUsage` when analysis lands (spoken = pass), and `settleUnusedWords` grades a previous day's untouched pick as a lapse when the next day's challenge is built. Never grade from a view `body`.
10. A word missed four days running stops leading the day (`leechThreshold`) so ignoring the workout cannot pin the same words on screen forever.
11. When more than one word a day is on and new words are enabled, one slot is always reserved for a fresh word — a backlog of due reviews must never starve out learning.
12. Each recording snapshots its own-day workout exactly once, at processing time: `RecordingProcessingCoordinator` persists the day stamp and the picked `[VocabChallengeWord]` beside `recordUsage`, in the same re-fetch-then-write pass as the analysis save (so a failed analysis leaves no snapshot behind). One pick feeds transcript detection, FSRS grading, and the snapshot, so all three agree even if the user edits settings mid-transcription. Schema change is additive: both fields optional, nil for recordings analyzed before snapshots existed.
13. The detail view never substitutes today's challenge for a dated recording. `VocabChallengeService.workout(forRecordingAt:snapshotDayStamp:snapshotWords:preferences:)` resolves the card: snapshot present → that day's words; no snapshot but recorded today → today's pick (keeps scoring for takes processed by pre-snapshot builds on the same calendar day); no snapshot and recorded earlier → nil, the card hides. Silent-and-correct beats loud-and-wrong for history the app cannot honestly score.
14. The snapshot is authoritative over the day cache. If the user later skips/refills that day's words elsewhere, old recordings still show what they were actually shown; an empty or malformed snapshot hides the card instead of rendering a hollow one.
15. Uniqueness is layered: the curated pool is deep enough for months (≥100 per tier, asserted by test); fresh draws exclude everything with an FSRS schedule **and** everything graded inside a 21-day window (`freshnessWindowDays`), so chance never re-deals a card the user just saw. Deliberate FSRS returns are exempt — spaced repetition repeating a missed word is the design, not a bug.
16. Generated words are second-class until proven: they join the intro pool only after `FreshWordSanitizer` validation, they never shadow a curated entry with the same key, and they get FSRS schedules on the same terms as lexicon words (`lexiconEntry(for:)` merges both stores, or they could never come back as reviews). The generator runs fire-and-forget from `TodayView.task`, throttled to one attempt per six hours, refilling only when live stock drops below ten; any failure degrades silently to the curated lexicon.

## Level control shape

`VocabChallengePreferences.levelOverrideRaw`: 0 follows `speakerLevelRaw`; 1–3 pin beginner/intermediate/advanced. `resolvedIntroLevel` collapses both into one tier number, which is what the picker filters on and what the day-cache fingerprint carries — changing the level mid-day legitimately re-picks. Tier preference is exact-match first, adjacent tiers as exhaustion fallback, so a pinned tier can never blank the card.

## Scheduling shape

Grades come from usage alone: spoken once or twice = `good`, three or more times in a day = `easy`, never spoken on the day it was spotlighted = `again`. Retention is fixed at 0.9 and intervals are capped at 90 days. A word spoken every time it comes up moves out roughly 4 → 15 → 50 → 90 days; a missed word returns the next day.

Words the workout introduced are scheduled too, even when the user never taps Add — otherwise a new word would be shown once and only return by chance. The random intro draw excludes anything that already has a schedule.

## Cross-links

[today-library.md](./today-library.md) · [settings.md](./settings.md) · [recording.md](./recording.md) · [recording-detail.md](./recording-detail.md) · [speech-pipeline.md](./speech-pipeline.md)
