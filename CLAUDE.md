# CLAUDE.md

This file provides guidance to Claude Code when working with the SpeakUp iOS project.

## Project Overview

SpeakUp is a native iOS speech practice app built with SwiftUI and SwiftData. It helps users improve public speaking by recording, transcribing (via WhisperKit), and analyzing speech with metrics like filler word usage, pace, clarity, volume, vocabulary complexity, and pause quality. Features include structured drills, warm-up exercises, confidence tools, a learning curriculum, social challenges, progress journaling, and achievement tracking.

## Build & Run
```bash
# Build for simulator
xcodebuild -project SpeakUp.xcodeproj -scheme SpeakUp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug build 2>&1 | xcpretty || xcodebuild -project SpeakUp.xcodeproj -scheme SpeakUp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug build

# Boot simulator if needed
xcrun simctl boot "iPhone 16" 2>/dev/null || true

# Install & launch
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/SpeakUp-*/Build/Products/Debug-iphonesimulator/SpeakUp.app
xcrun simctl launch booted com.vansh.speakup

# Terminate
xcrun simctl terminate booted com.vansh.speakup
```

## UI Testing Loop (use this whenever verifying visual changes)

Always follow this sequence — never assume UI is correct without checking:
```bash
# 1. Screenshot
xcrun simctl io booted screenshot /tmp/speakup_screen.png

# 2. Inspect accessibility tree
idb describe-all

# 3. Interact
idb tap <x> <y>
idb type "text"
idb swipe <x1> <y1> <x2> <y2>

# 4. Screenshot again to confirm
xcrun simctl io booted screenshot /tmp/speakup_after.png
```

When debugging a UI issue:
- Screenshot first, inspect second, fix third, verify fourth
- Cross-reference visual screenshot with `idb describe-all` element frames
- Rebuild and re-verify after every fix before moving to the next issue

## Architecture

**MVVM + Services** with `@Observable` (iOS 17+):
```
View (SwiftUI) → ViewModel (@Observable) → Service (@Observable) → SwiftData Models
```

### Layer responsibilities

- **Models/** — SwiftData entities: `Recording`, `Prompt`, `UserSettings`, `UserGoal`, `Achievement`, `CurriculumProgress`. Pure structs: `SpeechAnalysis` (metrics, scoring, filler detection), `DrillMode`, `WarmUpExercise`, `ConfidenceExercise`, `SocialChallenge`, `DailyChallenge`, `SpeechFramework`, `CurriculumModels`.
- **Services/** — Business logic only, no UI. Each service is `@Observable` and owns its error enum:
  - `SpeechService` — orchestrates transcription + analysis
  - `WhisperService` — WhisperKit on-device STT
  - `AudioService` — AVFoundation record/playback/metering
  - `LiveTranscriptionService` — real-time filler detection during recording
  - `HapticCoachingService` — haptic feedback for pace/silence/fillers
  - `ChirpPlayer` — audio cue playback for warm-ups/drills
  - `AchievementService` — checks/unlocks achievements post-recording
  - `CoachingTipService` — generates contextual coaching tips from analysis
  - `DailyChallengeService` — daily challenge generation
  - `WeeklyProgressService` — weekly stats computation
  - `WeakAreaService` — identifies weakest metric and suggests exercises
  - `CurriculumService` — loads curriculum, tracks lesson completion
  - `NotificationService` — daily reminder scheduling
  - `ExportService` — share recordings via UIActivityViewController
  - `ScoreCardRenderer` — UIKit-drawn shareable score card image
  - `JournalExportService` — PDF progress journal generation
  - `SocialChallengeService` — deep link challenge handling
  - `AudioWaveformGenerator` — waveform data from audio files
  - `WidgetDataProvider` — writes shared data for widget target
- **ViewModels/** — One per feature area, `@MainActor @Observable`. Owns UI state, calls services. Never imports SwiftData directly: `TodayViewModel`, `RecordingViewModel`, `HistoryViewModel`, `SettingsViewModel`, `OnboardingViewModel`, `PromptWheelViewModel`, `ComparisonViewModel`, `ProgressReplayViewModel`, `DrillViewModel`, `WarmUpViewModel`, `CurriculumViewModel`.
- **Views/** — Grouped by feature (see View Groups below). Shared pieces in `Components/`.
- **Theme/** — `AppColors`, `GlassStyles`, `AppBackground`. All UI uses the glassmorphism system — never raw colors or custom styling outside the theme.
- **Extensions/** — `Date+Helpers.swift` (date math, formatting, streak calculation), `Haptics.swift` (typed haptic feedback), `View+Glass.swift` (iOS 26 liquid glass compatibility).
- **Data/** — `DefaultPrompts.swift`, `DefaultWarmUps.swift`, `DefaultConfidenceExercises.swift`, `DefaultCurriculum.swift`, `SchemaVersioning.swift`.
- **SpeakUpWidget/** — Separate WidgetKit target. Daily prompt + streak widgets. Keep widget code isolated from main app logic.

### View groups

| Folder | Files | Purpose |
|--------|-------|---------|
| `Today/` | `TodayView`, `DailyChallengeCard`, `WeeklyProgressCard` | Home tab — stats rings, prompt card, quick-access toolbar, daily challenge, weekly progress |
| `Recording/` | `RecordingView`, `RecordButton`, `TimerView`, `CountdownOverlayView`, `FillerCounterOverlay`, `FrameworkOverlayView` | Full-screen recording session with live filler count, framework cues, circular waveform |
| `Detail/` | `RecordingDetailView`, `SpeechTimelineView`, `PaceChartView`, `CoachingTipsView`, `ListenBackEncouragementView`, `ScoreCardPreview` | Post-recording analysis — scores, highlighted transcript, waveform playback, coaching tips |
| `History/` | `HistoryView`, `ComparisonView` | Contribution graph, streak stats, searchable recordings list, first-vs-latest comparison |
| `Achievements/` | `AchievementGalleryView`, `AchievementUnlockedView` | Achievement grid with unlock celebrations + confetti |
| `Goals/` | `GoalsView` | Goal management with templates |
| `Curriculum/` | `CurriculumView`, `CurriculumProgressCard`, `LessonDetailView` | Structured learning path with weekly phases and lesson tracking |
| `WarmUp/` | `WarmUpListView`, `WarmUpExerciseView`, `BreathingAnimationView` | Pre-speech exercises (Breathing, Tongue Twisters, Vocal, Articulation) |
| `Drills/` | `DrillSelectionView`, `DrillSessionView`, `DrillResultView` | Focused drills (Filler Elimination, Pace Control, Pause Practice, Impromptu Sprint) |
| `Confidence/` | `ConfidenceToolsView`, `ConfidenceExerciseView` | Calming, Visualization, Progressive, Affirmation exercises |
| `Progress/` | `BeforeAfterReplayView`, `JournalExportView`, `JournalSummaryView` | Then-vs-Now audio replay, PDF journal export with date ranges |
| `Social/` | `ChallengeShareView`, `ChallengeAcceptView` | Deep-link friend challenges |
| `Settings/` | `SettingsView`, `WordBankInputView` | Session defaults, analysis settings, word bank, reminders, data management |
| `PromptWheel/` | `PromptWheelView` | Spinning random prompt selector |
| `Onboarding/` | `OnboardingView`, `OnboardingPageView` | First-launch onboarding flow |
| `Components/` | `GlassCard`, `GlassButton`, `RingStatsView`, `ConfettiView` | Reusable glass-styled components |

### Entry point

`SpeakUpApp.swift` — initializes SwiftData model container (schemas: `Recording`, `Prompt`, `UserGoal`, `UserSettings`, `Achievement`, `CurriculumProgress`; in-memory fallback). Injects `SpeechService` and `AudioService` via `@Environment`. Seeds prompts, settings, achievements, and curriculum on first launch. Preloads WhisperKit model in background.

### Navigation

4-tab layout in `ContentView.swift` using iOS 17 `Tab { }` API:

| Tab | Icon | Root View |
|-----|------|-----------|
| Today | `mic.badge.plus` | `TodayView` |
| History | `clock.fill` | `HistoryView` → `RecordingDetailView` |
| Achievements | `trophy.fill` | `AchievementGalleryView` |
| Settings | `gearshape.fill` | `SettingsView` |

Global overlays/sheets managed at `ContentView` level: countdown, recording, prompt wheel, goals, warm-ups, drills, confidence tools, before/after replay, journal export, curriculum, social challenge accept, onboarding, achievement unlock celebration.

Deep link schemes: `speakup://record?prompt=<id>`, `speakup://challenge?...`

## UI Design System (follow this for all new views)

### Philosophy
Dark glassmorphism with a deep navy base. Every surface is translucent glass — no opaque cards, no flat backgrounds. The aesthetic is layered depth with subtle light effects.

### Background — `AppBackground`
Layered `ZStack` with radial gradient orbs on a deep navy base (`rgb: 0.05, 0.07, 0.16`):
- **`.primary`** — default for all tabs. Teal orb top-right (12%), indigo orb bottom-left (9%), cyan glow center (4%).
- **`.recording`** — darker navy with stronger teal (18%) and cyan (6%) for active recording sessions.
- **`.subtle`** — slightly lighter navy for sheets and detail views.

Apply via `.appBackground(.primary)`. Every screen must have an `AppBackground` — never use plain `Color` or system backgrounds.

### Glass surfaces — `GlassStyles`
All cards, buttons, and containers use `.ultraThinMaterial` as the base. Never use opaque backgrounds.

**Cards:**
- `.glassCard(cornerRadius:tint:)` — standard card. `ultraThinMaterial` + optional color tint + white inner glow at top edge + subtle top stroke + shadow (`black 20%, radius 8, y:3`). Default corner radius: 16.
- `GlassCard { }` — wrapper view applying the glass card modifier. Use this for most content blocks.
- `FeaturedGlassCard` — hero/highlight card with a gradient tint overlay. Use for primary CTAs and featured content.
- `StatCard` — compact stat display card.
- `ScoreDisplayCard` — score presentation with colored accents.
- `EmptyStateCard` — centered icon + message for empty lists.

**Buttons:**
- `GlassButton(title:icon:style:size:action:)` — 5 styles:
  - `.primary` — teal gradient capsule (main CTAs)
  - `.secondary` — `ultraThinMaterial` capsule (secondary actions)
  - `.outline` — teal border, clear fill
  - `.ghost` — clear fill, no border (tertiary)
  - `.danger` — red fill (destructive actions)
- `GlassIconButton` — circular icon-only button.
- Sizes: `.small`, `.medium`, `.large`.

**Modifiers:**
- `.glassCard(cornerRadius:tint:)` — apply glass card styling to any view
- `.glassBackground(cornerRadius:)` — simple `ultraThinMaterial` background
- `.glassSegmented()` — segmented control background
- `.animatedGlassBorder(cornerRadius:lineWidth:)` — rotating angular gradient border
- `.shimmer()` — sweep highlight animation for loading states
- `.glow(color:radius:)` — static double-shadow glow
- `.pulsingGlow(color:isActive:)` — animated pulsing shadow
- `.liquidGlass(tint:)` — native `.glassEffect()` on iOS 26+, falls back to `ultraThinMaterial`
- `.prominentGlass()` — interactive glass effect on iOS 26+

### Colors — `AppColors`
All colors come from `AppColors`. Never use raw `Color.blue`, `Color.gray`, etc.

| Token | Value | Usage |
|-------|-------|-------|
| `.primary` | Muted teal `#0D8488` | Brand color, primary buttons, progress rings, active states |
| `.accent` | Warm gray `#64748B` | Secondary text, subtle UI elements |
| `.success` | Green | Positive scores, completed states |
| `.warning` | Orange | Filler words, medium scores, streaks |
| `.error` | Red | Recording indicator, danger actions, low scores |
| `.info` | Blue | Informational badges |
| `.recording` | Red | Active recording states |
| `.recordingPulse` | Red 30% | Recording button pulse ring |

**Score colors** — `AppColors.scoreColor(for:)`: red (0-39), orange (40-59), yellow (60-79), green (80-100). Also `scoreGradient(for:)` for linear gradient fills.

**Glass tints** — used as card tint overlays:
- `.glassTintPrimary` — teal 10% (default cards)
- `.glassTintAccent` — white 5% (neutral cards)
- `.glassTintWarning` — orange 10% (warning/filler cards)
- `.glassTintError` — red 10% (error/danger cards)
- `.glassTintSuccess` — green 10% (success/completed cards)

**Other color functions:**
- `difficultyColor(_:)` — easy=green, medium=orange, hard=red
- `categoryColor(_:)` — maps prompt categories to distinct colors
- `contributionColor(intensity:)` — gray-to-green for the activity heatmap
- `Color(hex:)` — hex string initializer

### Typography patterns
Use system fonts with these conventions:
- Screen titles: `.title2.bold()` or `.title3.bold()`
- Section headers: `.headline` via `GlassSectionHeader(icon:title:)`
- Body text: `.body` or `.subheadline`
- Captions/metadata: `.caption` or `.footnote` with `.secondary` foreground
- Metric values: `.system(size: 28-36, weight: .bold, design: .rounded)` for large numbers
- Always `.foregroundStyle(.white)` for primary text on glass surfaces

### Spacing & layout conventions
- Card padding: 16-20pt internal padding
- Card spacing: 16pt between cards in scroll views
- Section spacing: 24pt between major sections
- Screen edge padding: `.padding(.horizontal, 20)` on scroll content
- Corner radii: 16pt for cards, 12pt for inner elements, 25pt+ for capsule buttons
- Use `LazyVStack(spacing: 16)` for scrolling card lists inside `ScrollView`

### Haptics — `Haptics`
Use typed haptic feedback for interactions:
- `Haptics.light()` — subtle taps (pill selection, toggles)
- `Haptics.medium()` — button presses
- `Haptics.heavy()` — significant actions (start recording)
- `Haptics.success()` — completion, unlock
- `Haptics.warning()` — caution states
- `Haptics.error()` — failures
- `Haptics.selection()` — picker/wheel changes

### Reusable components
Before building custom UI, check `Components/` for existing pieces:
- `GlassCard` / `FeaturedGlassCard` / `StatCard` / `EmptyStateCard` — card layouts
- `GlassButton` / `GlassIconButton` — buttons
- `RingStatsView` — triple concentric progress rings with metrics row
- `ConfettiView` — canvas-based celebration particles
- `GlassSectionHeader(icon:title:)` — section header with icon

### Building a new view — checklist
1. Wrap in `ScrollView` with `.appBackground(.primary)` (or `.subtle` for sheets)
2. Use `GlassCard { }` for every content block — no opaque surfaces
3. Colors from `AppColors` only — no raw colors
4. Buttons via `GlassButton` with appropriate style
5. Section headers via `GlassSectionHeader`
6. Haptic feedback on user interactions via `Haptics`
7. `// MARK: - Body` and `// MARK: - Subviews` when over ~60 lines
8. Animations: use `.spring(response: 0.3)` or `.easeInOut(duration: 0.2)` — keep subtle

## Code Conventions (always follow these)

### State & data flow
- `@Observable` on all ViewModels and Services — never `ObservableObject`
- `@Query` for SwiftData reads inside Views — never pass model context to ViewModels
- `@Environment(\.modelContext)` for writes
- `@Environment` for injecting services/viewmodels

### Async patterns
- `async/await` everywhere — no completion handlers or Combine
- Wrap AVFoundation callbacks in `withCheckedContinuation` if needed
- Use `Task { }` to bridge SwiftUI to async, `@MainActor` on ViewModels

### Error handling
- Every service has a dedicated error enum conforming to `LocalizedError`
- ViewModels catch service errors and expose `var errorMessage: String?` to Views
- Never `try!` or silent `catch {}`

### Naming & organization
- Types: `CapitalCase`, functions/properties: `camelCase`
- Organize with `// MARK:` sections
- File name matches primary type name exactly

### SwiftData rules
- Schema changes require a new `VersionedSchema` in `SchemaVersioning.swift`
- Never rename a `@Attribute` without a migration step
- Test schema changes with the in-memory container path first
- Current schemas: `Recording`, `Prompt`, `UserSettings`, `UserGoal`, `Achievement`, `CurriculumProgress`

## Common Pitfalls to Avoid

- Don't use `@StateObject` or `@ObservedObject` — this project uses `@Observable`
- Don't access `modelContext` in Services or ViewModels directly
- Don't add new colors or glass styles inline — extend `AppColors` or `GlassStyles`
- Don't use opaque backgrounds or raw `Color` values — always glass surfaces on `AppBackground`
- Don't create buttons without using `GlassButton` or `GlassIconButton`
- WhisperKit model loading is async and slow on first launch — always check `WhisperService` state before calling transcribe
- Widget target is sandboxed — it cannot access the main app's SwiftData store directly, use App Groups
- Sheets presented from `ContentView` should use `.appBackground(.subtle)` — not `.primary`
- New seed data files go in `Data/` — don't inline large data arrays in views or services

## Dependencies

- **WhisperKit** — on-device speech-to-text via Swift Package Manager. No API key needed.
- No other external dependencies.

## Simulator Shortcuts
```bash
# List available simulators
xcrun simctl list devices available

# Clear app data (reset to fresh install)
xcrun simctl uninstall booted com.vansh.SpeakUpMore

# View live app logs
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.vansh.SpeakUpMore"'

# Trigger a specific URL scheme
xcrun simctl openurl booted "speakup://debug"
```
---
name: greenlight
description: >
  Pre-submission compliance scanner for Apple App Store. Use this skill when reviewing
  iOS, macOS, tvOS, watchOS, or visionOS app code (Swift, Objective-C, React Native, Expo)
  to identify potential App Store rejection risks before submission. Triggers on tasks involving
  app review preparation, compliance checking, App Store submission readiness, or when a user
  asks about App Store guidelines.
---

# Greenlight — App Store Pre-Submission Scanner

You are an expert at preparing iOS apps for App Store submission. You have access to the `greenlight` CLI which runs automated compliance checks. Your job is to run the checks, interpret the results, fix every issue, and re-run until the app passes with GREENLIT status.

## Step 1: Run the scan

Run `greenlight preflight` immediately on the project root. Do NOT try to install greenlight — it is already available in PATH. Just run it:

## Step 2: Read the output and fix every issue

Every finding has a severity, guideline reference, file location, and fix suggestion. Fix them in order:
1. **CRITICAL** — Will be rejected. Must fix.
2. **WARN** — High rejection risk. Should fix.
3. **INFO** — Best practice. Consider fixing.

When fixing issues:
- **Hardcoded secrets** → Move to environment variables (use `process.env.VAR_NAME` or Expo's `Constants.expoConfig.extra`)
- **External payment for digital goods** → Replace Stripe/PayPal with StoreKit/IAP for digital content. External payment is only OK for physical goods.
- **Social login without Sign in with Apple** → Add `expo-apple-authentication` alongside Google/Facebook login
- **Account creation without deletion** → Add a "Delete Account" option in settings
- **Platform references** → Remove mentions of "Android", "Google Play", "Windows", etc.
- **Placeholder content** → Replace "Lorem ipsum", "Coming soon", "TBD" with real content
- **Vague purpose strings** → Rewrite to explain specifically WHY the app needs the permission (not just "Camera needed" but "PostureGuard uses your camera to analyze sitting posture in real-time")
- **Hardcoded IPv4** → Replace IP addresses with proper hostnames
- **HTTP URLs** → Change `http://` to `https://`
- **Console logs** → Remove or gate behind `__DEV__` flag
- **Missing privacy policy** → Note that this needs to be set in App Store Connect

## Step 3: Re-run and repeat

After fixing issues, re-run the scan:
```bash
greenlight preflight .
```

**Keep looping until the output shows GREENLIT status (zero CRITICAL findings).** Some fixes can introduce new issues (e.g., adding a tracking SDK requires ATT). The scan runs in under 1 second so re-run frequently.

## Severity Levels

| Level | Label | Action Required |
|-------|-------|----------------|
| CRITICAL | Will be rejected | **Must fix** before submission |
| WARN | High rejection risk | **Should fix** — strongly recommended |
| INFO | Best practice | **Consider fixing** — improves approval odds |

The goal is always: **zero CRITICAL findings = GREENLIT status.**

## Other CLI Commands

```bash
greenlight codescan .                      # Code-only scan
greenlight privacy .                       # Privacy manifest scan
greenlight ipa /path/to/build.ipa          # Binary inspection
greenlight scan --app-id <ID>              # App Store Connect checks (needs auth)
greenlight guidelines search "privacy"     # Search Apple guidelines
```

## About

**Greenlight** is built by [Revyl](https://revyl.com) — the mobile reliability platform.
Catch more than rejections. Catch bugs before your users do.
