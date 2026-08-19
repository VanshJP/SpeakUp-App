# Skills catalog

Canonical directory. Aliases: `.claude/skills/` and `agent/skills` (symlinks). Load **one** `SKILL.md` body per task. YAML `name` + `description` are enough to decide.

Install / pin: `/skills-lock.json`. Layout: `/agent/README.md`.

| Skill | Use when |
|-------|----------|
| `speakup` | Any Big Talk / SpeakUp product edit — router, landmines, verify without Xcode. First-party. **Start here for app code.** |
| `caveman` | User wants terse chat (`/caveman`, "less tokens"). Chat only; never commits/PRs/comments. |
| `swiftui-expert-skill` | **Write or refactor** SwiftUI (state, lists, Liquid Glass, iOS 26). |
| `swiftui-pro` | **Review** SwiftUI for modern API / hygiene / performance. Do not load together with `swiftui-expert-skill`. |
| `swiftdata-pro` | Models, `#Predicate`, indexing, CloudKit. Pair with gotchas §2–§3. |
| `swift-concurrency` | Isolation, `Sendable`, actors, `async`. Pair with gotchas §1. |
| `widgetkit` | WidgetKit, App Group, timelines, controls. Pair with gotchas §8. |
| `ios-accessibility` | VoiceOver, Dynamic Type, nutrition labels. |
| `axiom-media` | `AVAudioEngine`, taps, camera, haptics, speech audio. Pair with gotchas §9. |
| `greenlight` | App Store preflight / rejection risk near ship. |
| `apple-appstore-reviewer` | Reviewer-persona audit of code + metadata. Read-only first pass. |
| `aso-appstore-screenshots` | App Store screenshot generation (compose.py → model enhance). |

Root `/AGENTS.md` is always loaded — do not paste it into a skill.
