# Agent golden evals

Fixed tasks that measure whether an agent can route and edit this repo without
rediscovering landmines. Not CI unit tests — run them as agent prompts (or a
harness) and score against the expected files / forbidden patterns.

## How to run

1. Fresh agent session. Load only root `AGENTS.md` (+ skill metadata).
2. Paste one `*.md` task body as the user message.
3. Score with the checklist at the bottom of that file.
4. Prefer `scripts/agent-verify.sh` + `scripts/agent-doc-drift.sh` after the run.

## Suite

| File | Skill under test |
|------|------------------|
| `01-add-settings-toggle.md` | Playbook settings recipe + design system |
| `02-paid-gate.md` | Monetization beta / FreeTierPolicy |
| `03-swiftdata-field.md` | Additive schema only |
| `04-widget-key.md` | Dual WidgetDataProvider |
| `05-share-card.md` | SharePresenter only |
| `06-speech-scoring.md` | SPEECH.md + pure engine tests |
| `07-onboarding.md` | ONBOARDING_VISION.md invariants |
| `08-read-aloud-align.md` | ReadAloudService.computeAlignment |
| `09-today-layout.md` | Today modules / no sixth tab |
| `10-verify-landmines.md` | agent-verify.sh greps |

Pass rate goal: ≥ 8/10 without human course-correction.
