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
| Tests | `SpeakUpTests/LexiconInsightsTests.swift`, `SpeakUpTests/ScenarioReadinessTests.swift`, `SpeakUpTests/HistoryWeekTests.swift` |

## Recordings list shape

Grouped by calendar week (`HistoryWeek.group`, in `HistoryView.swift`), newest first, after search and filter apply. Each week is a `GlassSectionHeader` ("This week", "Last week", then "Sep 7 – 13", with the year once it is not this one) whose accessory is `N takes · avg S` - the average skips unscored takes and drops out when none scored. The week's takes are rows inside **one** `GlassRowGroup` (hairline-separated, the same plate Settings groups its rows on; a row presses with `RowPressStyle`, which lights it edge to edge - `.plain` gave no sign a tap landed), not a card per take: a flat stack of cards repeated the full date on every row and spent most of the screen on chrome. `RecordingRow` is content only (no card of its own) and prints weekday + time, since the header already carries the week.

Above the weeks, `ActivityStrip` ("Practice activity") is ~17 weeks as a dot grid with a Sessions / Score switch. **Tap a day and the footer reads it** (`Wed, Sep 23 · 2 sessions · avg 78`, outlined cell, selection haptic); tap it again for the total. A tap, not a drag: the grid is tall enough that a drag would catch the scroll.

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
   "Trends" whose accessory is the window's session count + the time-range
   menu): chart tabs (`ChartTab`: Score / Pace / Fillers / Language / Skills /
   Activity) and the selected chart. The range menu lives in the header, not
   beside the tabs - next to six tabs it overflowed a phone and dropped the
   row onto a scrolling rail. It is a `Picker` inside a `Menu` (native
   checkmark, VoiceOver value), a 44pt target around a smaller capsule, and it
   stays in the layout (hidden) for Skills / Language, which ignore the
   window. All trend plots share `TrendChart.plotHeight` (210) so tab switches
   don't reflow; card headers use `GlassCardTitle`. The tab picker is
   icon-free text segments in a `ViewThatFits`: equal-width single row when
   six labels fit, scrolling rail at accessibility sizes. Skills renders
   `SkillBreakdownCard` (the same `SubscoreRadarChart` sunburst as the
   session detail hero).
   - **Thin windows.** Skills and Language never pass through the window's
     empty check (Skills used to say "try widening the time range" with the
     menu hidden). Score / Pace need two takes in the window, Fillers /
     Activity two weeks; short of that the tab shows one card saying so with
     a **Show all time** button. The page opens on 30 days, widened to 90 or
     all time the first time the window holds fewer than two takes
     (`TimeRange.opening(for:)`), so a returning user never opens on an
     empty plot.
   - **Pinned points.** `chartDateScrub` pins the nearest point when the
     finger lifts; a tap on the pinned point clears it, and a change in the
     plotted collection resets it. On Score and Pace the readout is a row
     with a chevron that opens the take (`onSelectRecording`); nil (Today's
     push) keeps it read-only. Drops in readouts are amber, never red.
   - **Activity** zero-fills weeks from the first practiced one, so "% goal
     hit" counts missed weeks; the current week counts only once it meets
     the goal.
3. **Guidance — which situation needs work?** The scenario family (below)
   collapsed into ONE ranked card under `GlassSectionHeader("Where to
   improve")`.

**State lives in `ProgressChartsModel`**, owned by whoever shows the page
(`HistoryView`, or `ProgressChartsView` for Today's push) and passed to
`ProgressChartsContent`: points, lexicon, readiness, and the picked tab and
window. History's section picker tears the Progress section down; with the
state inside it every flip reset the tab and window, flashed the loader and
decoded every analysis again. The spinner shows only before the first pass;
later passes refresh behind the charts, and only when the takes changed:
History passes `HistoryViewModel.progressFingerprint` as `reloadKey` (count,
scored count, newest take), and a pass for the key already loaded is skipped.
Pull-to-refresh on Progress and Today's push (no key) always reload. < 2 analyzed sessions → one `EmptyStateCard`
("Your progress starts here" / "One take in") with **Choose today's prompt**
(`onShowToday`, the same route and words as the empty Recordings list; hidden
on Today's push). No scattered empty states firing at once. The pushed page's
title is **Progress**, the name History's picker gives the same content (it
was "Progress Charts"), and it calls `.restoresNavigationBar()` itself. The
zero-point copy counts **scored** takes ("After two scored takes…"); it used
to say "Record your first session" to someone whose only take had not scored.

The tail after `ProgressChartsContent`: **Review** only — `ProgressReviewSection`,
a 2×2 grid of `ToolTileLabel` tiles (compare, listen back, goals, journal;
compare/listen hidden until two **scored** takes exist -
`HistoryViewModel.scoredTakeCount`; counting every take opened them onto a
zero score or an empty sheet). History passes the root's callbacks; Today's
push (`ProgressChartsView`) presents the same sheets itself, so both entry
points end on the same tools. These stay on Progress because they need
history data; Library → Tools is prep (warm-up / drill / read aloud / calm).
Do not merge the catalogs. Word Bank usage moved inside the Language
tab (`ProgressChartsContent.vocabWords` → `LanguageInsightsView`), so the
page ends at Review instead of an orphaned chip rail.

**Compare** lists scored takes only and defaults to the oldest vs newest of
them (a processing or failed newest used to read "Latest 0, −72 points"); a
tie is "unchanged", not a red regression; the whole From / To card opens the
take menu; breakdown rows are one `GlassRowGroup`. **Listen back** (title
matches its tile) drives play / pause from `AudioService.isPlaying` plus the
side that owns the player - `AudioService.play` returns once playback starts,
so a flag reset after awaiting it left no way to pause. **Journal** keeps
Export PDF as the sheet's primary CTA in a `.safeAreaBar`.

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
- **UI:** one ranked `GlassRowGroup` — `IconChip` + title + momentum glyph +
  score, `TickMeter`, meta line, optional habit-cost line; unpracticed cores
  show “Not yet”. Rows become buttons (`RowPressStyle`, chevron) when
  `onPracticeScenario` is passed (`HistoryView` → `ProgressChartsContent` →
  `ScenarioReadinessSection.onPractice`); nil keeps them read-only. The root
  picks a prompt whose category maps to the scenario
  (`ScenarioReadinessEngine.scenario(forRawCategory:)`).
- **Thin data:** < 4 sessions → “early read”, score capped. Momentum colors
  via `ScenarioMomentum` only (slipping = amber, never error-red).

## Language tab (language profile)

`ChartTab.words` is the one Progress home for lexicon + Word Bank usage.

- Crutch swaps are **sentences**, never chips. One `WordCountChip` family.
- Rate deltas print the rate's own sign and arrow; only the colour knows
  which way is good (`higherIsBetter`). Weak language used to pass a negated
  delta, so a rise read "↘ −1.0". Regressions are amber, never red.
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
8. Chart math is memoized per points-change (`PlotModel` built in each chart's `init(points:)`, and the weekly buckets of `FillerTrendChart` / `SessionFrequencyChart` likewise; scrub state never re-runs it), and plots key points by stable recording UUIDs. **Every `AreaMark` names its `yStart`** — the implicit baseline is 0 in *data* space, and the Score plot's domain starts at `min - 10`, so the gradient used to run below the plot and out of the card. Swift Charts does not clip marks to the plot area. See [`../AGENT_GOTCHAS.md`](../AGENT_GOTCHAS.md) §21. Comparison, replay, and Story Detail render value snapshots decoded once at load. Listen back (`ProgressReplayViewModel`) reads a count and the first and last analyzed takes on the transcript proxy, never every analysis. **Journal export never touches a model object on the main actor.** The sheet's session count, minutes and scores come from `JournalTakePoint`s loaded in a detached pass on appear (no `@Query` over recordings). **Export PDF** runs fetch, snapshot, layout and the temp-file write in one `Task.detached`: a `#Predicate` on `date` only, one `analysis` decode per take into a `Sendable` `JournalEntry` (the PDF prints headline numbers, so no `fullAnalysis`), then the `nonisolated` `JournalExportService` renders from those entries. Only the file URL hops back, to `SharePresenter`. `SpeakUpTests/JournalExportTests.swift` renders from a detached task.
9. The empty Recordings CTA routes to Today, so its label is **Choose today's prompt**, not **Start speaking**. Never name a navigation action as though the microphone starts immediately.

## Cross-links

[monetization.md](./monetization.md) · [recording-detail.md](./recording-detail.md) · [analytics-review.md](./analytics-review.md) · [speech-pipeline.md](./speech-pipeline.md) · `/docs/AGENT_GOTCHAS.md`
