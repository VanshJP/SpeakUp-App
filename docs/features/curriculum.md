# Curriculum - Learn tab

## Purpose

Guided **skill studio**: capability chapters and interactive lessons that end in speaking proof (not a decorative path). Distinct from Library → Tools: Learn is a curriculum of skills you demonstrate with your voice; warm-ups/drills/calm are quick prep reps.

## Value thesis

The page answers *what speaking skill am I building, and how do I prove it?* - not *where am I on a zig-zag map?* Path rails optimize sequence theater; speaking gains come from one clear objective, a short interactive plan (learn → drill/warm-up → record/review), and feedback against that skill. Frames of reference: Brilliant / MasterClass lesson lists (content + description, not nodes), Orai Journey (outcome weeks + timed speak), Toastmasters projects (prove the objective). Duolingo-style paths are a deliberate non-goal here.

## Key files

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Curriculum/` - `CurriculumView`, `LessonDetailView`, `LessonContentView`, `LessonCompletionView`, `LessonPath` (`LessonNodeState` only), `LessonGlyphView`, `LessonTeachingChrome`, `PracticeResultsCard` |
| Glyphs | `LessonIdentity` + `LessonMotif` (`Models/LessonIdentity.swift`) → `LessonGlyphView` (Canvas art per lesson) |
| VM | `SpeakUp/ViewModels/CurriculumViewModel.swift` |
| Services | `CurriculumService`, `CurriculumActivitySignalStore` |
| Models | `CurriculumModels.swift` (`studioPlan`, `practiceSeconds`), `CurriculumProgress.swift`, `LessonContent.swift`, `LessonIdentity.swift` |
| Seed | `SpeakUp/Data/DefaultCurriculum.swift` |
| Tests | `SpeakUpTests/LessonIdentityTests.swift`, `CurriculumStudioPlanTests.swift` |

## Invariants

1. All eight weeks are open during the beta - the `PaidFeature.fullCurriculum` lock is removed from the UI ([monetization.md](./monetization.md)). Weeks still unlock in order.
2. Advancement uses durable activity signals in `CurriculumActivitySignalStore` - preserve signal semantics when changing lesson completion UX. Review/practice signals come from `CurriculumSessionSignals.scan(recordings)`: one decode pass over history feeding every activity. Per-activity blob reads were O(activities × recordings) on the main actor; do not reintroduce them.
3. Seed content stays in `Data/DefaultCurriculum.swift`. New lesson → add a row in `LessonIdentity.catalog` (motif + accent) in the same PR.
4. `CurriculumView` is a **skill studio**, not a path map:
 - Header: eyebrow **LEARN** + **Skill studio** + trophy (chrome, not a stats card).
 - **Studio session** card: current lesson framed by objective + `LessonTeachingCopy.roadmap` + `LessonModalityStrip` + primary Start / Practice again. Progress count is a quiet accessory. Not `elevated` (same shadow reason as `CoachFocusCard`).
 - **Prove it again** nudges the prior completed lesson into the first viewport (review is not buried in the chapter list).
 - Chapters use a left-aligned **lesson list** (glyph + title + objective + modality strip + Spoken/Now/Open/Locked). No zig-zag rails, no alternating left/right nodes.
 - Warm-ups/drills/calm stay under Library → Tools.
5. Lesson practice feedback uses `CoachingTipService` (same voice as Recording Detail) - no parallel praise strings. `PracticeResultsCard` resolves `recording.analysis` + the tip once into `@State` (blob re-decodes on every access). Pace UI and curriculum copy follow `resolvedTargetWPM`, not a fixed 130-170 band.
6. Curriculum practice with a `frameworkHint` opens `RecordingView` with that framework pre-selected and persists `frameworkUsed` so PREP/STAR completion signals are real, not “any analyzed take.”
7. **No navigation bar** (`.toolbar(.hidden, for: .navigationBar)`, like every root tab): Achievements trophy is `awardsRow`, which is also where the page says its own name - without it the tab opened on a lone icon over empty space. The trophy wears `.headerIconChrome()`, the same 44pt plate as the filter buttons on Prompts / Stories / History. Pushed `LessonDetailView` adds `.restoresNavigationBar()`. Details: [ui-design-system.md](./ui-design-system.md) rule 9.
8. **Next lesson stays in the detail stack.** `LessonDetailView` holds `@State lesson` and on "Next Lesson" swaps it in place (`advanceToNextLessonInPlace`) instead of `dismiss()`-ing back to the chapter list.
9. **Studio rows use lesson glyphs**, not a shared book SF Symbol. Completed rows caption status **Spoken**; revisiting a completed lesson shows **Done reviewing** in detail (does not re-fire the completion celebration). Review activities list recent recordings and a listen lens from the lesson objective - not a lone “Mark as Done” button.
   A recording opened from a review activity supplies `RecordingDetailSource.learn` and a real repeat route that preserves the recording's target duration and framework; result coaching must not dead-end inside a lesson.
10. Glyph accents come from `AppColors` category tones; chapter headers tint with `LessonIdentity.forPhase(week:)`. Keep glass tint ≤ 0.10 on cards ([ui-design-system.md](./ui-design-system.md) rule 12). A chapter header is **two lines** - dot + `CHAPTER N` + state icon + count, then the title - not one row of six things.
11. **Lesson detail is teacher-led, and says each thing once.** `LessonBoardHeader` states today's focus + roadmap on step 1 and collapses to a name plate (`isCompact`) from step 2 on - past the first card the activity is the subject, and reprinting the objective and roadmap above every step pushed the teaching below the fold. **There is no step strip.** `LessonPlanStrip` - a row of rounded Learn/Practice tiles with "1 Learn / 2 Practice" labels under them - is deleted: it was the fourth drawing of facts the title, the activity eyebrow and the bottom track already carried, and its glowing tiles were the one piece of chrome in the lesson that looked like no other screen. Going back to a step already reached is the navigation title's `toolbarTitleMenu` (`stepMenu`: done steps take a check, unreached ones are disabled - lessons are taught in order). **There is exactly one progress track on the screen** - `LessonProgressTrack` in the sticky bottom bar - and exactly one step counter, the inline navigation title `Role · n of total`. The bar carries no "n of m done" line. `LessonCoachCue` is one quiet sparkles line, not a card.
    **Activity descriptions belong to the header.** `activityHeader` prints role (`eyebrowStyle` in the role colour, beside an `IconChip`), title and description with a trailing Done pill; a launch card under it carries controls only (exercise identity, duration/framework labels, the CTA) and never reprints `activity.description` or `lesson.objective`. Bottom bar uses `safeAreaInset` so content clears the sticky CTA. CTAs use pedagogical verbs (`Got it`, `Next · Practice`, `Finish lesson`). Completion restates the objective as "You can now…" plus the worked stages - not a trophy checklist alone.
12. **Lesson glyphs stay readable when complete.** `LessonGlyphView` never draws a check badge on the Canvas motif. Completed state uses success ink plus a plate-corner badge on the parent (`lessonGlyphPlate` / reinforce nudge).
13. `CurriculumLesson.studioPlan` is ordered unique `CurriculumActivityType`s; list/meta UI should prefer it over inventing a second role taxonomy.

## Cross-links

[monetization.md](./monetization.md) · [recording.md](./recording.md) · [recording-detail.md](./recording-detail.md) · [today-library.md](./today-library.md) · [practice-tools.md](./practice-tools.md) · [ui-design-system.md](./ui-design-system.md)
