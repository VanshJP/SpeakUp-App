# UI design system

## Purpose

Navy glass UI: deep canvas + translucent surfaces + one loud primary CTA. All new UI must use this system.

## Key files

| Role | Path |
|------|------|
| Background | `SpeakUp/Theme/AppBackground.swift` — `.appBackground(.primary\|.recording\|.subtle)` |
| Colors | `SpeakUp/Theme/AppColors.swift` |
| Glass | `SpeakUp/Theme/GlassStyles.swift` — cards, buttons, modifiers |
| Type / motion | `AppType.swift`, `AppMotion.swift` |
| Page rhythm | `AppLayout.swift` — `pageHorizontal` (16), `chapterSpacing` (20), `listSpacing` (16), `minHitTarget` (44), `.pageContentInsets()` |
| Glass helpers | `SpeakUp/Extensions/View+Glass.swift`, `Haptics.swift` |
| Components | `SpeakUp/Views/Components/` — `GlassCard`, `GlassButton`, `GlassButtonLabel`, `MetricTile`, `RingStatsView`, `FlowLayout`, `RichTextEditor`, `AppTourView`, `ToolTile`, … |
| Header roles | Section = `GlassSectionHeader` (headline, page chapters). Card = `GlassCardTitle` (subheadline, chart/insight cards). Both take a trailing accessory closure. |

## Hard rules

1. Every screen: `.appBackground(...)`. Sheets / detail: prefer `.subtle`. Recording session: `RecordingBackdropView` — the user-picked canvas, shared by the prepare countdown, `RecordingView` and `DrillSessionView`, where Base is `AppBackground(style: .recording)`. Screens that don't capture a take (Read-Aloud, warm-ups, confidence) stay on `AppBackground(style: .recording)` directly.
2. Cards: `.glassCard` / `GlassCard` — iOS 26 `.glassEffect(.regular…)` (optional `.tint`) in a continuous rounded rect, then a quiet shadow. No opaque fills. Primary CTAs stay solid white (`GlassButton` `.primary`); secondary uses `.glassEffect(.regular.interactive(), in: .capsule)`.
3. Colors only from `AppColors`. Score ramp (`scoreColor(for:)`) ≠ semantic success/warning.
4. Buttons: `GlassButton` / `GlassButtonLabel` (styles: primary / secondary / outline / danger). `GlassButtonLabel` is the chrome alone — use it inside a `NavigationLink` label where nesting `Button` is illegal. Do not hand-roll white/`Color.white.opacity(0.94)` capsules for CTAs (primary style owns that fill).
5. Motion: `AppMotion` or `.spring(response: 0.3)` / `.easeInOut(duration: 0.2)`. Respect Reduce Motion. Press feedback is `GlassPressStyle` at scale `0.96` (no scale under Reduce Motion).
6. Haptics via `Haptics.*` typed helpers.
7. Tab bar: `.tint(.white)`, `.preferredColorScheme(.dark)`.
8. Full-screen pages scroll with **`PageScrollView`**, not `ScrollView`. A plain vertical `ScrollView` pans sideways as soon as any child measures wider than the viewport; `PageScrollView` clamps content to the container width so overflow clips instead. Deliberate horizontal rails stay `ScrollView(.horizontal)`.
9. **One page inset.** Root tabs use `.pageContentInsets()` (`AppLayout.pageHorizontal` = 16 + bottom 16). Do not hand-roll `.padding(.horizontal, 20)` on a tab — Learn used to, and the stack looked uneven. Chapter stacks use `AppLayout.chapterSpacing` (20); list hubs use `AppLayout.listSpacing` (16). Library / History / Learn / Settings use `.navigationBarTitleDisplayMode(.large)`; Today keeps a custom greeting with `.inline` empty title.
10. Nothing in a page may demand more width than the screen. `.fixedSize()` on a row, a wide fixed `.frame(width:)`, or a pinned pill row are the usual causes — check at 375pt *and* at accessibility text sizes, and reach for `ViewThatFits` before pinning (see `ActivityStrip.header`).
11. Controls keep a `AppLayout.minHitTarget` (44pt) hit target even when their visible icon/chip is smaller. Selected controls expose `.isSelected`; modal overlays expose `.isModal` + Escape; Reduce Motion suppresses ambient/celebration motion.
12. **Tint is for identity, not emphasis.** A colored `glassEffect` tint stays at **0.06** (a whole card or tile) or
    **0.10** (a featured/recommended row); anything above that turns a graphite page into a highlighter. Identity color
    belongs to the *glyph* — an icon at full tint inside a `Circle().fill(tint.opacity(0.18))` chip. `ToolTileLabel`
    (Today prep tools, History review grid) and `PracticeHubView.toolCategoryCard` (Library tools) are the same four
    tools, so they wear the same recipe — change one, change both. `StreakChip` is neutral glass with an amber flame:
    the streak is one number and does not need a billboard. Selected filter chips are the solid white pill
    (`FilterChip` / `FilterPill` / `SectionPicker`) on every tab; a chip's own color, if it has one, shows on the idle glyph.
13. **Liquid Glass surfaces (shared):** `GlassCard`, `SectionPicker` frame, `ToolTileLabel`, `FilterPill`, `StreakChip`, secondary `GlassButton`, `SourceStoryBanner`, duration/time-range capsules, icon chip buttons. Apply `.glassEffect` *after* padding/frame. Use `.interactive()` only on tappable chrome. Do not glass the white primary CTA. Selected section pills stay solid white (same as `SectionPicker`).
14. **Empty / CTA copy:** sentence case (`"No recordings yet"`, `"Start recording"`). Verb-first buttons. Errors say how to recover.
15. **Numerals:** `Font.displayNumeral` / `.metricValue` / `.statValue` carry tabular figures — use them (or `.monospacedDigit()`) on any value that updates.

## New view checklist

1. `PageScrollView` + `.appBackground` + `.pageContentInsets()` (root tabs)
2. `GlassCard` content blocks
3. `AppColors` only
4. `GlassButton` for actions
5. `GlassSectionHeader` for sections
6. Haptics on interaction
7. `// MARK:` when file grows past ~60 lines
8. Match neighbor tab title mode (`.large` unless Today-style custom header)

## Cross-links

All feature view docs. Prefer existing `Components/` before inventing new chrome.
