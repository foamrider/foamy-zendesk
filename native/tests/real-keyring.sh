#!/bin/sh
# Run by keyring.rs inside a private `dbus-run-session` (temporary home and
# runtime directory, a bus with no activatable services, so no unlock
# prompter): a gnome-keyring of its own, unlocked with a throwaway password.
# Prints one "<step> <reply>" line per helper run, and "<step> <count>" for
# the matching items left. $1 is the helper.
set -u
helper=$1

# secret-tool <verb> [options] with the helper's attributes.
st() {
  verb=$1
  shift
  secret-tool "$verb" "$@" service foamy-zendesk host acme.zendesk.com client foamy
}
keyring() {
  printf throwaway | gnome-keyring-daemon "$@" --foreground --unlock --components=secrets >/dev/null 2>&1 &
}
# Until the command succeeds, at most 10 s.
until_ok() {
  i=0
  until "$@" >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -le 100 ] || return 1
    sleep 0.1
  done
}
step() {
  name=$1
  client=$2
  shift 2
  printf '%s %s\n' "$name" "$("$helper" "$@" --address acme --client-id "$client" 2>/dev/null | tail -n 1)"
}
left() {
  printf '%s %s\n' "$1" "$(st search --all 2>/dev/null | grep -c '^\[')"
}

keyring
first=$!
# `search` never prompts.
if ! until_ok st search; then
  echo "no-keyring"
  exit 1
fi
printf '{"access_token":"A1"}' | st store --label="Foamy Zendesk test"
step status-unlocked foamy auth-status
secret-tool lock
step logout-locked foamy auth-logout
left left-after-locked-logout
step status-locked foamy auth-status
step status-locked-none other auth-status
step logout-locked-none other auth-logout
# Unlock: a new daemon takes over the same keyrings with the password.
keyring --replace
second=$!
until_ok st lookup
step logout-unlocked foamy auth-logout
left left-after-logout
step status-after foamy auth-status
kill "$first" "$second" 2>/dev/null
exit 0
