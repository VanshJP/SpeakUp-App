# History, progress, journal, streak

## Purpose

Browse takes, contribution/streak UI, plus the Progress page's conclusion →
evidence → reference flow: trajectory hero band, per-scenario readiness,
language profile, metric charts, then-vs-now replay, PDF journal export.

## Key files

| Area | Path |
|------|------|
| History | `SpeakUp/Views/History/` — `HistoryView`, `ActivityStrip`, `ComparisonView`, `ProgressChartsView` |
| Trajectory hero | `ProgressChartsContent.heroBand` (in `ProgressChartsView.swift`) |
| Scenario readiness | `SpeakUp/Services/ScenarioReadinessEngine.swift` + `SpeakUp/Views/History/ScenarioReadinessSection.swift` |
| Progress | `SpeakUp/Views/Progress/` — `BeforeAfterReplayView`, `JournalExportView`, `JournalSummaryView` |
| Language insights | `SpeakUp/Views/History/LanguageInsightsView.swift` + `SpeakUp/Services/LexiconInsightsEngine.swift` |
| Streak | `SpeakUp/Views/Streak/` — `StreakDetailView`, `FlameAnimationView` |
| VMs | `HistoryViewModel` (`RecordingSummary`), `ComparisonViewModel`, `ProgressReplayViewModel` |
| Services | `JournalExportService`, `ProgressCardRenderer` |
| Model | `ProgressCardData.swift` |
| Tests | `SpeakUpTests/LexiconInsightsTests.swift`, `SpeakUpTests/ScenarioReadinessTests.swift` |

## Progress page shape (conclusion → evidence → reference)

The Progress section answers three questions in order:

1. **Where am I and which way am I moving?** — one hero band
   (`ProgressChartsContent.heroBand`) once ≥ 2 analyzed sessions exist: latest
   score, a momentum verdict (Improving / Steady / Slipping from recent-half vs
   early-half mean of all session scores), and cadence stats (Best · Average ·
   This week). Replaces the former "Your Journey" card plus three stat cards.
2. **Which situation needs work?** — the scenario readiness family (below).
3. **Reference** — chart tabs (`ChartTab`: Score / Words / Fillers / Pace /
   Skills / Activity) and the secondary tools row (compare, replay, goals,
   journal) that `HistoryView.progressContent` appends.

## Scenario readiness

The single ambiguous "Interview Readiness" card is replaced by per-scenario
readiness cards so "how ready am I" gets a concrete object.

- **Engine:** `ScenarioReadinessEngine` (pure, `nonisolated`, no SwiftData).
  It consumes `[LexiconSessionInput]` — the same PODs already built inside
  `ProgressChartsContent.loadPoints()`'s single background `ModelContext`
  pass — buckets them by prompt category, runs each bucket back through
  `LexiconInsightsEngine.profile(from:)` (so every card uses the exact
  composite weights of the old aggregate: fluency .18, authority .20,
  impact verbs .22, evidence .12, depth .14, consistency .14), and emits
  small `ScenarioReadiness` PODs sorted weakest first.
- **Taxonomy:** categories map to scenarios by where the skill is performed
  (compiler-checked exhaustive switch + string path pinned by tests):
  - **Interviews** ← Interview Prep, Professional Development, Problem Solving
  - **Public Speaking** ← Elevator Pitch, Debate & Persuasion, Quick Fire
  - **Storytelling** ← Storytelling category + the `"Story"` marker for
    story-linked sessions (`ScenarioReadinessEngine.storyMarker`)
  - **Everyday Conversation** ← Conversation Starters, Communication Skills,
    Personal Growth, Describe & Explain, Current Events & Opinions
  - **Everything Else** ← freeform takes and unrecognized custom categories;
    rendered only when such sessions exist, never as an invitation.
- **Card contents:** ring + score, band label (Ready / Strong position /
  Getting there / Building blocks), momentum badge (half-split score trend
  via `TrajectorySummary`), and a "Holding it back: 'like' ×12" line from the
  bucket's dominant crutch.
- **Thin-data honesty:** < 4 sessions (`ScenarioReadiness.confidenceThreshold`)
  marks the card "early read" and caps its score at 84
  (`earlyReadScoreCap`) so thin data can never claim "Ready".
- **Ordering rule:** practiced cards sort lowest readiness first (ties broken
  by more sessions). Justification: the hero band already answered
  trajectory; the section's next job is directing attention to the
  highest-leverage gap. Unpracticed core scenarios render as compact
  invitation rows pointing at what practicing there builds.
- **Aggregate survival:** the old composite survives only as the small
  "All scenarios · N" chip in the section header — the full-card slot belongs
  to concrete scenarios now.

## Words tab (language profile)

The **Words** tab (`ChartTab.words`) renders the cross-session lexicon profile
as supporting detail under the scenario family.

- **Engine:** `LexiconInsightsEngine` (pure, `nonisolated`) consumes
  `[LexiconSessionInput]` — one per recording: date, transcript, pipeline
  filler dict, overall score. Built in the same background pass as above;
  transcripts are decoded off-main only and there is no second fetch.
- **Crutch taxonomy:** pipeline fillers (authoritative when present, tokens are
  skipped to avoid double counting), token fallback via `FillerWordList`
  otherwise, hedge phrases (regex), softener intensifiers, vague nouns.
  Separately: impact verbs (~90 inflected action verbs) and numeric-evidence
  markers (digit-bearing tokens).
- **Trend:** sessions sorted by date split into early/recent halves → per-word
  rising/falling direction and weak/power rate deltas (per 100 words); weekly
  buckets feed the dual-line chart.
- The former "By Practice Type" rows are superseded by scenario readiness
  cards and removed from this tab.
- **Components:** the tab reuses the design system throughout — `RingProgress`,
  `StatPair`, `MetricRow`, `StatusPill`, `WordCountChip`, and `FlowLayout`.
  The per-session counterpart is `CrutchSwapsCard` on the transcript tab
  (see [recording-detail.md](./recording-detail.md) § Word swaps).

## Invariants

1. **No analysis decode in list/chart `body`.** Background `ModelContext` → `RecordingSummary` / `ChartRecordingPoint` (`HistoryViewModel.fetchSummaries`, `ProgressChartsView`). Recipe: `/docs/AGENT_GOTCHAS.md` §3.
2. Never `#Predicate { $0.analysis != nil }` — process crash. Proxy with `transcriptionText != nil` when counting analyzed takes.
3. **Scenario readiness math is pure.** `ScenarioReadinessEngine` takes only `[LexiconSessionInput]` PODs, runs inside `loadPoints()`'s existing detached task, and is unit-tested for exhaustive category bucketing, thin-data thresholds, monotonicity, and empty state (`SpeakUpTests/ScenarioReadinessTests.swift`). No SwiftData inside.
4. Journal export is ungated during the beta ([monetization.md](./monetization.md)).
5. Progress / share cards are **not** gated (`PaidFeature.progressCards` exists but is omitted from both `FreeTierPolicy.trial` and `.expired`) — share loop must stay free for acquisition. Shares go through `SharePresenter`.
6. Streak sheet is presentation from Today/History — not a tab.

## Cross-links

[monetization.md](./monetization.md) · [recording-detail.md](./recording-detail.md) · [analytics-review.md](./analytics-review.md) · [speech-pipeline.md](./speech-pipeline.md) · `/docs/AGENT_GOTCHAS.md`
