# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SpeakUp is a native iOS speech practice app built with SwiftUI and SwiftData. It helps users improve public speaking by recording, transcribing (via WhisperKit), and analyzing speech with metrics like filler word usage, pace, clarity, and pause quality.

## Build & Run

```bash
# Open in Xcode
open SpeakUp.xcodeproj

# Build from CLI
xcodebuild build -project SpeakUp.xcodeproj -scheme SpeakUp -configuration Debug

# Build for simulator
xcodebuild -project SpeakUp.xcodeproj -scheme SpeakUp \
  -destination 'generic/platform=iOS Simulator' -configuration Debug
```

No test suite exists in this project. The sole external dependency is **WhisperKit** (on-device speech-to-text), resolved via Swift Package Manager.

## Architecture

**MVVM + Services pattern** with `@Observable` (iOS 17+):

```
View (SwiftUI) → ViewModel (@Observable) → Service (@Observable) → SwiftData Models
```

### Key layers

- **Models/** — SwiftData entities: `Recording`, `Prompt`, `UserSettings`, `UserGoal`, `Achievement`. `SpeechAnalysis.swift` contains the core speech metrics and context-aware filler word classification logic.
- **Services/** — Business logic. `SpeechService` orchestrates transcription, `WhisperService` wraps WhisperKit, `AudioService` handles AVFoundation recording/playback. Each service defines its own error enum.
- **ViewModels/** — One per major feature area (`RecordingViewModel`, `HistoryViewModel`, `SettingsViewModel`, `TodayViewModel`, etc.).
- **Views/** — Organized by feature: `Today/`, `Recording/`, `History/`, `Achievements/`, `Goals/`, `Settings/`, `PromptWheel/`, `Onboarding/`, `Social/`. Reusable pieces live in `Components/`.
- **Theme/** — `AppColors`, `GlassStyles`, `AppBackground` define the glassmorphism design system. Glass effect helpers are in `Extensions/View+Glass.swift`.
- **Data/** — `DefaultPrompts.swift` (seed data across 10 categories), `SchemaVersioning.swift` (SwiftData migration plan).
- **SpeakUpWidget/** — Separate WidgetKit target with daily prompt and streak widgets.

### Entry point

`SpeakUpApp.swift` — initializes the SwiftData model container (with in-memory fallback) and sets up the environment.

### Navigation

Tab-based via `ContentView.swift` with NavigationStack support.

## Conventions

- **State management**: `@Observable` macro on all ViewModels and Services; `@Query` for SwiftData reads; `@Environment` for dependency injection.
- **Async**: `async/await` throughout — no callback-based patterns.
- **Error handling**: Each service has a dedicated error enum (e.g., `AudioServiceError`, `SpeechServiceError`).
- **UI style**: Glassmorphism (frosted glass cards/buttons). Use `GlassCard`, `GlassButton`, and the `.glass()` view modifier for consistency.
- **Naming**: Files and types in `CapitalCase`, functions/properties in `camelCase`. Code sections organized with `// MARK:` comments.
