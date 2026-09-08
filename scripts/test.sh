#!/usr/bin/env bash
# Run lint and the test suite.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bash scripts/lint.sh
bash tests/run.sh "$@"
