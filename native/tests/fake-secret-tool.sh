#!/bin/sh
# A stand-in for `secret-tool` that answers as libsecret 0.21 with
# gnome-keyring does (checked against a real one in a private session, see
# real-keyring.sh). Its state is files next to it: `item` is the stored
# secret and `locked` locks its keyring, every unlock prompt dismissed.
# `search-fails` makes `search` fail and `lookup-dies` kills `lookup`.
# Each run's verb is appended to `log`.
d=$(dirname "$0")
echo "$1" >>"$d/log"
readable() { [ -f "$d/item" ] && [ ! -e "$d/locked" ]; }
case $1 in
  lookup)
    [ -e "$d/lookup-dies" ] && kill -9 $$
    # Not found and a dismissed unlock prompt look the same: exit 1, silent.
    if readable; then
      cat "$d/item"
      exit 0
    fi
    exit 1
    ;;
  clear)
    # Only unlocked items are removed, without a prompt.
    if readable; then
      rm "$d/item"
      exit 0
    fi
    exit 1
    ;;
  search)
    if [ -e "$d/search-fails" ]; then
      echo "secret-tool: The name is not activatable" >&2
      exit 1
    fi
    [ -f "$d/item" ] || exit 0
    echo "[/1]"
    echo "label = Foamy Zendesk (acme.zendesk.com)"
    if [ -e "$d/locked" ]; then
      echo "secret-tool: Cannot get secret of a locked object" >&2
    else
      printf 'secret = '
      cat "$d/item"
      echo
    fi
    echo "attribute.service = foamy-zendesk" >&2
    exit 0
    ;;
  store)
    if [ -e "$d/locked" ]; then
      echo "secret-tool: Cannot create an item in a locked collection" >&2
      exit 1
    fi
    cat >"$d/item"
    exit 0
    ;;
esac
exit 2
