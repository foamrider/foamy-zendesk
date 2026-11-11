#!/bin/bash
# foamy-zendesk's own tests; tests/validate.sh runs this after the linters.
#   --ci    no Quickshell, no Omarchy host: the node tests only
#   --fast  skip the offscreen runtime tests
# The helper's Rust tests are validate's `native` check.
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1
ci=0 fast=0
for arg in "$@"; do
  case $arg in
    --ci) ci=1 ;;
    --fast) fast=1 ;;
    *)
      echo "suite.sh: unknown argument $arg" >&2
      exit 2
      ;;
  esac
done
status=0
run() {
  echo "== $*"
  "$@" || status=1
}
skip() { echo "SKIP $*"; }
run node --test tests/model.test.cjs tests/i18n.test.cjs
if ((ci || fast)); then
  skip "the kit's preview/i18n_runtime.py and tests/runtime.py: offscreen Quickshell"
else
  # The sibling checkout, else the usual one (as tests/runtime.py finds it).
  kit=${FOAMY_KIT:-../foamy-kit}
  [ -d "$kit" ] || kit=$HOME/GitHub/Personal/foamy-kit
  run python3 "$kit/preview/i18n_runtime.py" .
  run python3 tests/runtime.py
fi
exit $status
