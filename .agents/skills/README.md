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
| `better-interface` | Full UI review across a11y, layout, writing, type, color, polish. Prefer over loading every `better-*` separately. |
| `better-ui` | Press scale, surfaces, concentric radius, icon motion, hit feel. |
| `better-typography` | Type scale, tabular nums, wrapping, truncation. |
| `better-colors` | Palettes, semantic tokens, contrast (measure before claiming). |
| `better-layout` | Grouping, alignment, progressive disclosure, adaptivity. |
| `better-accessibility` | Focus, keyboard/VoiceOver names, hit targets, reduced motion. Pair with `ios-accessibility` for platform depth. |
| `better-writing` | Product copy — empty states, errors, button verbs, sentence case. |
| `interface-review` | Change-scoped review of a branch / PR / uncommitted diff. |
| `break` | Stress-test one component across states (web-oriented; adapt carefully). |
| `variant` | Explore alternate component variants before picking one. |
| `explain-interface` | Reverse-engineer how a web interface was built. |

Root `/AGENTS.md` is always loaded — do not paste it into a skill.

Interface polish set (`better-*`, `interface-review`, `break`, `variant`, `explain-interface`) is vendored from [jakubkrehel/skills](https://github.com/jakubkrehel/skills). For SpeakUp UI work: load `speakup` first, then at most one of `better-interface` **or** `swiftui-expert-skill` / `swiftui-pro` (not both SwiftUI skills).
