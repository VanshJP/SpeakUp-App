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
| Glass helpers | `SpeakUp/Extensions/View+Glass.swift`, `Haptics.swift` |
| Components | `SpeakUp/Views/Components/` — `GlassCard`, `GlassButton`, `MetricTile`, `RingStatsView`, `FlowLayout`, `RichTextEditor`, `AppTourView`, `ToolTile`, … |
| Header roles | Section = `GlassSectionHeader` (headline, page chapters). Card = `GlassCardTitle` (subheadline, chart/insight cards). Both take a trailing accessory closure. |

## Hard rules

1. Every screen: `.appBackground(...)`. Sheets / detail: prefer `.subtle`. Recording session: `RecordingBackdropView` — the user-picked canvas, shared by the prepare countdown, `RecordingView` and `DrillSessionView`, where Base is `AppBackground(style: .recording)`. Screens that don't capture a take (Read-Aloud, warm-ups, confidence) stay on `AppBackground(style: .recording)` directly.
2. Cards: `.glassCard` / `GlassCard` — `ultraThinMaterial` + `surfaceLift` + `cardStroke`. No opaque fills.
3. Colors only from `AppColors`. Score ramp (`scoreColor(for:)`) ≠ semantic success/warning.
4. Buttons: `GlassButton` / `GlassIconButton` (styles: primary / secondary / outline / ghost / danger).
5. Motion: `AppMotion` or `.spring(response: 0.3)` / `.easeInOut(duration: 0.2)`. Respect Reduce Motion.
6. Haptics via `Haptics.*` typed helpers.
7. Tab bar: `.tint(.white)`, `.preferredColorScheme(.dark)`.
8. Full-screen pages scroll with **`PageScrollView`**, not `ScrollView`. A plain vertical `ScrollView` pans sideways as soon as any child measures wider than the viewport; `PageScrollView` clamps content to the container width so overflow clips instead. Deliberate horizontal rails stay `ScrollView(.horizontal)`.
9. Nothing in a page may demand more width than the screen. `.fixedSize()` on a row, a wide fixed `.frame(width:)`, or a pinned pill row are the usual causes — check at 375pt *and* at accessibility text sizes, and reach for `ViewThatFits` before pinning (see `ActivityStrip.header`).

## New view checklist

1. `PageScrollView` + `.appBackground`
2. `GlassCard` content blocks
3. `AppColors` only
4. `GlassButton` for actions
5. `GlassSectionHeader` for sections
6. Haptics on interaction
7. `// MARK:` when file grows past ~60 lines

## Cross-links

All feature view docs. Prefer existing `Components/` before inventing new chrome.
