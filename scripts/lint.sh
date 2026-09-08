#!/usr/bin/env bash
# Syntax-check and shellcheck every shell file in the plugin.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

files=(bin/mars lib/*.sh scripts/*.sh tests/run.sh tests/fakes/doctl tests/fakes/herdr)
status=0
for f in "${files[@]}"; do
  bash -n "$f" || status=1
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "${files[@]}" || status=1
else
  echo "shellcheck not found; skipped static analysis (install it for full lint coverage)." >&2
fi

if [[ "$status" -eq 0 ]]; then
  echo "lint: ok"
fi
exit "$status"
