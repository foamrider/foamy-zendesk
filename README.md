# Foamy Zendesk

An Omarchy bar plugin for your Zendesk tickets: the unsolved tickets assigned
to you, and the unassigned ones in your groups. It signs in with OAuth and
reads only; nothing in Zendesk changes. No desktop notifications are used.

![Zendesk inbox](preview.png)

The bar shows the Zendesk icon followed by a red count of unread tickets,
like Teams. Click it to open the inbox: your tickets under **Assigned to
you**, then **Unassigned in your groups**. Unread tickets have an accent
rail, their status and priority (only when not Open or Normal), who wrote
last ("You" for your own replies) and the latest comment, with a footer
line: when (10:40 today, then Yesterday, a weekday or a date), the assignee
and the group. Read tickets take one line.

Click a ticket to open it; one ticket is open at a time. Its comments show
newest first: those that were unread and the one before them, long comments
clipped at six lines, and **Show earlier comments** for the rest (internal
notes labelled). Icon buttons in each title row offer **Mark as read** and
**View in Zendesk** (opens the ticket in the browser). Notices (Undo,
waiting updates) float in a bar above the footer, so they never move the
ticket being read. The footer shows the account, when the inbox was last
updated (or why it couldn't be, or when it tries again), and **Refresh**.

Zendesk has no per-agent read state, so reading is kept on this computer. A
ticket is unread while it has comments from someone else newer than when you
marked it read; your own replies never make it unread. **Opening a ticket
marks it read**: the count drops at once, while the open ticket keeps its
place and its "new" marks until it closes (then it moves, or hides with
**Hide read tickets**). Read tickets stay listed, dimmed, with **Mark as
unread**. The header's **Mark all as read** marks every unread ticket; an
Undo link restores that batch. Viewing a ticket in Zendesk changes nothing.

Settings (the gear, `s`, or right-click the bar icon):

- **Hide read tickets** (off), **Show unread first** (off), and **Group
  waiting tickets** (on): Pending and On-hold tickets you have read move to a
  "Waiting on others" section at the end; a new reply brings them back up.
- **Use a weekly schedule**: per-day working hours (local time; overnight
  ranges carry into the next day), as in Foamy Train. Outside them nothing is
  fetched and the bar icon dims without its count, or the widget hides (it
  stays while its popup is open).
- **Zendesk** (at the bottom): the account, and **Check every** (1 to 15
  minutes, default 1). Signed out, it also holds the connection fields below.

If any monitor has an open ticket, a newer inbox waits until it closes (or
its panel does), so text and order stay stable while reading.

## Languages

English and Norwegian (`i18n/en.json`, `i18n/no.json`), following the
shell's language. Every text the panel shows is a catalog key, including the
helper's errors: their varying details (an HTTP status, a port) follow the
key after U+001F separators and fill its `%1`, `%2`. `tests/i18n.test.cjs`
checks that both catalogs cover the plugin, the kit components, ticket
statuses and priorities, day names and the helper's errors, with matching
placeholders and no unused entries.

## Zendesk sign-in

OAuth only: the authorization code grant with PKCE for a **public** OAuth
client, so there is no client secret and no API token. Nothing about the
account is hard-coded:

- **Zendesk address**: `acme` or `acme.zendesk.com`.
- **OAuth client ID**: the client's unique identifier.
- **Redirect port**: empty means 47823 (shown as the placeholder). It must
  match the client's redirect URL, which the section shows.

A Zendesk admin creates the OAuth client once, in Admin Center › Apps and
integrations › APIs › OAuth clients: kind **Public**, redirect URL
`http://127.0.0.1:47823/callback` (or your port), allowed scope `read`.

**Sign in** (it saves fields still being typed) opens the browser; the helper
listens on `127.0.0.1` only, checks the `state` value, exchanges the code at
once and shows who is signed in. Tokens are stored in the Secret Service
keyring (through `secret-tool`), never in the plugin settings, a file or a
log; the panel only learns the outcome. Access tokens are refreshed when they
expire, and the new pair is stored before it is used (Zendesk invalidates the
old one). An expired refresh token shows "Sign-in expired". **Sign out**
revokes the token and removes it from the keyring.

## Fetching

Every minute (your **Check every**) while signed in and within the schedule,
and when the popup opens on an inbox older than 30 seconds, the helper's
`fetch`:

- searches `type:ticket status<solved assignee:me`, and
  `type:ticket status<solved assignee:none group:<id>` for each of your groups
  (Zendesk's search can lag a few minutes behind);
- fetches the latest 20 comments only for tickets whose `updated_at` changed
  (at most 25 per run; the rest follow next run);
- looks up the names of assignees, requesters and comment authors in one call.

Failures back off (2×, 4×, … up to 15 minutes) and keep the last inbox. Read
markers live in `$XDG_STATE_HOME/foamy-zendesk/read-<account>.json` (private
directory); markers of tickets that left the inbox are kept 30 days.

Requirements: `secret-tool` (libsecret) with a running keyring (Omarchy's
gnome-keyring), and an x86_64 CPU with AVX2/BMI2/ADX (Broadwell or Zen and
newer) or an aarch64 CPU with the ARMv8 crypto extensions for HTTPS. The
helper is `bin/<arch>/foamy-zendesk-helper`, built from `native/` with the
foamy-kit native toolchain; its contract is the comment at the top of
`native/src/main.rs`.

## Keyboard

Arrows or hjkl move a single cursor over the header actions, tickets and
their actions in on-screen order, then Refresh. Enter or Space activates,
Escape closes, and Tab switches shell panels. `r` refreshes, `m` shows every
comment of the ticket under the cursor in full, `u` undoes Mark all as read
and `s` opens settings.

## Local installation

For this local checkout, `~/.config/omarchy/plugins/foamy.zendesk` links to
`~/GitHub/Personal/foamy-zendesk`. Enable `foamy.zendesk` in the shell bar
using Omarchy's plugin/bar controls. Restart the shell after source changes;
the isolated tests below do not change the running desktop.

## Validation

Uses the existing Quickshell, Node.js, Python and foamy-kit tools. The
runtime test isolates HOME, XDG paths and D-Bus, loads the real Panel, stores
and view offscreen, and runs the real helper (which finds no keyring there);
the inbox comes from `preview/Fixtures.js` (fictional tickets, used only by
the preview and tests) and ticket links go to a stub. The helper's own tests
use a fake Zendesk on loopback and an in-memory keyring; nothing touches a
real account.

```sh
FOAMY_HOST_45=/usr/share/omarchy/shell bash tests/run.sh
KIT=../foamy-kit   # a checkout with the native-helpers toolchain (kit 0.5.0)
$KIT/tools/build-native.sh . --test     # fmt, clippy, cargo test
$KIT/tools/build-native.sh .            # rebuild bin/<arch>/ and native/native.pin
$KIT/tools/build-native.sh . --verify   # byte-identical clean rebuild
FOAMY_HOST_45=/usr/share/omarchy/shell python3 $KIT/preview/render.py . \
  --host 4.5 --out /tmp/foamy-zendesk-preview
```

The preview covers tickets (one read), expanded content, a waiting inbox,
Mark all as read, hidden read tickets, grouped waiting tickets, signed out,
loading, failed and offline states, an empty inbox, settings (signed in and
signed out), the schedule, outside the schedule, a narrow popup, keyboard
focus and scrolling. Render with `--theme light` to check the light palette.
`FOAMY_KIT` overrides the sibling kit path used by runtime tests.

Shared components are copied from foamy-kit and pinned by `foamy-kit.lock`.
Change the kit source and sync; never edit its stamped copies here.

Validated against the installed Omarchy 4.5 shell. The installed Qt formatter
cannot process typed `void` IPC methods in `Panel.qml` (also true for existing
Foamy plugins); the runtime test loads and exercises that file without removing
its types.
