#!/usr/bin/env bash
# Agent landmine verify — mirrors docs/AGENT_PLAYBOOK.md → Verify.
# Run after SpeakUp / SpeakUpWidget edits. Exit 0 = greps ran (hits may be
# known-good); exit 1 = tool missing or unexpected failure.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required" >&2
  exit 1
fi

echo "== agent-verify: landmine greps =="

run() {
  local title="$1"
  shift
  echo
  echo "--- ${title} ---"
  # Intentionally do not fail on matches: known-good call sites exist.
  # Agents must read the playbook / gotchas when a hit appears in *new* code.
  rg -n "$@" || true
}

run "Isolation / UIKit-era state" \
  '@StateObject|@ObservedObject' SpeakUp SpeakUpWidget --glob '*.swift'

run "Design-system leaks" \
  'Color\.(blue|red|green|orange|purple|yellow)\b' SpeakUp --glob '*.swift'

run "SwiftData blob predicates" \
  '#Predicate' SpeakUp --glob '*.swift'

run "Membership scatter" \
  'isLifetime' SpeakUp --glob '*.swift'

run "Widget reloads" \
  'reloadAllTimelines\(' SpeakUp --glob '*.swift'

run "Audio-engine taps" \
  'installTap|removeTap' SpeakUp --glob '*.swift'

run "On-device recognition" \
  'requiresOnDeviceRecognition' SpeakUp --glob '*.swift'

run "noSpeechThreshold" \
  'noSpeechThreshold' SpeakUp --glob '*.swift'

echo
echo "== agent-verify: toolchain probe =="
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version | head -2
  echo "Xcode present → run tests (scheme SpeakUp) after Swift changes."
else
  echo "xcodebuild missing (Linux/cloud) → grep-only verify; CI macos-26 runs tests."
fi

echo
echo "Done. New hits outside known-good files → open docs/AGENT_GOTCHAS.md."
echo "Doc/path drift → scripts/agent-doc-drift.sh"
