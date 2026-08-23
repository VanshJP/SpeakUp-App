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

## Progress page shape (conclusion → evidence → guidance)

`HistoryView.progressContent` owns the page rhythm in one `VStack(spacing: 20)`
— every chapter sits the same distance apart. Order follows the user's actual
intent: verdict, then the charts they came for, then guidance.

1. **Where am I and which way am I moving?** — one hero band
   (`ProgressChartsContent.heroBand`) shown only once loading finished and
   ≥ 2 analyzed sessions exist: the latest score inside a ring gauge (scale
   made physical), the momentum verdict opposite it ("+N pts lately" caption
   beneath), then cadence stats (Best · Average · This week).
2. **Evidence — trends first.** The trends chapter (`GlassSectionHeader`
   "Trends" with a "N sessions" accessory): chart tabs (`ChartTab`: Score /
   Pace / Fillers / Language / Skills / Activity), time-range menu, and the
   selected chart. All trend plots share `TrendChart.plotHeight` (210) so tab
   switches don't reflow; card headers use `GlassCardTitle`. The picker is
   icon-free text segments in a `ViewThatFits`: equal-width single row when
   six labels fit, scrolling rail at accessibility sizes — every destination
   visible, nothing hiding behind an unmarked scroll. Skills renders
   `SkillBreakdownCard` (the same `SubscoreRadarChart` sunburst as the
   session detail hero).
3. **Guidance — which situation needs work?** The scenario family (below)
   collapsed into ONE ranked card under `GlassSectionHeader("Where to
   Improve")`.

State is consolidated at the body level: while loading → bare spinner;
< 2 analyzed sessions → one `EmptyStateCard` ("Your Progress Starts Here" /
"One Take In"). No scattered empty states firing at once.

The tail after `ProgressChartsContent`: Practice Tools only — a 2×2 grid of
`ToolTileLabel` tiles (compare, listen back, goals, journal; compare/listen
hidden until two summaries exist). Word Bank usage moved inside the Language
tab (`ProgressChartsContent.vocabWords` → `LanguageInsightsView`), so the
page ends at tools instead of an orphaned chip rail.

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
- **Card hierarchy:** one ranked card, weakest first (the section header says
  so). Each practiced scenario is a row that stacks downward instead of
  splitting into two columns: title + momentum glyph + score on one baseline,
  a `TickMeter` at the score's fraction (the same meter `ScoreHeroCard` uses,
  so "how far along" reads without comparing bare numbers), a meta line
  "band · N sessions · early read", and — when there is one — a full-width
  line naming the habit costing the most ("'really' costs you most here —
  1× so far"). That line used to share a truncating caption with the session
  count and got cut mid-word. Unpracticed core scenarios follow in the same
  list as dimmed rows ending in "Not yet" (previously a `plus.circle` that
  looked tappable and was wired to nothing). A quiet footer line carries the
  combined readiness composite.
- **Thin-data honesty:** < 4 sessions (`ScenarioReadiness.confidenceThreshold`)
  marks the card "early read" and caps its score at 84
  (`earlyReadScoreCap`) so thin data can never claim "Ready".
- **Momentum has one encoding.** `ScenarioMomentum.symbolName` / `.label` /
  `.tint` (extension in `ScenarioReadinessSection.swift`, mirroring
  `CrutchCategory.badgeColor`) back both the hero's filled pill and the
  readiness rows' inline glyph. They were separate switches and had already
  drifted — slipping was red in one and amber in the other on the same
  screen. Slipping is amber: a dipping score wants attention, `AppColors.error`
  reads as broken.
- **Ordering rule:** practiced rows sort lowest readiness first (ties broken
  by more sessions). Justification: the hero band already answered
  trajectory; this section's job is directing attention to the
  highest-leverage gap.

## Language tab (language profile)

The **Language** tab (`ChartTab.words`) renders the cross-session lexicon
profile plus Word Bank practice words — deliberately the ONE word home on the
page. Every section explains itself: each card carries one line saying what it
counts and why that matters, impact verbs and recurring topics share one "Word
Mix" card with labeled groups, and "Word Bank in Practice" states what it
counts ("Saved words from your daily workouts, counted across your takes").

- **Advice is never a chip.** Crutch-word swaps render as one wrapped
  sentence ("Try instead  'significant' · cut it · 'genuinely' sparingly"),
  not capsules. As capsules they sat one card above the Word Mix chips and
  read as more words the speaker had said — and a pill reading "cut it" is
  shaped identically to a pill reading "significant". In running text the
  quoted entries are the wording to borrow and the unquoted ones are the move
  to make.
- **One chip family.** `WordCountChip` has a single form — tinted capsule,
  hairline, quiet tinted count. The filled-badge variant is gone; three word
  lists in a column previously used three different chip treatments and read
  as three unrelated systems. Tint plus the group label carries the meaning.
- **Topic hygiene.** `LexiconInsightsEngine.stopwords` covers contractions
  ("i'm", "wasn't" — `NLTokenizer` keeps them whole and `normalize` only trims
  the ends, so the stems never match) and the speech verbs that frame a topic
  without being one ("want", "know", "think", "say", "tell"). Untreated they
  outranked real subjects in "Topics you return to". The list stops there on
  purpose: "make", "take" and "use" stay out, because "make films" is the kind
  of subject it must not eat. Blast radius is `contentWords` only — fillers,
  hedges, intensifiers, vague nouns and impact verbs are all matched and
  `continue`d earlier in the loop, which is also the trap: a word in both
  lists silently takes the earlier branch.
  `stopwordsStayDisjointFromTheClassifiedLists` guards it.

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
7. Chart math is memoized per points-change (`PlotModel` built in each chart's `init(points:)`; scrub state never re-runs it), and plots key points by stable recording UUIDs. Comparison, replay, and Story Detail render value snapshots decoded once at load; journal export decodes its date range once in a detached background pass and hands the file to `SharePresenter`.

## Cross-links

[monetization.md](./monetization.md) · [recording-detail.md](./recording-detail.md) · [analytics-review.md](./analytics-review.md) · [speech-pipeline.md](./speech-pipeline.md) · `/docs/AGENT_GOTCHAS.md`
