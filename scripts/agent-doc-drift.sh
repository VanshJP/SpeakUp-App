#!/usr/bin/env bash
# Fail when feature docs / index point at missing paths or dead key symbols.
# Linux-safe. Used by CI agent-guards and by agents before trusting a brief.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required" >&2
  exit 1
fi

FEATURES_DIR="docs/features"
INDEX="${FEATURES_DIR}/README.md"
ERR=0

fail() {
  echo "drift: $*" >&2
  ERR=1
}

echo "== agent-doc-drift: index + feature briefs =="

if [[ ! -f "$INDEX" ]]; then
  fail "missing $INDEX"
  exit 1
fi

while IFS= read -r slug; do
  path="${FEATURES_DIR}/${slug}"
  if [[ ! -f "$path" ]]; then
    fail "index links to missing ${path}"
  fi
done < <(rg -oN --no-filename '\./[a-z0-9-]+\.md' "$INDEX" | sed 's|^\./||' | sort -u)

for contract in SPEECH.md ONBOARDING_VISION.md ONBOARDING_REDESIGN.md \
  APP_STORE_LISTING.md APP_STORE_PRODUCT_PAGES.md RELEASE_CHECKLIST.md; do
  if [[ ! -f "$contract" ]]; then
    fail "index/contract missing ${contract}"
  fi
done

for agent_doc in docs/AGENT_GOTCHAS.md docs/AGENT_PLAYBOOK.md; do
  if [[ ! -f "$agent_doc" ]]; then
    fail "missing ${agent_doc}"
  fi
done

# Paths in backticks. Skip globs and explicitly deleted paywall tree.
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  if [[ "$rel" == *"*"* || "$rel" == *"…"* || "$rel" == *"..."* ]]; then
    continue
  fi
  if [[ "$rel" == "SpeakUp/Views/Paywall" || "$rel" == "SpeakUp/Views/Paywall/" ]]; then
    continue
  fi
  if [[ "$rel" == */ ]]; then
    if [[ ! -d "$rel" ]]; then
      fail "missing directory \`${rel}\` (cited in feature docs)"
    fi
    continue
  fi
  if [[ ! -e "$rel" ]]; then
    fail "missing path \`${rel}\` (cited in feature docs)"
  fi
done < <(
  rg -oN --no-filename '`((SpeakUp|SpeakUpWidget|SpeakUpTests)/[^`]+)`' "$FEATURES_DIR" \
    -r '$1' | sort -u
)

check_symbol() {
  local name="$1"
  local needle="$2"
  if ! rg -q "$needle" SpeakUp SpeakUpWidget --glob '*.swift'; then
    fail "symbol not found for ${name} (needle: ${needle})"
  fi
}

check_symbol ContentView 'struct ContentView'
check_symbol AppTab 'enum AppTab'
check_symbol PracticeHubView 'struct PracticeHubView'
check_symbol ToolPresentation 'enum ToolPresentation'
check_symbol RecordingProcessingCoordinator 'class RecordingProcessingCoordinator|final class RecordingProcessingCoordinator'
check_symbol SharePresenter 'enum SharePresenter'
check_symbol FreeTierPolicy 'struct FreeTierPolicy'
check_symbol BetaAccess 'enum BetaAccess'
check_symbol SessionWordsRow 'struct SessionWordsRow'
check_symbol ReadAloudService 'class ReadAloudService'
check_symbol AppTourOverlay 'struct AppTourOverlay'
check_symbol VocabChallengeService 'enum VocabChallengeService|struct VocabChallengeService'
check_symbol SpeakUpApp 'struct SpeakUpApp'

for dead in SessionBriefRow WordAlignmentScorer MetricTile; do
  if rg -n "\`${dead}\`|${dead}\\.swift|${dead}\\.score" "$FEATURES_DIR" \
      --glob '!**/monetization.md' >/dev/null 2>&1; then
    fail "stale live reference to ${dead} in feature docs"
  fi
done

FRESH_MAP="$(mktemp)"
scripts/generate-surface-map.sh "$FRESH_MAP" >/dev/null
if ! diff -q "$FRESH_MAP" docs/SURFACE_MAP.md >/dev/null; then
  fail "docs/SURFACE_MAP.md is stale; run scripts/generate-surface-map.sh"
fi
rm -f "$FRESH_MAP"

if [[ "$ERR" -ne 0 ]]; then
  echo
  echo "agent-doc-drift failed — patch the brief or restore the path/symbol." >&2
  exit 1
fi

echo "OK — feature index, cited paths, and key symbols look consistent."
