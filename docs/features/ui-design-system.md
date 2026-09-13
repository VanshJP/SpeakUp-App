# UI design system

## Purpose

Navy glass UI: deep canvas + translucent surfaces + one loud primary CTA. All new UI must use this system.

## Key files

| Role | Path |
|------|------|
| Background | `SpeakUp/Theme/AppBackground.swift` — `.appBackground(.primary\|.recording\|.subtle)`; reads `@Environment(\.appCanvas)` |
| Canvas art | `SpeakUp/Theme/CanvasLook.swift` — `CanvasLook` (the one catalogue: Classic / Midnight / Mist / Aurora / Ember / Horizon / Prism / Depth / Hyperspace / Nebula / Void / Tide / Dusk / Signal / Noir) + `CanvasMood` + every painter and primitive |
| Canvas menus | `SpeakUp/Theme/AppCanvas.swift` — `AppCanvas` (App Look) + `AppCanvasView` + `CanvasLookView`; `SpeakUp/Views/Recording/RecordingBackdrop.swift` — `RecordingBackdrop` (Recording Look). Both are thin persisted lists over `CanvasLook.look`; neither owns art |
| Appearance | `SpeakUp/Theme/AppearanceEnvironment.swift` — `GlassAppearance` (Light / Dark) + environment keys, including `\.isOnGlass` (rule 13b) |
| Colors | `SpeakUp/Theme/AppColors.swift` |
| Glass | `SpeakUp/Theme/GlassStyles.swift` — cards, buttons, modifiers |
| Type / motion | `AppType.swift`, `AppMotion.swift` |
| Page rhythm | `AppLayout.swift` — `pageHorizontal` (16), `chapterSpacing` (20), `listSpacing` (16), `minHitTarget` (44), `.pageContentInsets()` |
| Glass helpers | `SpeakUp/Extensions/View+Glass.swift`, `Haptics.swift` |
| Components | `SpeakUp/Views/Components/` — `GlassCard`, `GlassButton`, `GlassButtonLabel`, `MetricTile`, `RingStatsView`, `FlowLayout`, `RichTextEditor`, `AppTourView`, `ToolTile`, … |
| Page chrome | `SpeakUp/Views/Components/PageHeaderBar.swift` — `InlineSearchField`, `PinnedPageHeader`, `.headerIconChrome()`, `.restoresNavigationBar()`. The header a root tab uses instead of a navigation bar (rule 9) |
| Header roles | Section = `GlassSectionHeader` (headline, page chapters). Card = `GlassCardTitle` (subheadline, chart/insight cards). Both take a trailing accessory closure. |

## Hard rules

1. Every screen: `.appBackground(...)`. Sheets / detail: prefer `.subtle`. Recording session: `RecordingBackdropView` — the user-picked session canvas, shared by the prepare countdown, `RecordingView` and `DrillSessionView`. `RecordingBackdrop.base` is always Classic at recording tone (`RecordingBackdrop.base.look == .classic`), never the app-wide `appCanvas`. Screens that don't capture a take (Read-Aloud, warm-ups, confidence) stay on `AppBackground(style: .recording)` directly (which *does* follow the app canvas).
2. Cards: `.glassCard` / `GlassCard` — iOS 26 `.glassEffect(.regular…)` (optional `.tint`) in a continuous rounded rect, then a quiet shadow. No opaque fills. Primary CTAs stay solid white (`GlassButton` `.primary`); secondary uses `.glassEffect(.regular.interactive(), in: .capsule)`.
3. Colors only from `AppColors`. Score ramp (`scoreColor(for:)`) ≠ semantic success/warning.
4. Buttons: `GlassButton` / `GlassButtonLabel` (styles: primary / secondary / outline / danger). `GlassButtonLabel` is the chrome alone — use it inside a `NavigationLink` label where nesting `Button` is illegal. Do not hand-roll white/`Color.white.opacity(0.94)` capsules for CTAs (primary style owns that fill), and do not hand-roll tinted `RoundedRectangle` buttons either — Read-Aloud's Hear / Define pair used to, and they were the only actions in the app with their own radius and no press feedback.
5. Motion: `AppMotion` or `.spring(response: 0.3)` / `.easeInOut(duration: 0.2)`. Respect Reduce Motion. Press feedback is `GlassPressStyle` at scale `0.96` (no scale under Reduce Motion).
6. Haptics via `Haptics.*` typed helpers.
7. Tab bar: `.tint(.white)`, `.preferredColorScheme(.dark)`.
8. Full-screen pages scroll with **`PageScrollView`**, not `ScrollView`. A plain vertical `ScrollView` pans sideways as soon as any child measures wider than the viewport; `PageScrollView` clamps content to the container width so overflow clips instead. Deliberate horizontal rails stay `ScrollView(.horizontal)`.
9. **One page inset.** Root tabs use `.pageContentInsets()` (`AppLayout.pageHorizontal` = 16 + bottom 16). Do not hand-roll `.padding(.horizontal, 20)` on a tab — Learn used to, and the stack looked uneven. Chapter stacks use `AppLayout.chapterSpacing` (20); list hubs use `AppLayout.listSpacing` (16).
    - **No root tab has a navigation bar.** All five hide it (`.toolbar(.hidden, for: .navigationBar)`). The bar's only content was the tab's own name — "History" rendered directly above a tab button labelled History — and it cost 44pt permanently, with `.searchable` stacking another ~50pt under it. Library and History were spending ~100pt of every screen on chrome before the first row of content.
    - **What replaced it:** the section picker (`SectionPicker`) is the one pinned row. **Search belongs to the section, not the page**: each section draws its own `InlineSearchField` as the first thing in its content, so it scrolls away like Mail's and swaps with the section — which is what a per-section search string (`Search prompts…` / `Search stories…` / `Search tools…`) actually means. The filter / sort button rides on the trailing end of that row (`.headerIconChrome()`), which is also the only place it does not collide with anything: parked at the end of a chip row or a folder bar, the chips scroll underneath it. Learn has no search, so its trophy sits in `awardsRow`. An inline field must also declare `.scrollDismissesKeyboard(.interactively)` — `.searchable` gave that for free.
    - **The trailing accessory is the same size as the field.** `.headerIconChrome()` is `AppLayout.minHitTarget` square at the capsule radius `InlineSearchField` uses, so the filter button reads as the field's twin rather than a smaller plate centred in a 44pt box. It was a 36pt plate inside a separate 44pt frame, which put a visible 4pt of dead air on each side and left the icon short next to the 44pt field. The glass *is* the hit target — do not wrap it in a second `.frame`. The Learn trophy wears the same modifier so the five accessories agree.
    - Owning the search row inside the section is what makes this work without plumbing: a section's control needs that section's state (`AllPromptsView`'s difficulty filter and CSV importer, `StoriesViewModel`'s sort order), and a child cannot hand a view up to its parent now that there is no toolbar to do it. The hub keeps the `@State` string and passes a `Binding` down.
    - **Nested pushes keep a real `.inline` title** (lesson detail, a setting, a story) and add `.restoresNavigationBar()`. SwiftUI resolves toolbar visibility per view in the stack, so a push gets the bar back on its own; the pushed pages say it anyway, because a detail page silently missing its Back button is an expensive thing to be wrong about. **A child of a bar-less root cannot own a `topBarTrailing` item** — it renders nowhere. Put the control in the page.
10. Nothing in a page may demand more width than the screen. `.fixedSize()` on a row, a wide fixed `.frame(width:)`, or a pinned pill row are the usual causes — check at 375pt *and* at accessibility text sizes, and reach for `ViewThatFits` before pinning (see `ActivityStrip.header`).
11. Controls keep a `AppLayout.minHitTarget` (44pt) hit target even when their visible icon/chip is smaller. Selected controls expose `.isSelected`; modal overlays expose `.isModal` + Escape; Reduce Motion suppresses ambient/celebration motion.
12. **Tint is for identity, not emphasis.** A colored `glassEffect` tint stays at **0.06** (a whole card or tile) or
    **0.10** (a featured/recommended row); anything above that turns a graphite page into a highlighter. Identity color
    belongs to the *glyph* — an icon at full tint inside a `Circle().fill(tint.opacity(0.18))` chip. `ToolTileLabel`
    (Today prep tools, History review grid) and `ToolCategoryCard` (Library tools) wear the same recipe — change one, change both. `StreakChip` is neutral glass with an amber flame:
    the streak is one number and does not need a billboard. Selected filter chips are the solid white pill
    (`FilterChip` / `FilterPill` / `SectionPicker`) on every tab; a chip's own color, if it has one, shows on the idle glyph.
13. **Liquid Glass surfaces (shared):** `GlassCard`, `SectionPicker` frame, `ToolTileLabel`, `FilterPill`, `StreakChip`, secondary `GlassButton`, `SourceStoryBanner`, duration/time-range capsules, icon chip buttons. Apply `.glassEffect` *after* padding/frame. Use `.interactive()` only on tappable chrome. Do not glass the white primary CTA. Selected section pills stay solid white (same as `SectionPicker`). Untinted surfaces take `@Environment(\.glassAppearance).glassTint` (Light = soft white lift 0.08; Dark = quieter 0.02) so Settings → Appearance → App Look can deepen the glass. Cards paint **no** rim stroke of their own: `glassEffect` already lights its edge, and a white overlay on top of it stacked a second line that read as a halo (worst on the tallest plate, the Today focus card). Edge definition is the system's job — do not reintroduce a `.strokeBorder` rim on a glass surface (`FeaturedGlassCard` lost its `cardStroke` hairline for the same reason). A colored stroke that *means* something — `GlassCard(accentBorder:)` for selection, the dashed rect on a dormant Today block — is state, not chrome, and stays. `glassCard()` and `GlassCard` now paint the same shadow. `ContentView` injects both `glassAppearance` and `appCanvas` from `UserSettings`.
13b. **Never stack glass on glass.** Liquid Glass samples what is *behind* it, so a second `glassEffect` laid straight on a `GlassCard` samples the plate instead of the canvas and renders as a murky grey band where a control should be — the shading on the Today focus card after its CTA became `GlassButton.secondary`. `GlassCard` / `FeaturedGlassCard` / `.glassCard()` set `\.isOnGlass` on their content, and `GlassButton.secondary` reads it and paints a capsule (white 0.10 fill + 0.16 rim) instead. Any new glass surface that can appear inside a card owes the same branch; a `GlassEffectContainer` is the alternative when two glass surfaces genuinely have to share a region. The branch is on an environment value, never on animated state — see rule 14.

14. **Never animate a glassEffect on/off.** Selection that swaps glass ↔ solid fill under `withAnimation` mid-fades into a dark clipped rectangle for a beat — `SelectedFilterChrome` hard-cuts with `.transaction { $0.animation = nil }`, and filter chips use `.buttonStyle(.plain)` (no press-scale on live glass). Hit targets expand *around* the capsule, never under the glass.
15. **Empty / CTA copy:** sentence case (`"No recordings yet"`, `"Start recording"`). Verb-first buttons. Errors say how to recover.
16. **Numerals:** `Font.displayNumeral` / `.metricValue` / `.statValue` carry tabular figures — use them (or `.monospacedDigit()`) on any value that updates.
17. **App canvas budget.** All background art lives in **one catalogue**, `CanvasLook` — `AppCanvas` and `RecordingBackdrop` are two persisted menus over it, each mapping a stored raw value to a look via `.look`. Aurora means the same Aurora on both screens; the menus used to keep private copies (`AppAuroraCanvas` vs `AuroraCanvas`, `AppHorizonCanvas` vs `VoidCanvas`) that drifted the moment either was touched. `CanvasLook` is **not persisted** — add, rename or reorder cases freely; only the two menus' raw values are the SwiftData payload. A menu grows into a look it does not offer yet with one new case plus one line in `look`. `CanvasMood` (`.ambient` behind tabs, `.session` behind a take) is the single knob for intensity and particle density — never write a second painter for the same look.
    - **Every look is a still.** No `TimelineView`, no per-frame repaint. Motion behind tabs burned frames for wallpaper the eye stops noticing, and a tab switch restarted the clock. There is no `animated:` parameter and no `CanvasLook.isAnimated` — both were no-ops kept for call-site compatibility, and a `isAnimated` hardcoded to `false` meant the test guarding "every look is a still" could not fail. If motion behind a tab is ever wanted again, it needs a real decision, not a dormant flag.
    - **One `Canvas` pass per background**, never a stack of `RadialGradient` views. Paint through the primitives in `CanvasLook.swift` (`canvasWash` / `canvasGlow` / `canvasStars` / `canvasSparks` / `canvasAuroraShaft` / `canvasHorizonLine` / `canvasGround` / `canvasVignette` / `canvasWaveRibbon`); they are private, so new art belongs in that file.
    - Inside a `Canvas`, `graphics.blendMode = .plusLighter` and transforming a *copy* of the context are free state changes; the `.blendMode()` / `.blur()` **view** modifiers are not — each forces an offscreen compositing group.
    - **No `.drawingGroup`.** A `Canvas` already is the flattened layer Liquid Glass samples. The old `drawingGroup(opaque: true)` cost a texture allocation on every screen appearance (the beat of empty canvas on a push) plus a re-rasterization every tick, once per screen still alive in the stack.
    - **Normalise every dimension against `hypot(size.width, size.height)`** (`CanvasFrame.d` / `.unit` / `.at`), never fixed point radii. That makes a 76pt picker tile a true miniature of the full screen, and makes two stacked full-screen backgrounds paint identical pixels so a push does not slide one composition over another.
    - `ContentView` paints the canvas **inside** each tab's `NavigationStack` (`tabContent` wraps `tabRoot` in `.background { AppBackground() }`) — root tabs do not each paint their own, and a background behind the `TabView` is invisible because SwiftUI hosts navigation content in an opaque system-background view (that is the all-black-tabs bug).
    - `CanvasLookView` does **not** call `.ignoresSafeArea()` — that expansion made picker tiles steal layout and punch a hole in the button's hit target. `AppBackground` and full-screen `RecordingBackdropView(fillsSafeArea: true)` apply it. Picker tiles and hub swatches pass `fillsSafeArea: false`.
    - Tone (`.primary` / `.subtle` / `.recording`) nudges only Classic and Midnight, and `.subtle` stays a hair from `.primary` so a pushed detail view does not pop; every other look ignores tone and keeps one mood. Classic is frozen: quiet navy-blue counterweight, never bright violet, never a composition rewrite. No MeshGradient anywhere.

## New view checklist

1. `PageScrollView` + `.appBackground` + `.pageContentInsets()` (root tabs)
2. `GlassCard` content blocks
3. `AppColors` only
4. `GlassButton` for actions
5. `GlassSectionHeader` for sections
6. Haptics on interaction
7. `// MARK:` when file grows past ~60 lines
8. Root tabs: real `.inline` nav title, except Today which hides the bar entirely. Never `.large`, never an empty title on a page that has toolbar buttons. Nested pushes: real title + `.inline` unless a sheet owns its own chrome.

## Cross-links

All feature view docs. Prefer existing `Components/` before inventing new chrome.
