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
| Components | `SpeakUp/Views/Components/` — `GlassCard`, `GlassButton`, `MetricTile`, `RingStatsView`, `FlowLayout`, `RichTextEditor`, `AppTourView`, … |

## Hard rules

1. Every screen: `.appBackground(...)`. Sheets / detail: prefer `.subtle`. Recording session: `.recording`.
2. Cards: `.glassCard` / `GlassCard` — `ultraThinMaterial` + `surfaceLift` + `cardStroke`. No opaque fills.
3. Colors only from `AppColors`. Score ramp (`scoreColor(for:)`) ≠ semantic success/warning.
4. Buttons: `GlassButton` / `GlassIconButton` (styles: primary / secondary / outline / ghost / danger).
5. Motion: `AppMotion` or `.spring(response: 0.3)` / `.easeInOut(duration: 0.2)`. Respect Reduce Motion.
6. Haptics via `Haptics.*` typed helpers.
7. Tab bar: `.tint(.white)`, `.preferredColorScheme(.dark)`.

## New view checklist

1. `ScrollView` + `.appBackground`
2. `GlassCard` content blocks
3. `AppColors` only
4. `GlassButton` for actions
5. `GlassSectionHeader` for sections
6. Haptics on interaction
7. `// MARK:` when file grows past ~60 lines

## Cross-links

All feature view docs. Prefer existing `Components/` before inventing new chrome.
