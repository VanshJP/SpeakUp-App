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

The tail after `ProgressChartsContent`: **Review** only — a 2×2 grid of
`ToolTileLabel` tiles (compare, listen back, goals, journal; compare/listen
hidden until two summaries exist). These stay on Progress because they need
history data; Library → Tools is prep (warm-up / drill / read aloud / calm).
Do not merge the catalogs. Word Bank usage moved inside the Language
tab (`ProgressChartsContent.vocabWords` → `LanguageInsightsView`), so the
page ends at Review instead of an orphaned chip rail.

## Scenario readiness

Per-scenario readiness replaces a single ambiguous “Interview Readiness” score.

- **Engine:** `ScenarioReadinessEngine` (pure, `nonisolated`) consumes
  `[LexiconSessionInput]` PODs already built in
  `ProgressChartsContent.loadPoints()`, buckets by prompt category, profiles
  each bucket with `LexiconInsightsEngine.profile(from:)`, emits
  `ScenarioReadiness` sorted weakest-first. Composite weights live in
  code/tests — do not re-paste them here.
- **Taxonomy** (exhaustive switch + tests): Interviews; Public Speaking;
  Storytelling (+ `"Story"` marker); Everyday Conversation; Everything Else
  (only when such sessions exist).
- **UI:** one ranked card — title + momentum glyph + score, `TickMeter`,
  meta line, optional habit-cost line; unpracticed cores show “Not yet”.
- **Thin data:** < 4 sessions → “early read”, score capped. Momentum colors
  via `ScenarioMomentum` only (slipping = amber, never error-red).

## Language tab (language profile)

`ChartTab.words` is the one Progress home for lexicon + Word Bank usage.

- Crutch swaps are **sentences**, never chips. One `WordCountChip` family.
- Engine: `LexiconInsightsEngine` on the same background POD pass; stopword /
  dual-list traps pinned by `stopwordsStayDisjointFromTheClassifiedLists`.
- Components: `RingProgress`, `StatPair`, `MetricRow`, `StatusPill`,
  `WordCountChip`, `FlowLayout`. Session counterpart: `CrutchSwapsCard`
  ([recording-detail.md](./recording-detail.md)).

## Invariants

1. **No analysis decode in list/chart `body`.** Background `ModelContext` → `RecordingSummary` / `ChartRecordingPoint` (`HistoryViewModel.fetchSummaries`, `ProgressChartsView`). Recipe: `/docs/AGENT_GOTCHAS.md` §3. History appears after every take and on each tab switch, so `HistoryViewModel.configure` is single-flight: an appearance during a reload queues one more pass instead of a second scan beside it.
2. Never `#Predicate { $0.analysis != nil }` — process crash. Proxy with `transcriptionText != nil` when counting analyzed takes.
3. **Scenario readiness math is pure.** `ScenarioReadinessEngine` takes only `[LexiconSessionInput]` PODs, runs inside `loadPoints()`'s existing detached task, and is unit-tested for exhaustive category bucketing, thin-data thresholds, monotonicity, and empty state (`SpeakUpTests/ScenarioReadinessTests.swift`). No SwiftData inside.
4. Journal export is ungated during the beta ([monetization.md](./monetization.md)).
5. Progress / share cards are **not** gated (`PaidFeature.progressCards` exists but is omitted from both `FreeTierPolicy.trial` and `.expired`) — share loop must stay free for acquisition. Shares go through `SharePresenter`.
6. Streak sheet is presentation from Today/History — not a tab. It reads `streakFrozenDays`, counts streaks with `StreakProtection.liveSnapshot`, and surfaces the freeze bank (auto-spend, not a button).
7. **The page has no navigation bar.** `HistoryView` hides it (`.toolbar(.hidden, for: .navigationBar)`) like every root tab. The `SectionPicker` (Recordings / Progress) is the one pinned row; the `InlineSearchField` lives inside the Recordings section — Progress has nothing to search — carrying the filter menu on its trailing edge and scrolling away with the content. The bar it replaced said "History" above a tab button labelled History, and `.searchable` hung another ~50pt off it. `ComparisonView` and the pushed recording detail add `.restoresNavigationBar()`. Details: [ui-design-system.md](./ui-design-system.md) rule 9.
8. Chart math is memoized per points-change (`PlotModel` built in each chart's `init(points:)`; scrub state never re-runs it), and plots key points by stable recording UUIDs. **Every `AreaMark` names its `yStart`** — the implicit baseline is 0 in *data* space, and the Score plot's domain starts at `min - 10`, so the gradient used to run below the plot and out of the card. Swift Charts does not clip marks to the plot area. See [`../AGENT_GOTCHAS.md`](../AGENT_GOTCHAS.md) §21. Comparison, replay, and Story Detail render value snapshots decoded once at load. Listen back (`ProgressReplayViewModel`) reads a count and the first and last analyzed takes on the transcript proxy, never every analysis. Journal export's score chart loads in a detached pass (`loadScorePoints`), but the PDF itself (`JournalExportService.generatePDF`) still renders on the main actor from the view's `@Query`, decoding each take's analysis several times - known debt, not a pattern to copy.
9. The empty Recordings CTA routes to Today, so its label is **Choose today's prompt**, not **Start speaking**. Never name a navigation action as though the microphone starts immediately.

## Cross-links

[monetization.md](./monetization.md) · [recording-detail.md](./recording-detail.md) · [analytics-review.md](./analytics-review.md) · [speech-pipeline.md](./speech-pipeline.md) · `/docs/AGENT_GOTCHAS.md`
