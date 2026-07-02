#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COREAI_DIR="$ROOT_DIR/vendor/coreai-models"
EXPORT_DIR="${TINYCHAT_MODEL_EXPORT_DIR:-$ROOT_DIR/.build/coreai-exports/qwen3-0.6b-macos}"

if [[ -n "${TINYCHAT_APP_SUPPORT_DIR:-}" ]]; then
  APP_SUPPORT_DIR="$TINYCHAT_APP_SUPPORT_DIR"
else
  APP_SUPPORT_DIR="$HOME/Library/Containers/org.barnson.tinychat/Data/Library/Application Support/tinychat"
fi

CACHE_DIR="$APP_SUPPORT_DIR/Models/qwen3-0.6b/macOS"

if [[ ! -d "$COREAI_DIR" ]]; then
  echo "Missing CoreAI checkout at $COREAI_DIR" >&2
  exit 1
fi

mkdir -p "$(dirname "$EXPORT_DIR")" "$(dirname "$CACHE_DIR")"

(
  cd "$COREAI_DIR"
  uv run coreai.llm.export Qwen/Qwen3-0.6B --output-dir "$EXPORT_DIR" --overwrite
)

rm -rf "$CACHE_DIR.tmp"
mkdir -p "$CACHE_DIR.tmp"

shopt -s dotglob nullglob
entries=("$EXPORT_DIR"/*)
if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
  cp -R "${entries[0]}"/. "$CACHE_DIR.tmp"/
else
  cp -R "$EXPORT_DIR"/. "$CACHE_DIR.tmp"/
fi
shopt -u dotglob nullglob

rm -rf "$CACHE_DIR"
mv "$CACHE_DIR.tmp" "$CACHE_DIR"

echo "Seeded Qwen3 0.6B macOS model cache: $CACHE_DIR"
