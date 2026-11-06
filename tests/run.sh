#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
node --test tests/model.test.cjs tests/i18n.test.cjs
bash tests/kit-check.sh
omarchy-plugin-validate "$PWD"
python3 tests/i18n-runtime.py
python3 tests/runtime.py
