#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# The sibling checkout, else the usual one (as tests/runtime.py finds it).
kit="${FOAMY_KIT:-../foamy-kit}"
[ -d "$kit" ] || kit="$HOME/GitHub/Personal/foamy-kit"
node --test tests/model.test.cjs tests/i18n.test.cjs
bash tests/kit-check.sh
omarchy-plugin-validate "$PWD"
python3 "$kit/preview/i18n_runtime.py" .
python3 tests/runtime.py
