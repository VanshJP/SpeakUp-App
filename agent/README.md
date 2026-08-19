# Agent system

Instructions for coding agents that work on Big Talk / SpeakUp. Humans: this is not the product README. Agents: start at `/AGENTS.md`, then this map only if you are changing the agent stack itself.

## Layers (progressive disclosure)

| Layer | Path | Loaded when |
|-------|------|-------------|
| Kernel | `/AGENTS.md` (`CLAUDE.md` → same file) | Always. Keep it small. |
| Feature index | `/docs/features/README.md` | Locating code / adding a surface |
| Landmines | `/docs/AGENT_GOTCHAS.md` | Concurrency, SwiftData, shares, widgets, audio thread |
| Recipes | `/docs/AGENT_PLAYBOOK.md` | Setting / gate / field / widget / test / static verify |
| Feature briefs | `/docs/features/<slug>.md` | That feature only |
| Contracts | `/SPEECH.md`, `/ONBOARDING_VISION.md`, listing/release docs | Subsystem named in the index |
| Product skill | `.agents/skills/speakup/SKILL.md` | Any SpeakUp product edit |
| Vendor skills | `.agents/skills/<name>/SKILL.md` | Task matches YAML `description` |
| Lockfile | `/skills-lock.json` | Vendored skill provenance |

Do not copy kernel rules into feature docs. Do not copy feature docs into the kernel.

## Canonical skills directory

**Source of truth:** `.agents/skills/`

| Alias | Points at | Consumed by |
|-------|-----------|-------------|
| `.claude/skills/<name>` | symlink → `../../.agents/skills/<name>` | Claude Code |
| `agent/skills` | symlink → `../.agents/skills` | Tools that look in `agent/` |

Do not add a third copy of a vendor skill. Install once under `.agents/skills/`, then symlink.

First-party: `speakup` (router + verify). Vendored: see `.agents/skills/README.md` and `skills-lock.json`. Do not edit vendor `SKILL.md` bodies except to wire Big Talk paths that already exist (`greenlight`).

## Why this shape (2026)

- Always-on tokens are the scarce resource. Kernel = stance + NEVER + pointers. Encyclopedias live behind a click.
- Skills use YAML `name` / `description` so the agent can decide *whether* to open the body. Nested `references/` are a third layer — open one file, not the folder.
- `agent/skills` used to be a full duplicate of `.agents/skills` and drifted (different hashes, missing `caveman` / `aso-appstore-screenshots`). Aliases are symlinks so that cannot happen again.
- A skill-local `CLAUDE.md` is auto-injected by some tools as a workspace rule. Vendor skills must not ship `CLAUDE.md`; root `CLAUDE.md` → `AGENTS.md` is the only one.
- Build/test is capability-based: run `xcodebuild` when it exists (local Mac). Linux cloud agents grep + rely on CI (`macos-26`). Do not encode a Linux limitation as a universal NEVER.

## Changing this system

1. Kernel change → `/AGENTS.md` only if it is always-on (NEVER, stance, map). Otherwise put it in gotchas, playbook, a feature doc, or `speakup`.
2. New vendor skill → install into `.agents/skills/<name>/`, add a row to `.agents/skills/README.md`, pin in `skills-lock.json`, symlink from `.claude/skills/` if that tree does not glob `.agents`.
3. New first-party skill → `.agents/skills/<name>/SKILL.md` with `name` + `description` (what **and** when). Body < ~150 lines; further detail in `references/`.
4. Do not add nested `AGENTS.md` under `SpeakUp/` — closest-file-wins would hide the kernel.
