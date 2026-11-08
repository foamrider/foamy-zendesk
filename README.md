# Foamy Zendesk

An Omarchy bar plugin for your Zendesk tickets: the unsolved tickets assigned
to you, and the unassigned ones in your groups. It signs in with OAuth and
reads only; nothing in Zendesk changes. No desktop notifications are used.

![Foamy Zendesk inbox with sample tickets assigned to you, unassigned in your groups and waiting on others](preview.png)

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
**Hide read tickets**). Read tickets stay listed, dimmed; their **Mark as
unread** button shows while the pointer or the keyboard cursor is on the
ticket. The header's **Mark all as read** marks every unread ticket; an
Undo link restores that batch. Viewing a ticket in Zendesk changes nothing.

Settings (the gear, `s`, or right-click the bar icon):

- **Hide read tickets** (off), **Show unread first** (off), and **Group
  waiting tickets** (on): Pending and On-hold tickets you have read move to a
  "Waiting on others" section at the end; a new reply brings them back up.
- **Use a weekly schedule**: per-day working hours (local time; overnight
  ranges carry into the next day), as in Foamy Train. Outside them nothing is
  fetched in the background and the bar icon dims without its count, or the
  widget hides (it stays while its popup is open). Opening the popup still
  refreshes the inbox, and **Refresh** works; the footer's refresh icon spins
  while it loads.
- **Zendesk** (at the bottom): the account, and **Check every** (1 to 15
  minutes, default 1). Signed out, it also holds the connection fields below.

If any monitor has an open ticket, a newer inbox waits until it closes (or
its panel does), so text and order stay stable while reading.

## Languages

English and Norwegian (`i18n/en.json`, `i18n/no.json`), following the
shell's language. Every text the panel shows is a catalog key, including the
helper's errors (only an internal failure passes on the system's own error
text): their varying details (an HTTP status, a port) follow the key after
U+001F separators and fill its `%1`, `%2`. `tests/i18n.test.cjs` checks that
both catalogs cover the plugin, the kit components, ticket statuses and
priorities, day names and the helper's errors (also those it takes from the
kit, such as `tls::UNSUPPORTED`, read from `kit/rust`), with matching
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
and, in or outside the schedule, when the popup opens on an inbox older than
30 seconds or on **Refresh**, the helper's `fetch`:

- searches `type:ticket status<solved assignee:me`, and
  `type:ticket status<solved assignee:none group:<id>` for each of your groups
  (up to 20 groups and 100 tickets; Zendesk's search can lag a few minutes
  behind);
- fetches the latest 20 comments only for tickets whose `updated_at` changed
  (at most 25 per run; the rest follow next run);
- looks up the names of assignees, requesters and comment authors in one call.

Failures back off (2×, 4×, … up to 15 minutes) and keep the last inbox. Read
markers live in `$XDG_STATE_HOME/foamy-zendesk/read-<account>.json` (private
directory); markers of tickets that left the inbox are kept 30 days.

Requirements: `secret-tool` (libsecret) with a running keyring (Omarchy's
gnome-keyring). HTTPS needs AES, carry-less multiply, AVX2, BMI2 and ADX on
x86-64 (Intel Broadwell, AMD Zen or newer), or the crypto extensions on ARMv8
(a Raspberry Pi 5, not a Pi 4); without them the panel says HTTPS isn't
supported on this CPU. The helper is `bin/<arch>/foamy-zendesk-helper`, built
from `native/` with the foamy-kit native toolchain; its contract is the
comment at the top of `native/src/main.rs`.

## Keyboard

Arrows or hjkl move a single cursor over the header actions, tickets and
their actions in on-screen order, then Refresh. Enter or Space activates,
Escape closes, and Tab switches shell panels. `r` refreshes, `m` shows every
comment of the ticket under the cursor in full, `u` undoes Mark all as read
and `s` opens settings.

IPC: `omarchy-shell foamy.zendesk <open|close|toggle|settings>`.

## Install

Requires Omarchy 4.5.

```sh
omarchy plugin add https://github.com/foamrider/foamy-zendesk.git --enable
```

To remove it, sign out first (that revokes the token and removes it from the
keyring), then run `omarchy plugin remove foamy.zendesk`. Read markers stay in
`$XDG_STATE_HOME/foamy-zendesk/`.

## Verifying the helper binaries

`bin/x86_64/foamy-zendesk-helper` and `bin/aarch64/foamy-zendesk-helper` are compiled from the Rust
source in this repository: `native/`, the shared crate in
`kit/rust/foamy-helper/`, the dependencies locked in `Cargo.lock` and the
toolchain pinned in `rust-toolchain.toml`. The build is reproducible, so you
can rebuild both binaries yourself and check that they are byte-identical to
the committed files.

`native/native.pin` records the foamy-kit release that built them (`kit`), the
Rust toolchain (`toolchain`), a hash of every build input (`source`) and the
SHA-256 of each binary. The rebuild uses that foamy-kit release's
`tools/build-native.sh`. You need `git`, `rustup`, Python 3.11 or newer and
`file`; Omarchy isn't needed.

```sh
git clone https://github.com/foamrider/foamy-zendesk.git
cd foamy-zendesk
pin=native/native.pin
rustup toolchain install "$(awk '$1 == "toolchain" { print $2 }' $pin)" \
  --profile minimal --target x86_64-unknown-linux-musl,aarch64-unknown-linux-musl
# foamy-kit 0.5.2 (`kit` in native.pin), at the commit its v0.5.2 tag names:
git clone https://github.com/foamrider/foamy-kit.git ../foamy-kit &&
  git -C ../foamy-kit checkout -q --detach cc3e46f0fae443701c81793cf9f49890b39b37c1 &&
  ../foamy-kit/tools/build-native.sh . --verify
```

The last command builds both binaries from scratch in `~/.cache/foamy-native/`
(nothing is written to the checkout) and compares them byte for byte with
`bin/`. It also checks that the kit files are unmodified copies of that
foamy-kit release and that `native.pin` matches the source. It ends with
`verify OK (foamy-zendesk-helper, <toolchain>, both arches reproducible)`; any
difference is reported with both hashes. `git -C ../foamy-kit describe --tags`
prints `v0.5.2`, the release `native.pin` names. To check a release the
marketplace lists, run `git checkout <commit>` right after `cd`.

<!-- Maintainers: when native.pin's kit changes, set the commit above to
     `git -C foamy-kit rev-parse v<kit>^{commit}`. -->

## License

Licensed under [MIT](LICENSE). Omarchy and Lucide notices are in
[kit/LICENSE-OMARCHY](kit/LICENSE-OMARCHY) and [kit/LICENSE-LUCIDE](kit/LICENSE-LUCIDE).
The Zendesk mark comes from [Simple Icons](https://github.com/simple-icons/simple-icons)
(CC0). Zendesk is a trademark of Zendesk, Inc.; this plugin is not affiliated
with or endorsed by Zendesk.

Provided **as is**, without warranty or guaranteed support. Use at your own risk.

## Validation

Uses the existing Quickshell, Node.js, Python and foamy-kit tools. The
runtime test isolates HOME, XDG paths and D-Bus, loads the real Panel, stores
and view offscreen, and runs the real helper (which finds no keyring there);
the inbox comes from `preview/Fixtures.js` (fictional tickets, used only by
the preview and tests) and ticket links go to a stub. The helper's own tests
use a fake Zendesk on loopback and an in-memory keyring; nothing touches a
real account.

```sh
bash tests/run.sh
KIT=../foamy-kit   # a foamy-kit checkout at the version in foamy-kit.lock
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
`FOAMY_KIT` overrides the kit path used by runtime tests (default: a sibling
`foamy-kit`, else `~/GitHub/Personal/foamy-kit`).

Shared components are copied from foamy-kit and pinned by `foamy-kit.lock`.
Change the kit source and sync; never edit its stamped copies here.

The tests run on Omarchy 4.5, the installed `/usr/share/omarchy/shell`
(`FOAMY_HOST_45` picks another 4.5 tree); `python3 tests/runtime.py 4.0` runs
only when `FOAMY_HOST_40` names a 4.0 shell tree and otherwise prints a SKIP
line. The installed Qt formatter
cannot process typed `void` IPC methods in `Panel.qml` (also true for existing
Foamy plugins); the runtime test loads and exercises that file without removing
its types.
