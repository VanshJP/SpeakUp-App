---
name: speakup
description: >
  Big Talk / SpeakUp product skill (iOS 26 speech-practice app). Router for
  SpeakUp/, SpeakUpWidget/, SpeakUpTests/, SPEECH.md, onboarding, Stories,
  Read-Aloud, curriculum, widgets, paywall, settings, and agent docs. Use on
  any feature edit in this repo. Tells you which one feature doc and which
  one vendor skill to open. Do not skip for SpeakUp Swift changes.
---

# SpeakUp — product router

Kernel (NEVER, stance, map) is always in `/AGENTS.md`. This skill is the next layer: what to open, then how to check.

## Protocol

1. Find the row in `/docs/features/README.md`. Open **that one** feature doc.
2. If the row names a contract (`SPEECH.md`, `ONBOARDING_VISION.md`), read it before editing.
3. If the row names gotchas sections, open `/docs/AGENT_GOTCHAS.md` and read those sections only.
4. Adding a setting / gate / SwiftData field / widget / test → `/docs/AGENT_PLAYBOOK.md` for that recipe.
5. Load **at most one** vendor skill from `.agents/skills/README.md`.
6. Code is truth. If the doc disagrees, follow the code and patch the doc in the same PR.
7. After edits: playbook → Verify (grep always). If `xcodebuild -version` works, run tests. If not, do not fake it — CI will.

## Where things live

```
SpeakUpApp.swift          ModelContainer, inject, seed, migrate
Views/ContentView.swift   5 tabs + global sheets + deep links
Models/                   SwiftData entities + value types
Services/                 no UI; own LocalizedError
ViewModels/               @MainActor @Observable; no ModelContext
Views/<Feature>/          SwiftUI
Theme/                    AppColors, glass, background, type, motion
Data/                     seeds (prompts, curriculum, passages)
SpeakUpWidget/            WidgetKit + App Group only
SpeakUpTests/             Swift Testing
```

Tabs: Today → Library (`PracticeHubView`) → History → Learn (`CurriculumView`) → Settings. Achievements are a **sheet**, not a tab.

## Beta monetization

`BetaAccess.allFeaturesFree == true`. Paywall UI is deleted. Do not add a gate until the unlock UI is restored. Details: `docs/features/monetization.md`.

## Discovery

No semantic index. Prefer:

```bash
rg -n 'symbol' SpeakUp --glob '*.swift'
```

Path + type search over whole-repo dumps.

## Do not

- Invent a second share sheet, a sixth tab, a third first-run coach, or a new StoreKit Environment key.
- Load `ONBOARDING_REDESIGN.md` unless the task is onboarding research.
- Load both `swiftui-pro` and `swiftui-expert-skill`.
- Grow `/AGENTS.md` with feature encyclopedias.

## After a behavior change

Update `docs/features/<slug>.md` and the index row. New silent failure → `docs/AGENT_GOTCHAS.md`. New repeatable workflow → `docs/AGENT_PLAYBOOK.md`.
