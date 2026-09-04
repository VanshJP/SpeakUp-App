# UI design system

## Purpose

Navy glass UI: deep canvas + translucent surfaces + one loud primary CTA. All new UI must use this system.

## Key files

| Role | Path |
|------|------|
| Background | `SpeakUp/Theme/AppBackground.swift` — `.appBackground(.primary\|.recording\|.subtle)`; reads `@Environment(\.appCanvas)` |
| Canvas | `SpeakUp/Theme/AppCanvas.swift` — `AppCanvas` + `AppCanvasView` (Classic / Midnight / Mist / Aurora / Ember / Horizon / Prism / Depth) |
| Appearance | `SpeakUp/Theme/AppearanceEnvironment.swift` — `GlassAppearance` (Light / Dark) + environment keys |
| Colors | `SpeakUp/Theme/AppColors.swift` |
| Glass | `SpeakUp/Theme/GlassStyles.swift` — cards, buttons, modifiers |
| Type / motion | `AppType.swift`, `AppMotion.swift` |
| Page rhythm | `AppLayout.swift` — `pageHorizontal` (16), `chapterSpacing` (20), `listSpacing` (16), `minHitTarget` (44), `.pageContentInsets()` |
| Glass helpers | `SpeakUp/Extensions/View+Glass.swift`, `Haptics.swift` |
| Components | `SpeakUp/Views/Components/` — `GlassCard`, `GlassButton`, `GlassButtonLabel`, `MetricTile`, `RingStatsView`, `FlowLayout`, `RichTextEditor`, `AppTourView`, `ToolTile`, … |
| Header roles | Section = `GlassSectionHeader` (headline, page chapters). Card = `GlassCardTitle` (subheadline, chart/insight cards). Both take a trailing accessory closure. |

## Hard rules

1. Every screen: `.appBackground(...)`. Sheets / detail: prefer `.subtle`. Recording session: `RecordingBackdropView` — the user-picked session canvas, shared by the prepare countdown, `RecordingView` and `DrillSessionView`. `RecordingBackdrop.base` is always classic recording navy (`AppCanvasView(canvas: .classic, style: .recording)`), never the app-wide `appCanvas`. Screens that don't capture a take (Read-Aloud, warm-ups, confidence) stay on `AppBackground(style: .recording)` directly (which *does* follow the app canvas).
2. Cards: `.glassCard` / `GlassCard` — iOS 26 `.glassEffect(.regular…)` (optional `.tint`) in a continuous rounded rect, then a quiet shadow. No opaque fills. Primary CTAs stay solid white (`GlassButton` `.primary`); secondary uses `.glassEffect(.regular.interactive(), in: .capsule)`.
3. Colors only from `AppColors`. Score ramp (`scoreColor(for:)`) ≠ semantic success/warning.
4. Buttons: `GlassButton` / `GlassButtonLabel` (styles: primary / secondary / outline / danger). `GlassButtonLabel` is the chrome alone — use it inside a `NavigationLink` label where nesting `Button` is illegal. Do not hand-roll white/`Color.white.opacity(0.94)` capsules for CTAs (primary style owns that fill).
5. Motion: `AppMotion` or `.spring(response: 0.3)` / `.easeInOut(duration: 0.2)`. Respect Reduce Motion. Press feedback is `GlassPressStyle` at scale `0.96` (no scale under Reduce Motion).
6. Haptics via `Haptics.*` typed helpers.
7. Tab bar: `.tint(.white)`, `.preferredColorScheme(.dark)`.
8. Full-screen pages scroll with **`PageScrollView`**, not `ScrollView`. A plain vertical `ScrollView` pans sideways as soon as any child measures wider than the viewport; `PageScrollView` clamps content to the container width so overflow clips instead. Deliberate horizontal rails stay `ScrollView(.horizontal)`.
9. **One page inset.** Root tabs use `.pageContentInsets()` (`AppLayout.pageHorizontal` = 16 + bottom 16). Do not hand-roll `.padding(.horizontal, 20)` on a tab — Learn used to, and the stack looked uneven. Chapter stacks use `AppLayout.chapterSpacing` (20); list hubs use `AppLayout.listSpacing` (16). **Root tabs carry no nav title** (`.navigationTitle("")` + `.inline`) — the tab bar already names the destination, and a large title left trailing chrome alone on an empty nav row with the name dropped underneath. Today’s greeting, Library/History’s `SectionPicker`, Learn’s continue card, and Settings’ inline name field are the first voice on each page. Nested pushes (lesson detail, a setting, a story) still take a real title.
10. Nothing in a page may demand more width than the screen. `.fixedSize()` on a row, a wide fixed `.frame(width:)`, or a pinned pill row are the usual causes — check at 375pt *and* at accessibility text sizes, and reach for `ViewThatFits` before pinning (see `ActivityStrip.header`).
11. Controls keep a `AppLayout.minHitTarget` (44pt) hit target even when their visible icon/chip is smaller. Selected controls expose `.isSelected`; modal overlays expose `.isModal` + Escape; Reduce Motion suppresses ambient/celebration motion.
12. **Tint is for identity, not emphasis.** A colored `glassEffect` tint stays at **0.06** (a whole card or tile) or
    **0.10** (a featured/recommended row); anything above that turns a graphite page into a highlighter. Identity color
    belongs to the *glyph* — an icon at full tint inside a `Circle().fill(tint.opacity(0.18))` chip. `ToolTileLabel`
    (Today prep tools, History review grid) and `ToolCategoryCard` (Library tools) wear the same recipe — change one, change both. `StreakChip` is neutral glass with an amber flame:
    the streak is one number and does not need a billboard. Selected filter chips are the solid white pill
    (`FilterChip` / `FilterPill` / `SectionPicker`) on every tab; a chip's own color, if it has one, shows on the idle glyph.
13. **Liquid Glass surfaces (shared):** `GlassCard`, `SectionPicker` frame, `ToolTileLabel`, `FilterPill`, `StreakChip`, secondary `GlassButton`, `SourceStoryBanner`, duration/time-range capsules, icon chip buttons. Apply `.glassEffect` *after* padding/frame. Use `.interactive()` only on tappable chrome. Do not glass the white primary CTA. Selected section pills stay solid white (same as `SectionPicker`). Untinted surfaces take `@Environment(\.glassAppearance).glassTint` (Light = soft white lift 0.08; Dark = quieter 0.02) so Settings → Appearance can deepen the glass. Cards paint a top-edge rim light via `.glassRimStroke` so the specular does not die when the card scrolls off the background orbs. `ContentView` injects both `glassAppearance` and `appCanvas` from `UserSettings`.
14. **Never animate a glassEffect on/off.** Selection that swaps glass ↔ solid fill under `withAnimation` mid-fades into a dark clipped rectangle for a beat — `SelectedFilterChrome` hard-cuts with `.transaction { $0.animation = nil }`, and filter chips use `.buttonStyle(.plain)` (no press-scale on live glass). Hit targets expand *around* the capsule, never under the glass.
15. **Empty / CTA copy:** sentence case (`"No recordings yet"`, `"Start recording"`). Verb-first buttons. Errors say how to recover.
16. **Numerals:** `Font.displayNumeral` / `.metricValue` / `.statValue` carry tabular figures — use them (or `.monospacedDigit()`) on any value that updates.
17. **App canvas budget.** Animated `AppCanvas` styles run at **8 fps** and pause when `scenePhase != .active` or Reduce Motion is on; recording backdrops at **15 fps** with the same pause. Thumbnails freeze with `animated: false`. `ContentView` owns one shared `AppBackground` behind the `TabView` — root tabs do not each paint their own. Animated canvases use `.drawingGroup(opaque: true)` so Liquid Glass samples a flattened layer. App Aurora is orbs, not MeshGradient (recording Aurora still may use MeshGradient). Do not put Hyperspace-density particle fields behind every tab.

## New view checklist

1. `PageScrollView` + `.appBackground` + `.pageContentInsets()` (root tabs)
2. `GlassCard` content blocks
3. `AppColors` only
4. `GlassButton` for actions
5. `GlassSectionHeader` for sections
6. Haptics on interaction
7. `// MARK:` when file grows past ~60 lines
8. Root tabs: empty `.inline` nav title (tab bar names the place). Nested pushes: real title + `.inline` unless a sheet owns its own chrome.

## Cross-links

All feature view docs. Prefer existing `Components/` before inventing new chrome.
