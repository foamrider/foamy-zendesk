#!/bin/bash
# foamy-kit 0.13.0 05fa9e02cc75540ffebe65a09d1b40db5c0db8e008e3ca47f49060f3980f84a2 — do not edit; change foamy-kit and run sync
# Bounded clipboard read for a field that must never let Qt paste itself.
#
#   bash kit/clipboard.sh clipboard|primary [multiline]
#
# Prints the selection's text as one JSON string on stdout: line breaks as
# spaces, or with `multiline` (a multi-line field) as "\n" (CR LF, CR,
# U+2028 and U+2029 each become one "\n"). Exit 0 on success; 5 when the
# text is over 16 KiB or contains NUL; 137 when the 2 s deadline killed the
# read; 143 when the caller stopped it (TERM, INT or HUP: the whole read is
# killed); 2 for a bad argument; any other nonzero code when wl-paste failed
# (no Wayland display, nothing copied, no text type). Read stdout only after
# exit 0: a failed wl-paste still leaves "" there. Nothing is written to
# stderr.
set -euo pipefail

case ${1:-} in
  clipboard | primary)
    [[ $# == 1 || ($# == 2 && $2 == multiline) ]] || exit 2
    # Keep the watchdog separate: it still bounds the pipeline if Quickshell
    # kills this wrapper during reload/destruction. Kill the whole read-only
    # pipeline at its deadline, including a producer that ignores TERM.
    timeout --signal=KILL 2s bash "$0" _read "$@" &
    clipboard_job=$!
    trap 'kill -KILL -- "-$clipboard_job" 2>/dev/null || true; wait "$clipboard_job" 2>/dev/null || true; exit 143' TERM INT HUP
    wait "$clipboard_job" 2>/dev/null
    ;;
  _read)
    [[ ($# == 2 || ($# == 3 && $3 == multiline)) && ($2 == clipboard || $2 == primary) ]] || exit 2
    options=(--no-newline --type text)
    [[ $2 != primary ]] || options+=(--primary)
    multiline=false
    [[ ${3:-} != multiline ]] || multiline=true
    # Read one extra byte to reject oversized input instead of silently truncating it.
    wl-paste "${options[@]}" 2>/dev/null | head -c 16385 | jq -Rse --argjson multiline "$multiline" '
      if utf8bytelength > 16384 or contains("\u0000") then
        error("Clipboard text exceeds the limit or contains NUL")
      elif $multiline then
        gsub("\r\n|[\r\u2028\u2029]"; "\n")
      else
        gsub("[\r\n\u2028\u2029]"; " ")
      end
    ' 2>/dev/null
    ;;
  *) exit 2 ;;
esac
