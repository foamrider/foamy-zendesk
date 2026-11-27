"""Run the real plugin, singletons and UI in foamy-kit's isolated offscreen shell.

The account check runs the real helper (the isolated session has no keyring,
so it reports that); the inbox is then filled from preview/Fixtures.js, as if
signed in, and tickets open in a fake xdg-open instead of a browser.

  python3 tests/runtime.py

The host is Omarchy 4.5, the installed /usr/share/omarchy/shell
(FOAMY_HOST_45 picks another 4.5 tree).
"""

import os
import shutil
import sys
from pathlib import Path

plugin = Path(__file__).resolve().parents[1]
# The sibling checkout, else the usual one (a worktree has no sibling kit).
kit = Path(
    os.environ.get("FOAMY_KIT")
    or next(
        (p for p in (plugin.parent / "foamy-kit", Path.home() / "GitHub/Personal/foamy-kit") if p.is_dir()),
        plugin.parent / "foamy-kit",
    )
)
# Set before the harness reads them.
os.environ.setdefault("FOAMY_HOST_45", "/usr/share/omarchy/shell")
sys.path.insert(0, str(kit / "preview"))
import harness

SHELL = r"""
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "harness"
import "plugin" as Plugin
import "plugin/kit" as Kit
import "plugin/kit/FoamyNative.js" as FoamyNative
import "plugin/preview/Fixtures.js" as Fixtures
import "plugin/Model.js" as Model
import "plugin/Status.js" as Status
import qs.Commons as Commons
ShellRoot {
  id: shell
  property int step: 0
  property real savedY: 0
  property string savedBody: ""
  property real savedScroll: 0
  property int frames: 0
  property int drawTarget: 0
  property bool finished: false
  property int fetchProbe: 0
  property int openBase: 0
  property int saves: 0
  property int saveBase: 0
  property var sent: []
  property var fetches: []
  property int statusRuns: 0
  // Ends of fetches and sign-outs, counted after the store or the account
  // applied the reply (their own handlers run first).
  property int fetchesEnded: 0
  property int fetchEndBase: 0
  property int signOutsEnded: 0
  property int signOutBase: 0
  // What the "failing" stand-in answers next (steps 63 to 67).
  property var fetchReply: null
  // The highest unread count since it was set to 0 (-1: not watched).
  property int maxUnread: -1
  property bool probeWindow: false
  property var windowResult: null
  property var cut: undefined
  // What the "big" stand-in says of ticket 9301 (steps 33 to 35): its first
  // comment, then a change whose comments are "deferred", then those comments.
  property string bigChange: ""
  // The saved address (steps 80 to 85), and what the address field showed
  // after a key typed while a sign-in waited (steps 81 and 82).
  property string savedAddress: ""
  property string typedWhileWaiting: ""
  // Step 9's parts, each after the frames of the last: a tall ticket opened,
  // the ticket below it clicked, its place checked.
  property int anchorPhase: 0
  // Step 59 ran up to the long inbox; the rest runs once it is laid out.
  property bool wideGrown: false
  property string anchorId: ""
  // Step 5 ran up to "Mark all as read"; the rest runs after the next frames.
  property bool undoShown: false
  readonly property string lockedSignOut: "Sign-out didn't finish: the keyring is locked, so the Zendesk sign-in is still stored. Unlock the keyring and sign out again."
  readonly property string lockedKeyring: "The keyring that holds the Zendesk sign-in is locked. Unlock it and try again."
  // The shell reflects saved settings back to every instance, like the host.
  // Wide is the default; the steps start in Small and switch to Wide later.
  property var entry: ({ panelWidth: "standard" })
  TestEvent { id: ev }
  FoamyWait { id: wait }
  // The fake xdg-open's log: every URL it was asked to open, in order.
  FileView { id: openLog; path: Quickshell.env("FOAMY_OUT") + "/opened.log"; blockAllReads: true; printErrors: false }
  function opened() { openLog.reload(); var text = openLog.text(); return text ? text.trim().split("\n") : []; }
  // What the fake xdg-open does next (see FAKE_OPENER).
  FileView { id: openerMode; path: Quickshell.env("FOAMY_OUT") + "/xdg-open.mode"; blockWrites: true; printErrors: false }
  FileView { id: openerRelease; path: Quickshell.env("FOAMY_OUT") + "/xdg-open.release"; blockWrites: true; printErrors: false }
  // Lets the "held" stand-in sign-in finish (see fake()).
  FileView { id: loginRelease; path: Quickshell.env("FOAMY_OUT") + "/login.release"; blockWrites: true; printErrors: false }
  // What the fake omarchy does (see FAKE_OMARCHY), and its release.
  FileView { id: omarchyMode; path: Quickshell.env("FOAMY_OUT") + "/omarchy.mode"; blockWrites: true; printErrors: false }
  FileView { id: omarchyRelease; path: Quickshell.env("FOAMY_OUT") + "/omarchy.release"; blockWrites: true; printErrors: false }
  // The theme's colors.toml (steps 93 to 103 switch it live), the kit's dark
  // theme with a dim red (2.70:1 on its background), and its light theme.
  FileView { id: themeFile; path: Kit.FoamyPalette.themePath; blockAllReads: true; blockWrites: true; printErrors: false }
  FileView { id: dimRed; path: Quickshell.env("FOAMY_OUT") + "/dim-red.toml"; blockLoading: true; printErrors: false }
  FileView { id: lightToml; path: Quickshell.env("FOAMY_OUT") + "/light.toml"; blockLoading: true; printErrors: false }
  // The theme before step 93 switched it: the file's text and its colours.
  property string savedTheme: ""
  property string savedColours: ""
  // Status words and marks under the cursor, by name, to compare at rest.
  property var underCursor: ({})
  function colours() {
    return [Commons.Color.background, Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent,
            Kit.FoamyPalette.background, Kit.FoamyPalette.error, Kit.FoamyPalette.warning, Kit.FoamyPalette.lightTheme].map(String).join();
  }
  // A theme switch as the host's applyTheme does: its colours, then the
  // theme's file that FoamyPalette watches. Only the run's own copy in its
  // temporary HOME may be written, never a real theme: checked on every write.
  function applyTheme(text) {
    var home = Quickshell.env("HOME");
    if (!check(home === Quickshell.env("FOAMY_OUT").replace(/\/out$/, "/home") && themeFile.path.indexOf(home + "/") === 0,
               "the theme file is in the run's temporary HOME (" + themeFile.path + ", HOME " + home + ")")) return false;
    Commons.Color.loadColors(text);
    themeFile.setText(text);
    return true;
  }
  // `item` (a text or an icon) shows, and reads at 4.5:1 on `surface`, the
  // opaque colour drawn under it; `old`, its colour before this change, does
  // not (else the theme proves nothing).
  function readsOn(name, item, surface, old) {
    if (!check(item && item.visible, name + " shows")) return false;
    var before = Kit.FoamyPalette.contrastRatio(old, surface);
    if (!check(before < 4.5, "the theme makes " + name + " fail in its old colour (" + old + " " + before.toFixed(2) + ":1 on " + surface + ")")) return false;
    var drawn = Kit.FoamyPalette.contrastRatio(item.color, surface);
    return check(drawn >= 4.5, name + " reads at 4.5:1 on what it is drawn on (" + item.color + " " + drawn.toFixed(2) + ":1 on " + surface + ")");
  }
  // Off the cursor, `item` keeps the colour saved under `name` and reads at
  // 4.5:1 on `surface`, the colour drawn under it at rest.
  function keeps(name, item, surface) {
    if (!check(Qt.colorEqual(item.color, underCursor[name]), name + " keeps its colour off the cursor (" + underCursor[name] + ", then " + item.color + ")")) return false;
    var drawn = Kit.FoamyPalette.contrastRatio(item.color, surface);
    return check(drawn >= 4.5, name + " reads at 4.5:1 at rest (" + item.color + " " + drawn.toFixed(2) + ":1 on " + surface + ")");
  }
  // The mock bar's inline save, while steps 92 and 93 save without it.
  property QtObject inlineSaves: null
  // The Omarchy language picker's file: writing it switches the language live.
  FileView { id: languageFile; path: Quickshell.env("OMARCHY_LANGUAGE_FILE"); blockWrites: true; printErrors: false }
  // Every View in Zendesk asked for has ended (launched or failed).
  function launchesDone() { return !Plugin.TicketStore.launching && Plugin.TicketStore.launches.length === 0; }
  function launchedOne() { return shell.opened().length > shell.openBase && shell.launchesDone(); }
  // A notification's button: the daemon runs its argv, `omarchy-shell -q
  // <target> <function> <argument>`, which calls that function of the
  // panel's IpcHandler. (`qs ipc` can't reach this shell when the temp path
  // is too long for a socket.)
  function press(argv) {
    if (!check(argv.length === 5 && argv[0] === "omarchy-shell" && argv[1] === "-q", "a button runs omarchy-shell (" + JSON.stringify(argv) + ")")) return false;
    // One handler per shell: the leading monitor's instance.
    var handlers = one.data.concat(two.data).filter(function(item) { return item.target === argv[2] && item.enabled && typeof item[argv[3]] === "function"; });
    if (!check(handlers.length === 1, "one panel answers " + argv[2] + " " + argv[3] + " (" + handlers.length + ")")) return false;
    var handler = handlers[0];
    handler[argv[3]](argv[4]);
    return true;
  }
  function actionsOf(argv) {
    var found = argv.find(function(arg) { return arg.indexOf("--hint=string:omarchy-actions:") === 0; });
    return JSON.parse(found.slice("--hint=string:omarchy-actions:".length));
  }
  Connections {
    target: Plugin.TicketStore.readFile
    function onSaved() { shell.saves++; }
  }
  Connections {
    target: Plugin.TicketStore.fetchProcess
    function onExited() { shell.fetchesEnded++; }
  }
  Connections {
    target: Plugin.ZendeskAccount.logoutProcess
    function onExited() { shell.signOutsEnded++; }
  }
  Connections {
    target: Plugin.TicketStore
    enabled: shell.maxUnread >= 0
    function onUnreadCountChanged() { shell.maxUnread = Math.max(shell.maxUnread, Plugin.TicketStore.unreadCount); }
  }
  // Each save the first panel's settings queue refused, as [key, value].
  property var refused: []
  Connections {
    target: one.prefs
    function onFailed(key, value) { shell.refused = shell.refused.concat([[key, value]]); }
  }
  // Quickshell ends a Process by dropping it (running is false), ending its
  // collectors' streams and only then emitting exited: a check() that runs
  // in between (here from the collector's streamFinished) finds no process
  // running while the last reply is still to be applied.
  Connections {
    target: Plugin.ZendeskAccount.statusProcess.stdout
    enabled: shell.probeWindow
    function onStreamFinished() {
      var account = Plugin.ZendeskAccount;
      shell.probeWindow = false;
      account.check();
      shell.windowResult = { running: account.statusProcess.running, again: account.checkAgain, busy: account.busy };
    }
  }
  // The notice bar's row for a save that failed ("" when there is none):
  // what was not saved, then that it is kept only until the shell restarts.
  // Read whether or not the popup is open, so not by the row's visibility.
  function saveNotice() {
    var row = find(one.popup.bodyItem, "saveError");
    return row && Plugin.TicketStore.saveError !== "" ? row.text : "";
  }
  readonly property string readMarkersLost: "Can't save read markers\nKept only until the shell restarts."
  readonly property string snoozeLost: "Can't save snooze or resume\nKept only until the shell restarts."
  function footer() {
    var view = one.popup.bodyItem;
    return view ? view.children.find(function(item) { return item.hasOwnProperty("statusError"); }) : null;
  }
  function find(item, name) {
    if (!item) return null;
    if (item.objectName === name) return item;
    for (var child of item.children) { var hit = find(child, name); if (hit) return hit; }
    return null;
  }
  // The settings page scrolled to its top, where the account section is.
  function toAccount(page) { page.flickable.contentY = 0; }
  // Whether all of the item shows in the page's scrolled view, so that a real click lands on it.
  function onPage(page, item) { var top = item.mapToItem(page.flickable, 0, 0).y; return item.visible && top >= 0 && top + item.height <= page.flickable.height; }
  // The sample inbox, with #4821's newest comment longer than the 12 lines an
  // open ticket shows of its newest unread comment, so the card cuts it.
  function longSample() {
    var list = Fixtures.tickets();
    var more = [];
    for (var i = 1; i <= 30; i++) more.push("Step " + i + ": I opened the project drive again and the VPN dropped within a few seconds, as before.");
    list[0].comments[0].body += "\n\n" + more.join("\n");
    return list;
  }
  // Draws the keys' cursor (FoamyCursor.byKeys): a cursor surface with its
  // 1 px accent border, an action with its border.
  function keysBorder(item) {
    if (!item.visible || !item.hasCursor) return false;
    if (item.borderSpec !== undefined) return item.byKeys && item.borderTop > 0 && Qt.colorEqual(item.borderSpec.color, item.accent);
    return item.border.width > 0;
  }
  // The objectNames (or "?") of the items under `item` that draw it.
  function keysBorders(item) {
    var found = [];
    (function walk(node) {
      if (node.hasCursor !== undefined && shell.keysBorder(node)) found.push(node.objectName || "?");
      for (var i = 0; i < node.children.length; i++) walk(node.children[i]);
    })(item);
    return found;
  }
  // ↓ from the stop before `first` to `last`: each stop on the way shows the
  // keys' border once. The stops where it doesn't, as "stop:index:borders".
  function keysWalk(view, first, last) {
    var bad = [];
    view.cursor.index = first - 1;
    for (var stop = first; stop <= last; stop++) {
      view.moveRequested(0, 1);
      var drawn = shell.keysBorders(view);
      if (view.cursor.index !== stop || drawn.length !== 1) bad.push(stop + ":" + view.cursor.index + ":" + drawn);
    }
    return bad;
  }
  function check(ok, message) {
    if (!ok && !shell.finished) { shell.finished = true; console.log("FOAMY FAIL " + message); Qt.quit(); }
    return ok;
  }
  // What step n waits for, as [condition, ms, label], beyond the frames
  // before every step: a process's exit and its reply, which take as long
  // as they take on a loaded machine.
  function gate(n) {
    var store = Plugin.TicketStore;
    var account = Plugin.ZendeskAccount;
    // The check's process can be gone a turn before its reply is applied,
    // while the state still says "checking".
    var checked = function() { return !account.busy && account.state !== "checking"; };
    switch (n) {
    case 1: return [checked, 30000, "auth-status finished"];
    // The header lays out its actions once the popup is shown (a 0 ms timer).
    case 2: return [function() { return one.popup.bodyItem && one.popup.bodyItem.band.settingsInMenu; }, 10000, "the popup's header laid out"];
    case 4: return [shell.launchedOne, 10000, "View in Zendesk launched"];
    case 12: return [function() { return shell.fetchProbe !== 1 || !store.fetchProcess.running; }, 30000, "the on-demand fetch finished"];
    case 16: return [shell.launchedOne, 10000, "this account's View in Zendesk launched"];
    case 17: return [checked, 30000, "the account check finished"];
    case 18: return [function() { return shell.fetches.length >= 2 && store.fetchProcess.running; }, 10000, "the new account's fetch started"];
    // The stopped fetch's exit starts the next account's fetch.
    case 19: return [function() { return shell.fetches.length >= 3; }, 10000, "the next account's fetch started"];
    case 20: return [function() { return store.loaded; }, 10000, "the new account's inbox arrived"];
    case 21: return [function() { return account.loginProcess.running; }, 10000, "the sign-in started"];
    case 22: return [function() { return checked() && account.state !== "waiting"; }, 10000, "the new address was checked"];
    case 23: return [function() { return store.loaded; }, 10000, "the inbox with an unreadable read file arrived"];
    case 24: return [function() { return shell.fetches.length !== shell.fetchProbe && !store.fetchProcess.running; }, 10000, "the next fetch finished"];
    case 26: return [function() { return shell.statusRuns >= 2 && !account.busy && account.user && account.user.name === "Check 2"; }, 10000, "both account checks finished"];
    case 28: return [function() { return store.loaded && one.popup.bodyItem; }, 10000, "the inbox with a read-only state folder arrived"];
    case 29: return [function() { return shell.saveNotice() === shell.readMarkersLost; }, 10000, "the failed save of the read markers is shown"];
    case 30: return [function() { return store.loaded && store.host === "unlocked.zendesk.com"; }, 10000, "the next account's inbox arrived"];
    case 31: return [function() { return shell.saveNotice() === shell.snoozeLost; }, 10000, "the failed save of the snooze is shown"];
    case 32: return [function() { return shell.saveNotice() !== shell.snoozeLost; }, 10000, "a snooze saved again clears it"];
    case 33: return [function() { return store.loaded && store.host === "big.zendesk.com"; }, 10000, "the cut-short inbox arrived"];
    case 34:
    case 35: return [function() { return shell.fetches.length > shell.fetchProbe && !store.fetchProcess.running; }, 10000, "the next fetch finished"];
    case 38:
    case 39: return [shell.launchedOne, 10000, "the popup's View in Zendesk ended"];
    case 40:
    case 41: return [shell.launchedOne, 10000, "the notification's View in Zendesk ended"];
    case 42: return [function() { return shell.opened().length >= shell.openBase + 3 && shell.launchesDone(); }, 10000, "the joined opens ended"];
    case 43: return [function() { return shell.opened().length >= shell.openBase + 9 && shell.launchesDone(); }, 20000, "the capped opens ended"];
    case 44: return [function() { return store.loaded && store.host === "lockable.zendesk.com" && shell.saves > shell.saveBase && !store.saveTimer.running; }, 10000, "the lockable inbox arrived and was saved"];
    case 45: return [function() { return shell.launchedOne() && shell.saves > shell.saveBase && !store.saveTimer.running; }, 10000, "the open was launched and its mark saved"];
    case 46: return [shell.launchedOne, 10000, "the read ticket's open ended"];
    case 47: return [function() { return shell.saves > shell.saveBase && !store.saveTimer.running; }, 10000, "Mark as unread was saved"];
    case 48: return [function() { return shell.launchesDone() && shell.saveNotice() === shell.readMarkersLost; }, 10000, "the open's failed save is shown"];
    case 49: return [function() { return store.loaded && store.host === "fresh.zendesk.com" && store.readReady; }, 10000, "the next account's inbox arrived"];
    case 50: return [shell.launchedOne, 10000, "the previous account's open ended"];
    case 52: return [function() { return !account.busy && account.error !== ""; }, 10000, "the sign-out finished"];
    case 53: return [checked, 10000, "the first check finished"];
    case 54: return [function() { return one.wide && !store.hideRead && !account.busy && !store.fetchProcess.running; }, 10000, "Wide was saved"];
    case 55: return [function() { return one.opened && one.popup.bodyItem.wide; }, 10000, "the Wide popup opened"];
    case 57: return [shell.launchedOne, 10000, "the pane's View in Zendesk launched"];
    case 58: return [function() { return store.pendingChanges === 0; }, 10000, "the waiting update came in"];
    case 60: return [function() { return !one.wide; }, 10000, "Small was saved"];
    case 62:
    case 63: return [function() { return !account.busy && shell.signOutsEnded > shell.signOutBase; }, 10000, "the sign-out finished"];
    case 64: return [function() { return store.loaded && store.host === "failing.zendesk.com" && !store.fetchProcess.running && !store.refreshAgain; }, 10000, "the failing account's inbox arrived"];
    case 65:
    case 66:
    case 67:
    case 68:
    case 69: return [function() { return shell.fetchesEnded > shell.fetchEndBase && !store.fetchProcess.running && !account.busy; }, 10000, "the next fetch finished"];
    case 70: return [function() { return store.loaded && store.host === "preread.zendesk.com" && store.readReady && !store.fetchProcess.running; }, 10000, "the inbox with an existing read file arrived"];
    // Saving Wide pushes the saved address back to the account, which checks it again.
    case 71: return [function() { return one.wide && !account.busy && !store.fetchProcess.running; }, 10000, "Wide was saved"];
    case 72: return [function() { return one.opened && one.popup.bodyItem.wide; }, 10000, "the Wide popup opened"];
    case 73: return [function() { return !one.wide && !account.busy && !store.fetchProcess.running; }, 10000, "Small was saved"];
    case 74: return [function() { return !account.busy; }, 10000, "the check finished"];
    case 75: return [function() { return shell.fetchesEnded > shell.fetchEndBase && !store.fetchProcess.running; }, 10000, "the fetch without a helper ended"];
    case 76: return [function() { return !account.busy; }, 10000, "the check without a helper ended"];
    case 77: return [function() { return Kit.FoamyI18n.language === "no"; }, 10000, "Norwegian was picked"];
    case 78: return [function() { return one.wide && !account.busy; }, 10000, "Wide was saved"];
    case 79: return [function() { return one.opened && one.popup.bodyItem.wide; }, 10000, "the Wide popup opened"];
    case 81: return [function() { return account.loginProcess.running; }, 10000, "the sign-in from Settings started"];
    case 82: return [function() { return checked() && account.state !== "waiting"; }, 10000, "the sign-in from Settings ended"];
    case 84: return [function() { return account.loginProcess.running; }, 10000, "the sign-in to cancel started"];
    case 85: return [function() { return !account.busy && account.state === "signed_out"; }, 10000, "the cancelled sign-in ended"];
    // The settings page's glide (FoamyMotion.slider) has ended.
    case 90:
    case 91:
    case 92: return [function() { return isNaN(one.popup.bodyItem.settingsPage.wheel.destination); }, 10000, "the Zendesk section was scrolled into view"];
    // Both CLI saves failed, and the account checks that their values asked for ended.
    case 93: return [function() { return !one.prefs.busy && checked(); }, 10000, "the held save and the address after it ended"];
    case 94: return [function() { return Kit.FoamyPalette.error.toString() === "#a54242" && Commons.Color.urgent.toString() === "#a54242"; }, 10000, "the dim red theme was read"];
    case 96: return [function() { return Kit.FoamyPalette.lightTheme && Kit.FoamyPalette.warning.toString() === "#df8e1d" && Commons.Color.background.toString() === "#eff1f5"; }, 10000, "the light theme was read"];
    case 101: return [function() { return !one.wide; }, 10000, "Small was saved"];
    case 104: return [function() { return shell.colours() === shell.savedColours; }, 10000, "the theme from before step 93 was read again"];
    }
    return null;
  }
  // Two frames, so layouts and deferred calls of the last step are done,
  // then the next step's gate, then the step.
  function advance() {
    if (shell.finished) return;
    if (!frameProbe.Window.window) {
      wait.waitFor(function() { return frameProbe.Window.window; }, 10000, function(ok) { if (check(ok, "the window exists")) shell.advance(); });
      return;
    }
    shell.drawTarget = shell.frames + 2;
    frameProbe.Window.window.update();
    wait.waitFor(function() { return shell.frames >= shell.drawTarget; }, 10000, function(ok) {
      if (!check(ok, "step " + shell.step + ": frames were drawn")) return;
      var gate = shell.gate(shell.step) || [function() { return true; }, 0, ""];
      wait.waitFor(gate[0], gate[1], function(ready) {
        if (!check(ready, gate[2] + ": not true after " + gate[1] + " ms")) return;
        shell.run();
        shell.advance();
      });
    });
  }
  // A stand-in helper: "now" replies at once, "slow" after a second;
  // "late" replies only when stopped (a full reply already on its way),
  // "stopped" then exits 143 with nothing; "held" replies once the test
  // writes login.release (without it, it exits 124 after 10 s).
  function fake(mode, reply) {
    var script = mode === "now" ? "printf '%s\\n' \"$1\""
      : mode === "slow" ? "sleep 1; printf '%s\\n' \"$1\""
      : mode === "held" ? "i=0; while [ ! -e \"$FOAMY_OUT/login.release\" ] && [ \"$i\" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; [ -e \"$FOAMY_OUT/login.release\" ] || exit 124; printf '%s\\n' \"$1\""
      : "trap 'kill $! 2>/dev/null; " + (mode === "late" ? "printf \"%s\\n\" \"$1\"; exit 0" : "exit 143") + "' TERM; sleep 30 & wait";
    return ["sh", "-c", script, "fake", JSON.stringify(reply)];
  }
  function inboxReply(address, id) {
    return { ok: true, state_path: Quickshell.env("FOAMY_OUT") + "/read-" + address + ".json",
             tickets: [{ id: String(id), subject: "Ticket " + id, status: "Open", priority: "Normal", assignee: "Alex", mine: true,
                         group: "IT support", requester: "Jonas", updated_at: "2026-11-06T10:00:00Z",
                         comments: [{ id: id * 10, author: "Jonas", mine: false, public: true, created: Fixtures.BASE, body: "Hello." }] }] };
  }
  // Zendesk's comment ids exceed an int (steps 60 and 72).
  readonly property double bigId: 31234567890123
  function bigTicket(comments, updated) {
    return [{ id: "7001", subject: "Large comment ids", status: "Open", priority: "Normal", assignee: "Alex", mine: true,
              group: "IT support", requester: "Ola", updated_at: updated, comments: comments }];
  }
  function bigComment(id, minutesAgo) {
    return { id: id, author: "Ola", mine: false, public: true, created: Fixtures.BASE - minutesAgo * 60000, body: "Comment " + id };
  }
  function many() {
    var list = shell.longSample();
    for (var i = 1; i <= 10; i++) list = list.concat([Fixtures.update(i, true)[0]]);
    return list;
  }
  FloatingWindow {
    implicitWidth: 1920; implicitHeight: 1080
    ScreenSim { }
    Item {
      id: frameProbe
      Connections {
        target: frameProbe.Window.window
        function onFrameSwapped() {
          shell.frames++;
          // advance() asks for frames up to drawTarget, one request each.
          if (shell.frames < shell.drawTarget) frameProbe.Window.window.update();
        }
      }
    }
    Plugin.Panel { id: one; settings: shell.entry; x: 1400; y: 4; width: 45; height: 26 }
    Plugin.Panel { id: two; settings: shell.entry; x: 1450; y: 4; width: 45; height: 26 }
  }
  MockBar {
    id: bar
    onSavedChanged: if (saved.length) shell.entry = saved[saved.length - 1].settings
  }
  Component.onCompleted: {
    for (var panel of [one, two]) { panel.bar = bar; panel.moduleName = "foamy.zendesk"; }
    shell.advance();
  }
  function run() {
    var store = Plugin.TicketStore;
    var account = Plugin.ZendeskAccount;
    var view = one.popup.bodyItem;
    var button = one.children.find(function(item) { return item.objectName === "zendeskButton"; });
    switch (shell.step++) {
    case 0:
      if (!check(one.popup.bodyItem === null && store.count === 0 && !store.loaded, "lazy popup, empty inbox before signing in")) return;
      if (!check(Kit.FoamyShared.memberCount("zendesk") === 2, "two monitor instances share state")) return;
      if (!check(account.state === "not_configured" && account.port === 47823, "not connected; an empty redirect port means the default port")) return;
      if (!check(!one.barContent.countLabel.visible && button.tooltipText.indexOf("not signed in") >= 0, "no count while signed out")) return;
      // A panel whose Size was never set opens Wide.
      var fresh = Qt.createComponent(Qt.resolvedUrl("plugin/Panel.qml")).createObject(one.parent, { settings: ({}), x: 1500, y: 4, width: 45, height: 26 });
      fresh.bar = bar;
      var freshWide = fresh.wide;
      fresh.destroy();
      if (!check(freshWide, "Wide is the default size")) return;
      one.prefs.save("zendeskAddress", "acme");
      one.prefs.save("oauthClientId", "foamy-test");
      break;
    case 1:
      // The real helper runs; the isolated session has no keyring, so it says so.
      if (!check(account.state === "error" && account.error.indexOf("keyring") >= 0, "a missing keyring is explained (" + account.state + ": " + account.error + ")")) return;
      if (!check(!store.active, "nothing is fetched without a sign-in")) return;
      // The bar says so without the popup: a warning sign, and the tooltip.
      if (!check(button.trouble === "signin" && one.barContent.troubleSign.visible && button.tooltipText === "Zendesk — can't sign in",
                 "a sign-in that can't be read marks the bar button (" + button.trouble + ", " + button.tooltipText + ")")) return;
      // From here on: signed in, with the sample inbox.
      store.loadFixtures(shell.longSample());
      account.state = "signed_in";
      account.user = { name: "Alex", email: "alex@acme.example" };
      if (!check(store.count === 3 && store.unreadCount === 3, "fixture inbox loaded")) return;
      if (!check(one.barContent.countLabel.visible && one.barContent.countLabel.text === "3" && one.barContent.icon.known
                 && one.barContent.countLabel.color == bar.urgent && one.barContent.icon.color == button.foreground, "bar badge counts unread tickets")) return;
      button.grabToImage(function(result) { result.saveToFile(Quickshell.env("FOAMY_OUT") + "/bar.png"); });
      button.triggerPress(Qt.LeftButton);
      break;
    case 2:
      if (!check(view !== null && view.repeater.count === 3, "real popup loads ticket cards")) return;
      // Rows are dated against the wall clock, or the preview's fixed time.
      var dated = shell.find(view, "ticket-4824");
      if (!check(dated !== null && Math.abs(dated.now - Date.now()) < 120000, "rows date against the wall clock")) return;
      view.fixedNow = Fixtures.NOW;
      // #4824's comment is from the day before NOW, #4821's from the same day.
      var datedLabel = shell.find(dated, "when").text;
      var todayLabel = shell.find(shell.find(view, "ticket-4821"), "when").text;
      if (!check(dated.now === Fixtures.NOW && datedLabel === "Yesterday" && todayLabel === Qt.formatDateTime(new Date(Fixtures.BASE), "HH:mm"),
                 "a fixed time dates the rows (" + datedLabel + ", " + todayLabel + ")")) return;
      view.fixedNow = 0;
      if (!check(Math.abs(dated.now - Date.now()) < 120000, "back on the wall clock")) return;
      if (!check(shell.find(view, "emptyState").visible === false && view.band.meta.indexOf("3 unread") === 0, "header counts unread")) return;
      if (!check(view.band.settingsInMenu && view.band.menuItems[0].iconName === "moon" && view.band.menuItems[0].text === "Snooze until tomorrow",
                 "Snooze and Settings are in the ⋯ menu")) return;
      // Opened with the pointer: no keys' border until a key moves the cursor.
      if (!check(shell.keysBorders(view).length === 0, "opened, no element shows the keys' border (" + shell.keysBorders(view) + ")")) return;
      view.moveRequested(0, 1);
      var markAll = shell.find(view, "markAllRead");
      if (!check(view.cursor.index === view.markAllStop && shell.keysBorder(markAll) && shell.keysBorders(view).length === 1,
                 "↓: Mark all as read shows the keys' border, nothing else (" + shell.keysBorders(view) + ")")) return;
      for (var m = 0; m < 2; m++) view.moveRequested(0, 1);
      if (!check(view.cursor.index === view.firstTicketStop, "keyboard walks Mark all and ⋯ before tickets")) return;
      var closed = view.repeater.itemAt(0);
      if (!check(shell.keysBorder(closed.bodyItem) && shell.keysBorders(view).length === 1, "↓ onto a ticket: its card shows the keys' border (" + shell.keysBorders(view) + ")")) return;
      view.moveRequested(0, 1);
      if (!check(shell.keysBorder(closed.readButton) && shell.keysBorders(view).length === 1, "↓ onto its read action: the action shows the keys' border (" + shell.keysBorders(view) + ")")) return;
      // The pointer onto another ticket: the cursor there, no keys' border anywhere.
      var pointed = view.repeater.itemAt(1).bodyItem;
      ev.mouseMove(pointed, pointed.width / 3, pointed.height / 2, -1, Qt.NoButton, Qt.NoModifier);
      if (!check(view.cursor.index === view.firstTicketStop + view.stopsPerTicket && pointed.hasCursor && shell.keysBorders(view).length === 0,
                 "the pointer on the next ticket: the cursor there, no keys' border (" + JSON.stringify([view.cursor.index, shell.keysBorders(view)]) + ")")) return;
      // The pointer off the stops again, so it takes no cursor in later steps.
      ev.mouseMove(view.band, 10, 10, -1, Qt.NoButton, Qt.NoModifier);
      // Every stop from the keys, the band's ⋯ and the footer's Refresh too.
      var walked = shell.keysWalk(view, 0, view.refreshStop);
      if (!check(walked.length === 0, "↓ through every stop: each shows the keys' border once (" + walked + ")")) return;
      view.cursor.index = view.firstTicketStop;
      if (!check(closed.unreadDot.visible && !closed.frameItem.visible && closed.bodyItem.height === closed.bodyItem.parent.height,
                 "closed, an unread ticket has the dot and the whole card is its target")) return;
      // #4821 is Open and High, #4818 Pending, #4824 New and Normal; all unread.
      var tag = shell.find(closed, "statusTag");
      var waiting = shell.find(view, "ticket-4818");
      var fresh = shell.find(view, "ticket-4824");
      // Zendesk's dark-UI colours (the harness theme is dark): Open, Pending, New.
      // In the list the tag is soft (a tint of the colour), its word in a
      // shade of the same colour that reads on the tint (4.5:1).
      var tint = Qt.tint(Kit.FoamyPalette.background, tag ? tag.color : "transparent");
      // The triangle: the tag's hue, stepped until it reads on the row under the cursor.
      var triangle = shell.find(closed, "disclosure");
      if (!check(tag !== null && tag.visible && tag.text === "Open" && tag.soft && Qt.colorEqual(tag.tone, "#eb5c69")
                 && Status.contrast(tag.ink, tint) >= 4.5
                 && Math.abs(triangle.color.hsvHue - tag.tone.hsvHue) < 0.02 && Kit.FoamyPalette.contrastRatio(triangle.color, Qt.tint(Kit.FoamyPalette.background, closed.bodyItem.color)) >= 4.5
                 && Qt.colorEqual(waiting.statusColor, "#2694d6") && Qt.colorEqual(fresh.statusColor, "#e38215")
                 && !Qt.colorEqual(waiting.statusColor, fresh.statusColor),
                 "an unread ticket shows its status as a soft tag in Zendesk's colour, the triangle in the same hue (" + triangle.color + ")")) return;
      // Light-UI fills: white beats black on Open and Pending (WCAG), black on New.
      var black = Qt.color("#000000"), white = Qt.color("#ffffff");
      if (!check(Qt.colorEqual(Status.inkOn(Qt.color("#cc3340"), black, white), white) && Qt.colorEqual(Status.inkOn(Qt.color("#1f73b7"), black, white), white)
                 && Qt.colorEqual(Status.inkOn(Qt.color("#ffa142"), black, white), black),
                 "a status tag's text is the candidate with the higher WCAG contrast")) return;
      if (!check(shell.find(closed, "priorityPill").visible && !shell.find(closed, "linePriority").visible && !shell.find(fresh, "priorityPill").visible
                 && closed.bodyItem.Accessible.name === "VPN disconnects after sign-in, Open, High, unread",
                 "High is labelled by the sender, Normal is not, and both are named for screen readers")) return;
      // A real click low on the closed card, on its latest comment, opens it.
      ev.mouseClick(closed.bodyItem, closed.bodyItem.width / 3, closed.bodyItem.height - 12, Qt.LeftButton, Qt.NoModifier, -1);
      break;
    case 3:
      var card = view.repeater.itemAt(0);
      if (!check(card.expanded && card.detailsItem.visible && store.reading, "click expands the ticket")) return;
      if (!check(card.commentItem.textFormat === Text.PlainText, "comments use plain text")) return;
      if (!check(card.historyRepeater.count === 4 && card.historyRepeater.itemAt(1).textItem.text.indexOf("restart the client") >= 0, "expanded history includes the agent's reply")) return;
      // One comment is unread: Alex's reply answered Anna's earlier one.
      if (!check(card.shownCount === 2 && !card.historyRepeater.itemAt(2).visible && card.moreButton.visible, "the timeline shows the unread comment and the one before it")) return;
      if (!check(card.frameItem.visible && !card.unreadDot.visible && card.bodyItem.height < card.height / 3, "open, the card is framed and its header band is the only toggle")) return;
      // Real clicks: none of these may collapse the ticket.
      var click = function(item, x, y) { ev.mouseClick(item, x === undefined ? item.width / 2 : x, y === undefined ? item.height / 2 : y, Qt.LeftButton, Qt.NoModifier, -1); };
      var longest = card.historyRepeater.itemAt(0);
      click(longest.textItem, 12, 6);
      click(shell.find(card, "cardFooter"), 12);
      if (!check(card.expanded, "clicks on a comment or the footer leave the ticket open")) return;
      if (!check(longest.clipped && shell.find(longest, "fade").visible && longest.lengthButton.visible && longest.lengthButton.text === "Show more"
                 && !card.historyRepeater.itemAt(1).lengthButton.visible, "a long comment is clipped and fades, with its own Show more")) return;
      click(longest.lengthButton);
      if (!check(card.expanded && longest.full && !longest.clipped && !shell.find(longest, "fade").visible && longest.lengthButton.text === "Show less"
                 && !card.historyRepeater.itemAt(1).full && card.shownCount === 2, "Show more expands only that comment")) return;
      click(longest.lengthButton);
      if (!check(card.expanded && !longest.full && longest.clipped && longest.lengthButton.text === "Show more", "Show less folds it back")) return;
      view.cursor.index = view.firstTicketStop;
      view.textKey("m", Qt.NoModifier);
      if (!check(card.expanded && longest.full && !card.showEarlier, "m shows the clipped comment in full first")) return;
      ev.mouseClick(card.moreButton, card.moreButton.width / 2, card.moreButton.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(card.expanded && card.showEarlier && card.historyRepeater.itemAt(3).visible && !card.moreButton.visible
                 && !card.historyRepeater.itemAt(3).full, "Show earlier lists the rest without expanding them, and the ticket stays open")) return;
      view.cursor.index = view.firstTicketStop;
      view.textKey("m", Qt.NoModifier);
      if (!check(card.expanded && card.showEarlier && longest.full && card.historyRepeater.itemAt(3).visible && !card.historyRepeater.itemAt(3).full,
                 "m with everything shown changes nothing")) return;
      if (!check(card.historyRepeater.itemAt(0).textItem.textFormat === Text.PlainText, "history uses plain text")) return;
      if (!check(card.read && store.unreadCount === 2 && one.barContent.countLabel.text === "2", "opening a ticket marks it read")) return;
      // The open card's header: the solid status tag, and both actions at
      // rest in their fixed slots at the end of the subject's line.
      var openTag = shell.find(card, "statusTag");
      if (!check(openTag.visible && !openTag.soft && card.readButton.opacity === 1 && card.readButton.iconName === "mail"
                 && Math.abs(card.readButton.mapToItem(card, card.readButton.width, 0).x - card.openButton.mapToItem(card, 0, 0).x) < 1,
                 "open, the header has the solid status tag and both actions at rest")) return;
      if (!check(shell.find(card, "cardAssignment").visible && shell.find(card, "cardAssignment").text === "Assigned to you"
                 && shell.find(card, "meta").text === "#4821 · Anna",
                 "open, the facts line names the requester, and the assignment stands at its end")) return;
      if (!check(card.openedUpdates === 1 && card.historyRepeater.itemAt(0).fresh && !card.historyRepeater.itemAt(1).fresh && !card.historyRepeater.itemAt(2).fresh,
                 "the opened ticket still marks what was new; my reply and what it answered never are")) return;
      if (!check(store.tickets.get(0).id === "4821" && view.repeater.itemAt(1).unreadDot.visible, "it stays in place; the next ticket still has its unread dot")) return;
      shell.savedY = card.mapToItem(view, 0, 0).y;
      shell.savedBody = card.commentItem.text;
      store.receive(Fixtures.update(1, false));
      card.openButton.clicked();
      break;
    case 4:
      var card = view.repeater.itemAt(0);
      if (!check(store.pending !== null && store.pendingChanges === 1 && card.historyRepeater.count === 4, "a new inbox waits while reading")) return;
      if (!check(card.mapToItem(view, 0, 0).y === shell.savedY && card.commentItem.text === shell.savedBody, "reading position and body remain stable")) return;
      if (!check(shell.find(view, "statusBar").visible, "waiting updates are announced without moving the ticket")) return;
      if (!check(shell.opened().length === 1 && shell.opened()[0] === "https://acme.zendesk.com/agent/tickets/4821" && card.expanded && card.read && store.notice === "",
                 "View opens the ticket in Zendesk; it stays open and read")) return;
      // The notice bar takes a click on its text: nothing under it reacts.
      var updatesText = shell.find(view, "updatesText");
      if (!check(updatesText.text === "1 update waiting" && shell.find(view, "showUpdates").visible, "the notice bar says an update waits, with Show")) return;
      ev.mouseClick(updatesText, 4, updatesText.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(card.expanded && store.pendingChanges === 1 && view.expandedIds.join() === "4821", "a click on the notice bar's text changes nothing")) return;
      // A real click on the header band (left of the actions) closes it.
      ev.mouseClick(card.bodyItem, card.bodyItem.width / 3, card.bodyItem.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      break;
    case 5:
      if (!shell.undoShown) {
        if (!check(store.pending === null && store.tickets.get(0).updates === 1 && store.tickets.get(0).history.count === 5, "collapse applies the waiting inbox; only the newer reply is unread")) return;
        if (!check(!view.repeater.itemAt(0).showEarlier, "collapsing forgets Show earlier")) return;
        view.repeater.itemAt(0).readButton.clicked();
        if (!check(store.count === 3 && store.unreadCount === 2 && view.repeater.itemAt(0).read && one.barContent.countLabel.text === "2", "Mark as read keeps the ticket and lowers the count")) return;
        if (!check(view.repeater.itemAt(0).compact && !view.repeater.itemAt(0).unreadDot.visible && shell.find(view.repeater.itemAt(0), "sender").text === "Anna ·"
                   && shell.find(view.repeater.itemAt(0), "when").visible && shell.find(view.repeater.itemAt(0), "when").text !== "",
                   "a read ticket takes one line: no unread dot, the sender and time by the subject")) return;
        // A narrow popup (320 px): an Urgent one-line ticket from a long name
        // leaves the requester out; the subject keeps the rest, the triangle its room.
        var probe = Qt.createComponent(Qt.resolvedUrl("plugin/TicketRow.qml")).createObject(view, {
          width: 272, compact: true, now: Fixtures.NOW,
          ticket: { id: "9900", subject: "Printer on the third floor jams on every job", status: "Open", priority: "Urgent",
                    sender: "Christopher Anderson", requester: "Christopher Anderson", senderMine: false, received: Fixtures.BASE - 26 * 3600000, read: true, updates: 0, since: 0,
                    history: null, body: "", mine: false, unassigned: true, assignee: "", group: "" } });
        // Rows lay out on the next frame; do it now to measure.
        shell.find(probe, "trailing").forceLayout();
        shell.find(probe, "lead").forceLayout();
        var probeSubject = shell.find(probe, "subject");
        var probeSender = shell.find(probe, "sender");
        var leadX = shell.find(probe, "lead").x;
        var ok = probeSubject.width > 0 && probeSubject.width >= leadX - probeSubject.x - 9 && !probeSender.visible
                 && probe.readButton.mapToItem(probe, 0, 0).x > shell.find(probe, "disclosure").mapToItem(probe, 14, 0).x;
        probe.destroy();
        if (!check(ok, "a narrow one-line row leaves out the requester and keeps the subject visible")) return;
        var oneLine = view.repeater.itemAt(0);
        if (!check(!shell.find(oneLine, "statusTag").visible && shell.find(oneLine, "linePriority").visible
                   && Math.abs(shell.find(oneLine, "disclosure").color.hsvHue - Qt.color("#eb5c69").hsvHue) < 0.02,
                   "a one-line ticket shows its status only by the triangle's colour (" + shell.find(oneLine, "disclosure").color + "), and its priority by the sender")) return;
        view.cursor.reset();
        if (!check(!view.repeater.itemAt(0).readActionShown && view.repeater.itemAt(1).readActionShown && view.repeater.itemAt(0).readButton.visible,
                   "Mark as unread waits for hover, keeping its place; Mark as read stays shown")) return;
        view.cursor.index = view.firstTicketStop + 1;
        if (!check(view.repeater.itemAt(0).readActionShown, "the keyboard cursor shows Mark as unread")) return;
        view.repeater.itemAt(0).readButton.clicked();
        if (!check(store.unreadCount === 3 && !view.repeater.itemAt(0).read && view.repeater.itemAt(0).unread === 1, "Mark as unread brings back the newest reply")) return;
        view.markAllRead();
        if (!check(store.count === 3 && store.unreadCount === 0 && store.canUndoMarkAll && !one.barContent.countLabel.visible, "Mark all as read keeps every ticket")) return;
        // The notice bar comes and the popup grows with it: Undo is clicked
        // once that is drawn.
        shell.undoShown = true;
        shell.step--;
        return;
      }
      view.cursor.index = view.settingsStop;
      view.moveRequested(0, -1);
      if (!check(view.cursor.index !== view.markAllStop, "keyboard skips the disabled Mark all")) return;
      var undo = shell.find(view, "undoMarkAll");
      if (!check(shell.find(view, "statusText").text === "3 marked as read" && undo.visible, "Mark all as read says so, with Undo")) return;
      ev.mouseClick(undo, undo.width / 2, undo.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(store.unreadCount === 3 && !store.canUndoMarkAll, "Undo restores the batch")) return;
      view.cursor.index = view.firstTicketStop;
      view.activateRequested();
      break;
    case 6:
      if (!check(view.repeater.itemAt(0).expanded && store.tickets.get(0).read, "keyboard activation opens the card and marks it read")) return;
      view.cursor.index = view.firstTicketStop + 1;
      view.activateRequested();
      if (!check(store.count === 3 && !store.tickets.get(0).read, "keyboard Mark as unread")) return;
      view.activateRequested();
      if (!check(store.tickets.get(0).read, "keyboard Mark as read")) return;
      view.toggleTicket("4824");
      if (!check(view.expandedIds.length === 1 && view.expandedIds[0] === "4824" && !view.repeater.itemAt(0).expanded && view.repeater.itemAt(2).expanded,
                 "opening a ticket closes the other one")) return;
      if (!check(view.cursor.index === view.firstTicketStop + 2 * 3 + 1, "the cursor follows the opened ticket")) return;
      view.toggleTicket("4824");
      store.markUnread("4824");
      one.prefs.save("hideRead", true);
      if (!check(store.count === 2 && store.unreadCount === 2, "hide read tickets")) return;
      view.cursor.index = view.firstTicketStop + 1;
      view.activateRequested();
      if (!check(store.count === 1 && view.cursor.index === view.firstTicketStop, "a hidden read ticket leaves; cursor stays on the next card")) return;
      var lastId = store.tickets.get(0).id;
      view.toggleTicket(lastId);
      if (!check(store.count === 1 && store.unreadCount === 0 && view.repeater.itemAt(0).expanded, "an opened ticket stays while read tickets are hidden")) return;
      view.toggleTicket(lastId);
      if (!check(store.count === 0 && view.expandedIds.length === 0, "closing it hides it")) return;
      one.prefs.save("hideRead", false);
      if (!check(store.count === 3, "showing read tickets again")) return;
      view.cursor.index = view.settingsStop;
      view.activateRequested();
      if (!check(view.band.menuOpen && view.blocked && !view.editingSettings, "Enter on ⋯ opens the menu, which takes the keys")) return;
      view.band.closeMenu();
      // The menu's Settings entry (last) goes through the band's settingsClicked.
      view.band.settingsClicked();
      if (!check(view.editingSettings && view.settingsPage.visible && !view.list.visible, "settings replace the inbox")) return;
      var toggle = shell.find(view.settingsPage, "hideReadToggle");
      if (!check(toggle && !toggle.checked, "Hide read tickets is off by default")) return;
      toggle.clicked();
      if (!check(store.hideRead && toggle.checked, "settings toggle hides read tickets")) return;
      var saved = bar.saved[bar.saved.length - 1];
      if (!check(saved && saved.id === "foamy.zendesk" && saved.settings.hideRead === true, "the setting is saved to the shell")) return;
      toggle.clicked();
      var grouping = shell.find(view.settingsPage, "groupWaitingToggle");
      if (!check(grouping && grouping.checked && store.groupWaiting, "grouping waiting tickets is on by default")) return;
      // Signed in: the connection fields step aside.
      if (!check(!shell.find(view.settingsPage, "addressField").visible && shell.find(view.settingsPage, "accountButton").text === "Sign out",
                 "signed in, the Zendesk section shows the account and Sign out")) return;
      view.settingsPage.back();
      if (!check(!view.editingSettings && view.list.visible && store.groupWaiting, "back returns to the inbox")) return;
      store.markUnread("4818");
      store.markUnread("4821");
      store.markUnread("4824");
      if (!check(store.firstWaitingIndex === -1, "unread Pending tickets are not grouped")) return;
      store.markRead("4818");
      if (!check(store.firstWaitingIndex === 2 && store.tickets.get(2).id === "4818" && store.waitingCount === 1, "a read Pending ticket moves to the end")) return;
      break;
    case 7:
      // Positioners lay out on the next frame (advance() waits for two).
      var waitingRow = view.repeater.itemAt(store.firstWaitingIndex);
      shell.savedY = view.repeater.itemAt(1).bodyItem.height;
      if (!check(waitingRow.compact && waitingRow.sectionHeader.visible && waitingRow.bodyItem.height < shell.savedY * 0.6, "waiting tickets are compact under a section header")) return;
      if (!check(view.repeater.itemAt(0).sectionTitle === "Assigned to you" && !view.repeater.itemAt(0).compact, "your unread tickets keep the full layout under their own header")) return;
      if (!check(view.repeater.itemAt(1).sectionTitle === "Unassigned in your groups" && view.repeater.itemAt(1).sectionHeader.visible, "unassigned tickets have their own section")) return;
      view.toggleTicket("4818");
      break;
    case 8:
      var waitingRow = view.repeater.itemAt(store.firstWaitingIndex);
      if (!check(waitingRow.bodyItem.parent.height >= shell.savedY && waitingRow.detailsItem.visible, "an expanded waiting ticket shows in full")) return;
      view.toggleTicket("4818");
      store.markUnread("4818");
      if (!check(store.firstWaitingIndex === -1 && store.tickets.get(1).id === "4818", "marking it unread brings it back up")) return;
      store.loadFixtures(shell.many());
      account.state = "signed_in";
      break;
    case 9:
      // Small, one ticket open and tall, the list scrolled: a click on the
      // ticket below it closes the first and opens the second, and the
      // second keeps its place in the view while the cards lay out.
      if (shell.anchorPhase === 0) {
        view.toggleTicket(store.tickets.get(0).id);
        // Everything shown: the card is taller than the list.
        for (var unfold = 0; unfold < 3; unfold++) view.repeater.itemAt(0).showMore();
        shell.anchorPhase = 1;
        shell.step--;
        return;
      }
      if (shell.anchorPhase === 1) {
        // Scrolled into the middle of the tall open card, its header band
        // stays at the top of the list's view.
        var tall = view.repeater.itemAt(0);
        view.list.contentY = view.rowTop(tall) + 300;
        var bandAt = tall.bodyItem.mapToItem(view.list, 0, 0).y;
        if (!check(tall.height > view.list.height && tall.pinned && bandAt >= 0 && bandAt <= 2,
                   "a long open ticket keeps its header at the top of the list (" + Math.round(bandAt) + " px)")) return;
        var below = view.repeater.itemAt(1);
        shell.anchorId = below.ticket.id;
        view.list.contentY = view.rowTop(below) - 140;
        if (!check(view.repeater.itemAt(0).height > 400 && Math.abs(view.rowTop(below) - view.list.contentY - 140) < 1, "a tall open ticket above the next one, scrolled")) return;
        ev.mouseClick(below.bodyItem, below.bodyItem.width / 3, Math.min(below.bodyItem.height / 2, 20), Qt.LeftButton, Qt.NoModifier, -1);
        shell.anchorPhase = 2;
        shell.step--;
        return;
      }
      if (shell.anchorPhase === 2) {
        var anchored = shell.find(view, "ticket-" + shell.anchorId);
        var shownAt = view.rowTop(anchored) - view.list.contentY;
        // In view, and no lower than it was: higher only as far as it takes to
        // show the whole card, or because the list reached its top (here, when
        // the tall card above closes).
        if (!check(anchored.expanded && !view.repeater.itemAt(0).expanded && shownAt >= 0 && shownAt <= 141,
                   "the ticket opened below an open one stays in view, near where it was (" + Math.round(shownAt) + " px from the top)")) return;
        view.toggleTicket(shell.anchorId);
        shell.anchorPhase = 3;
        shell.step--;
        return;
      }
      view.list.contentY = 0;
      if (!check(view.list.contentHeight > view.list.height && one.popup.contentHeight <= one.popup.availableCardHeight, "long inbox fits screen and scrolls")) return;
      view.cursor.index = view.firstTicketStop + (store.count - 1) * 3;
      view.reveal();
      if (!check(view.list.contentY > 0, "keyboard reveals offscreen card")) return;
      view.toggleTicket(store.tickets.get(store.count - 1).id);
      break;
    case 10:
      var last = view.repeater.itemAt(store.count - 1);
      shell.savedY = last.mapToItem(view, 0, 0).y;
      shell.savedScroll = view.list.contentY;
      if (!check(shell.savedScroll > 0 && store.reading, "scrolled to an expanded ticket")) return;
      store.receive(Fixtures.update(2, false).concat(shell.many().slice(3)));
      break;
    case 11:
      var last = view.repeater.itemAt(store.count - 1);
      if (!check(store.pendingChanges === 1 && shell.find(view, "statusBar").visible, "an update waits while reading a scrolled list")) return;
      if (!check(view.list.contentY === shell.savedScroll && last.mapToItem(view, 0, 0).y === shell.savedY, "the status bar never moves a scrolled ticket")) return;
      // Small: Show closes the ticket, which lets the update in, and goes to the top.
      var showSmall = shell.find(view, "showUpdates");
      ev.mouseClick(showSmall, showSmall.width / 2, showSmall.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(view.expandedIds.length === 0 && view.list.contentY === 0, "Show in Small closes the ticket and goes to the top")) return;
      one.close();
      break;
    case 12:
      if (!check(store.pendingChanges === 0 || shell.fetchProbe === 1, "the update that Show let in is applied")) return;
      if (shell.fetchProbe === 1) {
        // Let the on-demand fetch end (the isolated session has no keyring), then go back to the sample inbox.
        two.close();
        store.fixtures = true;
        store.error = "";
        store.failures = 0;
        store.loadFixtures(shell.many());
        shell.fetchProbe = 2;
      }
      if (!check(!store.reading && store.pending === null, "closing releases the waiting inbox")) return;
      one.prefs.save("scheduleEnabled", true);
      // The default week has no days, so the schedule is off right now.
      if (!check(!store.withinSchedule && button.dimmed && one.visible && two.visible && !store.active, "outside the schedule the widget dims and nothing is fetched")) return;
      if (shell.fetchProbe === 0) {
        // A real (non-sample) inbox outside the schedule: no background checks,
        // but opening the popup refreshes a stale inbox, with the footer's spinner.
        // The second monitor's popup has never been opened: its first open
        // builds the view with `active` already true, and must still refresh.
        store.fixtures = false;
        store.lastUpdated = 0;
        if (!check(store.connected && !store.active && !store.pollTimer.running, "outside the schedule nothing is checked in the background")) return;
        if (!check(two.popup.bodyItem === null, "the second popup was never opened")) return;
        two.open();
        if (!check(two.popup.bodyItem !== null && store.fetchProcess.running, "outside the schedule, the popup's first open refreshes on demand")) return;
        shell.fetchProbe = 1;
        shell.step--;
        return;
      }
      if (!check(!one.barContent.countLabel.visible && store.unreadCount > 0, "outside the schedule the bar shows no count")) return;
      one.prefs.save("scheduleOutsideMode", "hide");
      if (!check(!one.visible && !two.visible, "hide mode hides the widget")) return;
      one.open();
      if (!check(one.visible && !two.visible, "but not an open popup")) return;
      one.close();
      var today = ["scheduleSunday", "scheduleMonday", "scheduleTuesday", "scheduleWednesday", "scheduleThursday", "scheduleFriday", "scheduleSaturday"][new Date().getDay()];
      one.prefs.save(today, "00:00-24:00");
      if (!check(store.withinSchedule && one.visible && two.visible && !button.dimmed && one.barContent.countLabel.visible, "within the schedule the widget and count return")) return;
      var saved = bar.saved[bar.saved.length - 1].settings;
      if (!check(saved.scheduleEnabled === true && saved.scheduleOutsideMode === "hide" && saved[today] === "00:00-24:00", "schedule settings are saved together")) return;
      // Snooze: muted (here hidden) until tomorrow, without touching the settings.
      var savedCount = bar.saved.length;
      store.toggleSnooze();
      var midnight = new Date(); midnight.setHours(24, 0, 0, 0);
      if (!check(store.snoozed && !store.withinSchedule && !store.active && !one.visible && !two.visible, "snoozing mutes the widget and stops background checks")) return;
      if (!check(store.scheduleOverride.until === midnight.getTime(), "an all-day schedule snoozes until midnight")) return;
      if (!check(button.tooltipText === "Zendesk — snoozed", "the bar tooltip says snoozed")) return;
      store.toggleSnooze();
      if (!check(!store.snoozed && store.withinSchedule && store.scheduleOverride === null, "pressing again resumes the schedule")) return;
      if (!check(bar.saved.length === savedCount, "snoozing never saves settings")) return;
      one.prefs.save("scheduleEnabled", false);
      // Without a weekly schedule, only an override needs the clock: one that
      // runs out is dropped, and the clock stops with it.
      store.scheduleOverride = { on: false, until: Date.now() + 3600000 };
      if (!check(store.snoozed && store.clock.enabled, "a snooze runs the clock")) return;
      store.scheduleOverride = { on: false, until: Date.now() - 1 };
      if (!check(!store.snoozed, "a snooze that ran out no longer holds")) return;
      // Signed out: the inbox asks for a sign-in.
      account.state = "signed_out";
      store.loadFixtures(null);
      one.open();
      break;
    case 13:
      if (!check(store.scheduleOverride === null && !store.clock.enabled, "a snooze that ran out is dropped, and the clock stops")) return;
      var empty = shell.find(view, "emptyState");
      if (!check(empty.visible && empty.kind === "signed_out" && shell.find(view, "emptyTitle").text === "Signed out"
                 && shell.find(view, "emptyDetail").text === "Sign in again in the settings." && shell.find(view, "openSettings").visible
                 && !shell.find(view, "emptyAction").visible,
                 "signed out, the inbox says so and offers the settings")) return;
      // Each account state has its own action.
      var emptyAction = shell.find(view, "emptyAction");
      account.state = "expired";
      if (!check(emptyAction.visible && emptyAction.text === "Sign in" && !shell.find(view, "openSettings").visible && shell.find(view, "emptyTitle").text === "Sign-in expired",
                 "an expired sign-in offers Sign in")) return;
      account.state = "waiting";
      if (!check(emptyAction.visible && emptyAction.text === "Cancel" && shell.find(view, "emptyTitle").text === "Waiting for the browser…",
                 "a sign-in waiting for the browser offers Cancel")) return;
      account.state = "signed_out";
      var footer = view.children.find(function(item) { return item.hasOwnProperty("statusError"); });
      if (!check(!footer.visible && view.list.anchors.bottom === view.bottom, "signed out, there is no footer")) return;
      view.editingSettings = true;
      var signIn = shell.find(view.settingsPage, "accountButton");
      if (!check(shell.find(view.settingsPage, "addressField").visible && signIn.text === "Sign in", "signed out, the connection fields are back")) return;
      // Typed but not saved yet (no Enter, focus never left): Sign in still works.
      var typed = function(name, text) { var field = shell.find(view.settingsPage, name); field.dirty = true; field.field.text = text; };
      typed("clientIdField", "other-client");
      typed("portField", "80");
      if (!check(!signIn.actionEnabled, "an invalid port keeps Sign in off")) return;
      typed("portField", "48000");
      if (!check(signIn.actionEnabled && one.prefs.value("oauthClientId") === "foamy-test", "Sign in enables from typed values")) return;
      // Sign in saves the fields first (the test stops short of opening a browser).
      if (!check(view.settingsPage.saveConnection() && one.prefs.value("oauthClientId") === "other-client" && account.port === 48000, "typed connection fields save")) return;
      // Desktop notifications: off by default, then quiet while the inbox is open.
      var notifyMenu = shell.find(view.settingsPage, "notify");
      if (!check(notifyMenu && notifyMenu.value === "off" && store.notify === "off", "notifications are off by default")) return;
      shell.sent = [];
      store.sendNotification = function(argv) { shell.sent = shell.sent.concat([argv]); };
      store.loadFixtures(Fixtures.tickets());
      one.prefs.save("notify", "all");
      if (!check(store.notify === "all" && bar.saved[bar.saved.length - 1].settings.notify === "all", "the notification setting is saved")) return;
      store.receive(Fixtures.update(1, false));
      if (!check(store.watching && shell.sent.length === 0, "nothing is announced while the inbox is open")) return;
      one.close();
      break;
    case 14:
      if (!check(!store.watching, "a closed popup no longer holds notifications back")) return;
      store.receive(Fixtures.update(2, false));
      var argv = shell.sent[0] || [];
      var hint = function(name) {
        var found = argv.find(function(arg) { return arg.indexOf("--hint=string:" + name + ":") === 0; });
        return found ? JSON.parse(found.slice(("--hint=string:" + name + ":").length)) : null;
      };
      var tail = argv.slice(argv.indexOf("--") + 1);
      if (!check(shell.sent.length === 1 && argv[0] === "notify-send" && tail[0] === "VPN disconnects after sign-in"
                 && tail[1].indexOf("Anna: Follow-up 2: the VPN") === 0, "a new reply is announced with its subject and comment")) return;
      var buttons = hint("omarchy-actions") || [];
      if (!check(JSON.stringify(hint("omarchy-exec-argv")) === JSON.stringify(["omarchy-shell", "-q", "foamy.zendesk", "show", "acme.zendesk.com/4821"])
                 && buttons.length === 2 && buttons[0].label === "View in Zendesk" && buttons[1].label === "Mark as read"
                 && JSON.stringify(buttons[0].argv.slice(3)) === JSON.stringify(["viewInZendesk", "acme.zendesk.com/4821:48215"])
                 && JSON.stringify(buttons[1].argv.slice(3)) === JSON.stringify(["markRead", "acme.zendesk.com/4821:48215"]),
                 "a click opens it in the inbox; buttons view it in Zendesk or mark it read up to the reply shown, for this account")) return;
      var icon = argv.find(function(arg) { return arg.indexOf("--icon=") === 0; }) || "";
      if (!check(/\/icons\/zendesk\.png$/.test(icon) && icon.slice(7).charAt(0) === "/", "the Zendesk icon is a local PNG path")) return;
      // notify-send's --icon is the notification's image (image-path), which
      // history and stack headers treat as a picture; --app-icon is app_icon,
      // the field that names the sending app's icon there.
      var appIcon = argv.find(function(arg) { return arg.indexOf("--app-icon=") === 0; }) || "";
      if (!check(appIcon.slice("--app-icon=".length) === icon.slice("--icon=".length), "the Zendesk logo is also the notification's app icon")) return;
      // The buttons' IPC: a newer reply (here: after the one announced) stays unread.
      store.receive(Fixtures.update(3, false));
      shell.sent = shell.sent.slice(0, 1);
      if (!shell.press(buttons[1].argv)) return;
      if (!check(store.ticketById("4821").ticket.updates === 1, "Mark as read reads up to the reply shown")) return;
      if (!shell.press(["omarchy-shell", "-q", "foamy.zendesk", "markRead", "acme.zendesk.com/4821:48216,4824:48241,junk"])) return;
      if (!check(store.ticketById("4821").ticket.read && store.ticketById("4824").ticket.read, "Mark as read takes several tickets")) return;
      store.markUnread("4824");
      store.receive(Fixtures.update(2, false));
      if (!check(shell.sent.length === 1, "the same reply is announced once")) return;
      // In the shell's own JavaScript, not just Node's: long comments are cut short.
      var long = Fixtures.update(7, false);
      long[0].comments[0].body = new Array(80).join("word ") + "end";
      store.receive(long);
      tail = (shell.sent[1] || []).slice((shell.sent[1] || []).indexOf("--") + 1);
      if (!check(shell.sent.length === 2 && tail[1].length <= 280 && tail[1].length > 270 && tail[1].slice(-1) === "…",
                 "a long comment is cut short in the shell (" + shell.sent.length + ": " + tail[1] + ")")) return;
      shell.sent = shell.sent.slice(0, 1);
      one.prefs.save("notify", "mine");
      store.receive(Fixtures.update(3, true));
      if (!check(shell.sent.length === 1, "assigned to you only: a new unassigned ticket stays quiet")) return;
      one.prefs.save("notify", "all");
      store.receive(Fixtures.update(4, true).concat([Fixtures.update(5, true)[0]]));
      argv = shell.sent[1] || [];
      tail = argv.slice(argv.indexOf("--") + 1);
      if (!check(shell.sent.length === 2 && tail[0] === "2 updated Zendesk tickets" && hint("omarchy-actions").length === 1
                 && hint("omarchy-actions")[0].label === "Mark all as read" && hint("omarchy-actions")[0].argv[4] === "acme.zendesk.com/4905:49005,4904:49004"
                 && hint("omarchy-exec-argv")[3] === "open", "several at once are one notification that opens the inbox")) return;
      // Snoozed: a new reply (newer than any announced above) stays quiet.
      store.toggleSnooze();
      store.receive(Fixtures.update(8, false));
      if (!check(store.snoozed && shell.sent.length === 2, "snoozed: nothing is announced (" + shell.sent.length + ")")) return;
      store.toggleSnooze();
      // Off: a reply newer than any announced above stays quiet.
      one.prefs.save("notify", "off");
      store.receive(Fixtures.update(9, false));
      if (!check(shell.sent.length === 2, "off: nothing is announced")) return;
      // The notification's click (the show IPC): the inbox with that ticket open and read.
      var clickHint = "--hint=string:omarchy-exec-argv:";
      var click = JSON.parse(store.notificationCommand([store.state.tickets["4824"]]).find(function(arg) { return arg.indexOf(clickHint) === 0; }).slice(clickHint.length));
      if (!shell.press(click)) return;
      // The leading instance answers, whichever monitor that is.
      var shownBy = [one, two].filter(function(panel) { return panel.opened; });
      var shownView = shownBy.length === 1 ? shownBy[0].popup.bodyItem : null;
      if (!check(shownView && shownView.expandedIds.length === 1 && shownView.expandedIds[0] === "4824" && !shownView.editingSettings
                 && store.ticketById("4824").ticket.read, "show opens one inbox on the ticket and marks it read")) return;
      shownBy[0].close();
      break;
    case 15:
      // A first inbox of more than 25 changed tickets: the helper brings the
      // comments of 25 and defers the rest to later runs.
      var inbox = function(withComments) {
        var list = [];
        for (var i = 0; i < 30; i++) {
          var raw = { id: String(5000 + i), subject: "Ticket " + (5000 + i), status: "Open", priority: "Normal", assignee: "Alex", mine: true,
                      group: "IT support", requester: "Jonas", updated_at: "2026-11-06T10:00:00Z" };
          if (withComments(i)) raw.comments = [{ id: 50000 + i * 10, author: "Jonas", mine: false, public: true, created: Fixtures.BASE, body: "Old." }];
          else raw.deferred = true;
          list.push(raw);
        }
        return list;
      };
      if (!check(!store.watching, "the popup is closed again")) return;
      one.prefs.save("notify", "mine");
      shell.sent = [];
      store.loadFixtures(inbox(function(i) { return i < 25; }));
      store.receive(inbox(function() { return true; }));
      if (!check(shell.sent.length === 0 && store.unreadCount === 30, "the first inbox's deferred comments come later and are not announced")) return;
      var reply = inbox(function() { return true; });
      reply[27].comments.unshift({ id: 50271, author: "Jonas", mine: false, public: true, created: Date.now(), body: "Still broken." });
      store.receive(reply);
      tail = (shell.sent[0] || []).slice((shell.sent[0] || []).indexOf("--") + 1);
      if (!check(shell.sent.length === 1 && tail[0] === "Ticket 5027" && tail[1] === "Jonas: Still broken.", "a new reply on one of them is")) return;
      // Another account: the old notifications' click and buttons do nothing to it.
      one.prefs.save("zendeskAddress", "globex");
      if (!check(store.host === "globex.zendesk.com", "the inbox belongs to the new account")) return;
      store.loadFixtures(Fixtures.tickets());
      shell.openBase = shell.opened().length;
      store.markReadUpTo("acme.zendesk.com/4821:48299,4824:48241");
      store.viewInZendesk("acme.zendesk.com/4818:48181");
      store.markReadUpTo("4821:48213");
      store.viewInZendesk("4818:48181");
      if (!check(shell.launchesDone() && store.unreadCount === 3 && Object.keys(store.state.read).length === 0,
                 "another account's (or an older) notification marks nothing read and opens nothing")) return;
      one.showNotified("acme.zendesk.com/4824");
      if (!check(one.opened && view.expandedIds.length === 0 && !store.ticketById("4824").ticket.read, "its click opens only the inbox")) return;
      one.close();
      store.viewInZendesk("globex.zendesk.com/4818:48181");
      store.markReadUpTo("globex.zendesk.com/4824:48241");
      break;
    case 16:
      var globex = shell.opened().slice(shell.openBase);
      if (!check(globex.length === 1 && globex[0] === "https://globex.zendesk.com/agent/tickets/4818"
                 && store.ticketById("4818").ticket.read && store.ticketById("4824").ticket.read && store.unreadCount === 1,
                 "this account's notifications still work")) return;
      if (!check(!store.watching, "the popup is closed")) return;
      shell.sent = [];
      store.receive(Fixtures.update(1, false));
      var sentHint = function(name) {
        var found = (shell.sent[0] || []).find(function(arg) { return arg.indexOf("--hint=string:" + name + ":") === 0; });
        return found ? JSON.parse(found.slice(("--hint=string:" + name + ":").length)) : null;
      };
      if (!check(shell.sent.length === 1 && sentHint("omarchy-exec-argv")[4] === "globex.zendesk.com/4821"
                 && sentHint("omarchy-actions")[1].argv[4] === "globex.zendesk.com/4821:48214", "new notifications name the new account")) return;
      break;
    case 17:
      // Switching accounts mid-fetch: the old fetch's exit is ignored. The
      // helper is a stand-in from here on, inside the real timeout wrapper.
      // As in step 1, its gate waits for the account check's reply: one
      // applied after the fields set below would sign the stand-in accounts
      // out ("no keyring").
      store.helperCommand = function(args) {
        var address = args[args.indexOf("--address") + 1];
        shell.fetches = shell.fetches.concat([address]);
        return shell.fake({ dies: "stopped", late: "late", initech: "slow" }[address] || "now", shell.inboxReply(address, address === "late" ? 7001 : 8001));
      };
      store.fixtures = false;
      account.state = "signed_out";
      account.address = "dies";
      account.state = "signed_in";
      if (!check(store.active && store.fetchProcess.running && shell.fetches.length === 1 && !store.loaded && store.count === 0,
                 "signed in, the inbox is fetched")) return;
      account.address = "late";
      break;
    case 18:
      if (!check(store.error === "" && store.failures === 0 && store.retryAt === 0 && store.pollTimer.interval === store.refreshSeconds * 1000,
                 "a fetch stopped by an account switch (143) is no error and doubles no poll interval (" + store.error + ")")) return;
      account.address = "initech";
      break;
    case 19:
      // The previous account's full reply came in as it was stopped; its
      // exit started the next account's fetch (the gate waits for it).
      if (!check(shell.fetches.length === 3 && store.fetchProcess.running, "the next account's fetch is under way")) return;
      if (!check(store.count === 0 && !store.loaded && store.readPath === "" && store.error === "" && store.failures === 0,
                 "the previous account's late reply is ignored (" + store.count + " tickets, " + store.readPath + ")")) return;
      break;
    case 20:
      if (!check(store.count === 1 && store.tickets.get(0).id === "8001" && /\/read-initech\.json$/.test(store.readPath)
                 && store.error === "" && store.failures === 0, "only the new account's tickets and read markers")) return;
      // Another address mid sign-in: the stopped sign-in's reply is the old
      // address's; the new one gets its own check.
      account.helperCommand = function(args) {
        var who = args[args.indexOf("--address") + 1] === "newco" ? "New" : "Old";
        return shell.fake(args[0] === "auth-login" ? "late" : "now", { ok: true, state: "signed_in", verified: true, user: { name: who, email: who + "@example.invalid" } });
      };
      account.state = "signed_out";
      account.user = null;
      account.signIn();
      break;
    case 21:
      if (!check(account.state === "waiting" && account.loginProcess.running, "signing in waits for the browser")) return;
      account.configure({ address: "newco", clientId: account.clientId, port: account.port });
      break;
    case 22:
      if (!check(account.state === "signed_in" && account.user && account.user.name === "New" && account.address === "newco",
                 "a sign-in stopped by another address never signs that address in; the new address is checked (" + account.state + ", " + JSON.stringify(account.user) + ")")) return;
      // A read-state file that can't be read (the script made it write-only):
      // the inbox starts unread, and nothing is saved over the file (the
      // script checks it after the run).
      store.helperCommand = function(args) {
        var reply = shell.inboxReply("broken", 9001);
        shell.fetches = shell.fetches.concat(["broken"]);
        return shell.fake("now", reply);
      };
      account.address = "broken";
      break;
    case 23:
      if (!check(store.count === 1 && store.unreadCount === 1, "an unreadable read file starts the inbox unread")) return;
      store.markRead("9001");
      shell.fetchProbe = shell.fetches.length;
      store.refresh();
      break;
    case 24:
      if (!check(store.unreadCount === 0 && store.error === "", "the next fetch keeps what was read this session (" + store.unreadCount + " unread)")) return;
      if (!check(shell.saveNotice() === shell.readMarkersLost && !shell.footer().statusError && shell.footer().status === "Updated just now",
                 "the notice bar says the read markers can't be saved; the footer keeps the age (" + shell.saveNotice() + ")")) return;
      break;
    case 25:
      // An account check asked for while the last one's reply is on its way.
      account.helperCommand = function(args) {
        if (args[0] !== "auth-status") return ["false"];
        shell.statusRuns++;
        return shell.fake("now", { ok: true, state: "signed_in", verified: true, user: { name: "Check " + shell.statusRuns, email: "check@example.invalid" } });
      };
      shell.probeWindow = true;
      account.check();
      break;
    case 26:
      if (!check(shell.windowResult && !shell.windowResult.running && shell.windowResult.again && shell.windowResult.busy,
                 "a check asked for while the last reply is delivered waits for it, and the account stays busy (" + JSON.stringify(shell.windowResult) + ")")) return;
      if (!check(shell.statusRuns === 2 && account.state === "signed_in" && account.user.name === "Check 2", "then it runs once, and its own reply is the one shown")) return;
      // A state folder that can't be written (made read-only by the script).
      store.helperCommand = function(args) {
        var reply = shell.inboxReply("locked", 9101);
        reply.state_path = Quickshell.env("FOAMY_OUT") + "/locked/read-locked.json";
        return shell.fake("now", reply);
      };
      account.address = "locked";
      one.open();
      break;
    case 28:
      // Each inbox received is saved too (300 ms later), and fails here
      // whether or not this mark comes first.
      store.markRead("9101");
      break;
    case 29:
      if (!check(shell.saveNotice() === shell.readMarkersLost && store.unreadCount === 0,
                 "the notice bar says the read markers last only until the shell restarts; the ticket stays read")) return;
      // Then another account (its read file can be written) starts without it.
      one.popup.bodyItem.grabToImage(function(result) {
        result.saveToFile(Quickshell.env("FOAMY_OUT") + "/save-failed.png");
        store.helperCommand = function(args) { return shell.fake("now", shell.inboxReply("unlocked", 9201)); };
        account.address = "unlocked";
      });
      break;
    case 30:
      if (!check(shell.saveNotice() === "", "another account's inbox starts without the failure")) return;
      store.overridePath = Quickshell.env("FOAMY_OUT") + "/locked/schedule-override.json";
      store.toggleSnooze();
      break;
    case 31:
      if (!check(store.snoozed && shell.saveNotice() === shell.snoozeLost, "the snooze still holds, until the shell restarts")) return;
      store.overridePath = Quickshell.env("FOAMY_OUT") + "/schedule-override.json";
      store.toggleSnooze();
      break;
    case 32:
      if (!check(!store.snoozed && shell.saveNotice() === "", "resumed and saved, the notice is gone")) return;
      // An inbox the helper cut short says so below its last ticket.
      store.helperCommand = function(args) {
        var reply = shell.inboxReply("big", 9301);
        reply.truncated = shell.cut;
        var changed = reply.tickets[0];
        if (shell.bigChange !== "") changed.updated_at = "2026-11-06T10:05:00Z";
        if (shell.bigChange === "deferred") {
          delete changed.comments;
          changed.deferred = true;
        } else if (shell.bigChange === "reply")
          changed.comments.unshift({ id: 93011, author: "Jonas", mine: false, public: true, created: Fixtures.BASE + 300000, body: "Still broken." });
        shell.fetches = shell.fetches.concat(["big"]);
        return shell.fake("now", reply);
      };
      shell.cut = { tickets: true, groups: true };
      account.address = "big";
      break;
    case 33:
      var note = shell.find(view, "truncatedNote");
      if (!check(note && note.visible && note.text === "Showing the 100 most recently updated tickets", "the inbox says it shows the 100 most recently updated")) return;
      shell.cut = { tickets: false, groups: true };
      // Read, then changed with its comments deferred (the run's budget was spent).
      store.markRead("9301");
      shell.bigChange = "deferred";
      shell.fetchProbe = shell.fetches.length;
      view.grabToImage(function(result) { result.saveToFile(Quickshell.env("FOAMY_OUT") + "/truncated.png"); store.refresh(); });
      break;
    case 34:
      var groupsNote = shell.find(view, "truncatedNote");
      if (!check(groupsNote.visible && groupsNote.text === "Showing unassigned tickets from your first 20 groups", "or that only the first 20 groups were searched")) return;
      var stale = store.ticketById("9301").ticket;
      if (!check(stale.read && stale.history.count === 1 && stale.updatedAt === "2026-11-06T10:05:00Z",
                 "a deferred change keeps the earlier comments meanwhile (" + stale.history.count + ")")) return;
      shell.cut = undefined;
      shell.bigChange = "reply";
      shell.fetchProbe = shell.fetches.length;
      store.refresh();
      // What the helper is asked: the deferred ticket's comments again.
      var known = JSON.parse(store.fetchProcess.input).known;
      if (!check(!("9301" in known), "the next fetch asks for the deferred comments (" + JSON.stringify(known) + ")")) return;
      break;
    case 35:
      if (!check(!shell.find(view, "truncatedNote").visible, "a complete inbox has no note")) return;
      var caught = store.ticketById("9301").ticket;
      if (!check(!caught.read && caught.updates === 1 && caught.history.count === 2, "the deferred reply comes on the next fetch, unread")) return;
      // An agent may be called "Unassigned": the helper's flag says who has none.
      var named = Fixtures.update(8, true);
      named[0].assignee = "Unassigned";
      named[0].unassigned = false;
      store.loadFixtures(named);
      break;
    case 36:
      var footerOf = function(id) { return shell.find(view, "ticket-" + id).assignmentText; };
      if (!check(footerOf("4908") === "Assigned to Unassigned" && footerOf("4824") === "Unassigned",
                 "an agent named Unassigned is an assignee (" + footerOf("4908") + "; " + footerOf("4824") + ")")) return;
      // A ticket whose comments haven't come, marked read: it can be marked
      // unread again, which makes it unseen.
      var deferred = Fixtures.tickets();
      delete deferred[2].comments;
      deferred[2].deferred = true;
      store.loadFixtures(deferred);
      store.markRead("4824");
      var unloaded = shell.find(view, "ticket-4824");
      view.cursor.index = view.firstTicketStop + store.ticketById("4824").index * view.stopsPerTicket + 1;
      if (!check(unloaded.read && unloaded.readActionShown && unloaded.readButton.enabled, "a read ticket whose comments haven't come offers Mark as unread")) return;
      unloaded.readButton.clicked();
      if (!check(!store.ticketById("4824").ticket.read && store.ticketById("4824").ticket.unseen, "Mark as unread makes it unseen again")) return;
      store.loadFixtures(Fixtures.tickets());
      break;
    case 37:
      // View in Zendesk on a closed unread ticket: a real click, the fake xdg-open.
      var row = shell.find(view, "ticket-4821");
      if (!check(store.unreadCount === 3 && !row.read && !row.expanded && one.barContent.countLabel.text === "3", "three unread before opening any")) return;
      shell.openBase = shell.opened().length;
      ev.mouseClick(row.openButton, row.openButton.width / 2, row.openButton.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      break;
    case 38:
      var row = shell.find(view, "ticket-4821");
      if (!check(shell.opened().slice(shell.openBase).join() === "https://big.zendesk.com/agent/tickets/4821", "View in Zendesk opens the ticket's page")) return;
      if (!check(row.read && !row.expanded && store.unreadCount === 2 && one.barContent.countLabel.text === "2" && store.notice === "",
                 "opening it in Zendesk marks it read: the count and the bar drop, the card stays closed")) return;
      // xdg-open fails (no handler): nothing is marked, and the inbox says so.
      openerMode.setText("fail\n");
      shell.openBase = shell.opened().length;
      var other = shell.find(view, "ticket-4824");
      ev.mouseClick(other.openButton, other.openButton.width / 2, other.openButton.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      break;
    case 39:
      if (!check(!store.ticketById("4824").ticket.read && store.unreadCount === 2 && one.barContent.countLabel.text === "2",
                 "a failed launch marks nothing read")) return;
      if (!check(store.notice === "Can't open the browser" && shell.find(view, "statusBar").visible, "a failed launch says the browser can't open")) return;
      view.grabToImage(function(result) { result.saveToFile(Quickshell.env("FOAMY_OUT") + "/open-failed.png"); });
      openerMode.setText("");
      // A notification's View in Zendesk, through the real IPC: it reads up to
      // the reply shown, so one that came in since stays unread.
      store.receive(Fixtures.update(2, false));
      var argv = store.notificationCommand([store.state.tickets["4821"]]);
      store.receive(Fixtures.update(3, false));
      if (!check(!store.ticketById("4821").ticket.read, "the replies are unread")) return;
      shell.openBase = shell.opened().length;
      if (!shell.press(shell.actionsOf(argv)[0].argv)) return;
      break;
    case 40:
      if (!check(shell.opened().slice(shell.openBase).join() === "https://big.zendesk.com/agent/tickets/4821", "the notification's button opens the ticket")) return;
      if (!check(store.ticketById("4821").ticket.updates === 1 && store.unreadCount === 3 && one.barContent.countLabel.text === "3" && store.notice === "",
                 "and reads it up to the reply shown; the newer one stays unread")) return;
      openerMode.setText("fail\n");
      shell.openBase = shell.opened().length;
      if (!shell.press(shell.actionsOf(store.notificationCommand([store.state.tickets["4818"]]))[0].argv)) return;
      break;
    case 41:
      if (!check(!store.ticketById("4818").ticket.read && store.unreadCount === 3 && store.notice === "Can't open the browser",
                 "a notification's View in Zendesk that can't launch marks nothing read")) return;
      openerMode.setText("");
      // Opens of a ticket already on its way join it: one launch each, read up
      // to the further revision; "up to the newest" (the popup's) wins.
      store.loadFixtures(shell.many());
      var high = Model.newestFromOthers(store.state.tickets["4818"]);
      shell.openBase = shell.opened().length;
      store.openTicket("4821");
      for (var j = 0; j < 4; j++) store.viewInZendesk(store.host + "/4821:1");
      store.viewInZendesk(store.host + "/4818:" + (high - 1));
      store.viewInZendesk(store.host + "/4818:" + high);
      store.viewInZendesk(store.host + "/4818:" + (high - 1));
      for (var k = 0; k < 10; k++) store.openTicket("4824");
      if (!check(store.launching && store.launching.id === "4821" && store.launches.length === 2, "ten opens of one ticket wait as one")) return;
      shell.savedBody = String(high);
      break;
    case 42:
      var joined = shell.opened().slice(shell.openBase);
      if (!check(joined.length === 3 && joined.join() === ["4821", "4818", "4824"].map(function(id) { return "https://big.zendesk.com/agent/tickets/" + id; }).join(),
                 "each ticket opened once (" + joined.join() + ")")) return;
      if (!check(store.ticketById("4821").ticket.read && store.ticketById("4824").ticket.read && store.state.read["4818"].revision === Number(shell.savedBody)
                 && store.ticketById("4818").ticket.read, "joined opens read up to the further comment, or the newest")) return;
      // Ten different tickets at once: one opens, eight wait, the last is dropped.
      shell.openBase = shell.opened().length;
      for (var t = 4901; t <= 4910; t++) store.openTicket(String(t));
      if (!check(store.launches.length === 8, "at most eight opens wait")) return;
      break;
    case 43:
      var capped = shell.opened().slice(shell.openBase);
      if (!check(capped.length === 9 && capped.indexOf("https://big.zendesk.com/agent/tickets/4910") < 0
                 && store.ticketById("4909").ticket.read && !store.ticketById("4910").ticket.read, "the dropped open opens and marks nothing")) return;
      // A real account whose read file can be written until the opener locks its folder.
      store.helperCommand = function(args) {
        var address = args[args.indexOf("--address") + 1];
        var reply = shell.inboxReply(address, 9401);
        if (address === "lockable") reply.state_path = Quickshell.env("FOAMY_OUT") + "/lockable/read-lockable.json";
        return shell.fake("now", reply);
      };
      shell.saveBase = shell.saves;
      store.fixtures = false;
      account.address = "lockable";
      break;
    case 44:
      if (!check(store.unreadCount === 1 && shell.saveNotice() === "", "the inbox is saved and unread")) return;
      shell.saveBase = shell.saves;
      shell.openBase = shell.opened().length;
      var lockable = shell.find(view, "ticket-9401");
      ev.mouseClick(lockable.openButton, lockable.openButton.width / 2, lockable.openButton.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      break;
    case 45:
      if (!check(store.ticketById("9401").ticket.read && store.unreadCount === 0 && !one.barContent.countLabel.visible && shell.saveNotice() === "",
                 "the open's read mark is saved like Mark as read")) return;
      // Already read: opening it again writes nothing.
      shell.saveBase = shell.saves;
      shell.openBase = shell.opened().length;
      var again = shell.find(view, "ticket-9401");
      ev.mouseClick(again.openButton, again.openButton.width / 2, again.openButton.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      break;
    case 46:
      if (!check(!store.saveTimer.running && shell.saves === shell.saveBase && store.ticketById("9401").ticket.read, "opening a read ticket changes and saves nothing")) return;
      shell.saveBase = shell.saves;
      store.markUnread("9401");
      break;
    case 47:
      // The opener makes the read file's folder read-only, so the open's save fails.
      openerMode.setText("lock\n");
      shell.openBase = shell.opened().length;
      var locking = shell.find(view, "ticket-9401");
      ev.mouseClick(locking.openButton, locking.openButton.width / 2, locking.openButton.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      break;
    case 48:
      if (!check(shell.saveNotice() === shell.readMarkersLost && store.ticketById("9401").ticket.read && store.unreadCount === 0,
                 "an open whose read mark can't be saved says so in the notice bar; the ticket stays read")) return;
      // An open that ends after the account changed marks nothing in the next one,
      // which has a ticket with the same id and comment.
      openerMode.setText("hold\n");
      shell.openBase = shell.opened().length;
      store.viewInZendesk("lockable.zendesk.com/9401:94010");
      account.address = "fresh";
      break;
    case 49:
      if (!check(store.unreadCount === 1, "the next account's inbox is in, unread")) return;
      openerRelease.setText("go\n");
      break;
    case 50:
      if (!check(!store.ticketById("9401").ticket.read && store.unreadCount === 1 && one.barContent.countLabel.text === "1" && store.notice === "",
                 "the previous account's open marks nothing read in this one")) return;
      openerMode.setText("");
      // The sign-in is in a locked keyring whose unlock prompt is dismissed:
      // the helper can't read or remove it, and says so.
      account.helperCommand = function(args) {
        return shell.fake("now", { ok: false, code: "KEYRING_LOCKED", error: args[0] === "auth-logout" ? shell.lockedSignOut : shell.lockedKeyring });
      };
      account.state = "signed_in";
      account.user = { name: "Alex", email: "alex@acme.example" };
      account.error = "";
      view.band.settingsClicked();
      break;
    case 51:
      // The settings page has laid out: a real click on Sign out.
      var signOut = shell.find(view.settingsPage, "accountButton");
      if (!check(view.editingSettings && signOut.text === "Sign out", "signed in, the settings show Sign out")) return;
      ev.mouseClick(signOut, signOut.width / 2, signOut.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(account.logoutProcess.running, "Sign out runs the helper")) return;
      break;
    case 52:
      var page = view.settingsPage;
      if (!check(account.state === "signed_in" && account.signedIn && account.error === shell.lockedSignOut,
                 "a sign-out the locked keyring stopped stays signed in (" + account.state + ": " + account.error + ")")) return;
      if (!check(shell.find(page, "accountTitle").text === "Signed in as Alex" && shell.find(page, "accountDetail").text === "alex@acme.example · " + shell.lockedSignOut
                 && shell.find(page, "accountButton").text === "Sign out", "the settings say why, with Sign out to try again")) return;
      // A first check that finds the keyring locked: an error, not "Not signed in".
      account.state = "signed_out";
      account.user = null;
      account.check();
      break;
    case 53:
      var first = view.settingsPage;
      if (!check(account.state === "error" && account.error === shell.lockedKeyring && shell.find(first, "accountTitle").text === "Can't sign in"
                 && shell.find(first, "accountDetail").text === shell.lockedKeyring, "a locked keyring at the first check says so (" + account.state + ": " + account.error + ")")) return;
      view.settingsPage.back();
      one.close();
      // Wide: the list and the reading pane.
      one.prefs.save("hideRead", false);
      one.prefs.save("panelWidth", "wide");
      break;
    case 54:
      // Once the saved settings have settled (and any check they started), the
      // sample inbox; fixtures first, so signing in starts no fetch.
      store.loadFixtures(Fixtures.tickets());
      account.state = "signed_in";
      account.user = { name: "Alex", email: "alex@acme.example" };
      account.error = "";
      button.triggerPress(Qt.LeftButton);
      break;
    case 55:
      // Nothing selected: the overview beside the list. #4818 is Pending, so
      // only #4821 (High) and #4824 need a reply.
      if (!check(one.popup.contentWidth === one.wideWidth && view.list.width === view.listWidth && view.overview.visible && !view.pane.visible
                 && view.repeater.itemAt(0).wide && !view.repeater.itemAt(0).openButton.visible && !view.repeater.itemAt(0).readButton.visible,
                 "Wide opens at its width with the overview beside the list, and rows without their own actions")) return;
      if (!check(view.overview.awaitingRows.count === 2 && store.overview.awaiting.map(function(item) { return item.id; }).join() === "4821,4824",
                 "the overview lists what needs a reply, High first")) return;
      shell.savedY = one.popup.contentHeight;
      // Enter on the first ticket shows it in the pane and marks it read.
      view.cursor.index = view.firstTicketStop;
      view.activateRequested();
      var shown = view.repeater.itemAt(0);
      if (!check(view.selected && view.selected.ticket.id === "4821" && view.pane.visible && !view.overview.visible
                 && shown.selected && !shown.expanded && store.ticketById("4821").ticket.read, "Enter shows the ticket in the pane, read, not opened in place")) return;
      if (!check(shell.find(view.pane, "newDivider").visible && view.pane.lastFresh === 0 && view.pane.comments.children.length >= 4
                 && !shell.find(view.pane, "paneNote").visible,
                 "the pane shows every comment, the unread one under New")) return;
      break;
    case 56:
      if (!check(one.popup.contentWidth === one.wideWidth && one.popup.contentHeight === shell.savedY, "showing a ticket keeps the card's size")) return;
      // The pane's read action, from the keyboard: unread again, still shown.
      // The pane's actions from the keys: the keys' border; the pointer takes it away.
      view.cursor.index = view.paneFirstStop - 1;
      view.moveRequested(0, 1);
      if (!check(shell.keysBorder(view.pane.readButton) && shell.keysBorders(view).length === 1, "↓ onto the pane's read action: the keys' border (" + shell.keysBorders(view) + ")")) return;
      view.moveRequested(0, 1);
      if (!check(shell.keysBorder(view.pane.openButton) && shell.keysBorders(view).length === 1, "↓ onto View in Zendesk: the keys' border (" + shell.keysBorders(view) + ")")) return;
      view.moveRequested(0, 1);
      if (!check(shell.keysBorder(shell.find(view.pane, "paneClose")) && shell.keysBorders(view).length === 1, "↓ onto Hide ticket: the keys' border (" + shell.keysBorders(view) + ")")) return;
      ev.mouseMove(view.pane.openButton, view.pane.openButton.width / 2, view.pane.openButton.height / 2, -1, Qt.NoButton, Qt.NoModifier);
      if (!check(view.pane.openButton.hasCursor && shell.keysBorders(view).length === 0, "the pointer on View in Zendesk: no keys' border (" + shell.keysBorders(view) + ")")) return;
      ev.mouseMove(view.band, 10, 10, -1, Qt.NoButton, Qt.NoModifier);
      view.cursor.index = view.paneFirstStop;
      if (!check(view.pane.readButton.hasCursor, "the pane's read action takes the cursor")) return;
      view.activateRequested();
      if (!check(!store.ticketById("4821").ticket.read && view.pane.readButton.iconName === "mail-open" && view.selected.ticket.id === "4821",
                 "Mark as unread in the pane keeps the ticket shown")) return;
      // An update while a ticket is shown waits, and says how to show it.
      store.receive(Fixtures.update(1, false));
      if (!check(store.pendingChanges === 1 && shell.find(view, "updatesText").text === "1 update waiting" && shell.find(view, "showUpdates").visible,
                 "an update waits while a ticket is shown, with Show")) return;
      shell.openBase = shell.opened().length;
      view.cursor.index = view.paneFirstStop + 1;
      view.activateRequested();
      break;
    case 57:
      if (!check(shell.opened().slice(shell.openBase).join() === "https://" + store.host + "/agent/tickets/4821", "View in Zendesk in the pane opens the ticket")) return;
      // Wide: Show lets the waiting update in and keeps the ticket shown.
      var showWide = shell.find(view, "showUpdates");
      ev.mouseClick(showWide, showWide.width / 2, showWide.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(store.pendingChanges === 0 && view.selected && view.selected.ticket.id === "4821" && store.ticketById("4821").ticket.history.count === 5,
                 "Show in Wide applies the update and keeps the ticket shown")) return;
      // A click on the shown ticket's row closes it: the overview is back.
      var selectedRow = view.repeater.itemAt(view.selected.index);
      ev.mouseClick(selectedRow.bodyItem, selectedRow.bodyItem.width / 3, selectedRow.bodyItem.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(view.selected === null && view.overview.visible && !view.pane.visible, "a click on the shown ticket closes it")) return;
      break;
    case 58:
      if (!check(store.ticketById("4821").ticket.history.count === 5, "the update that waited is in")) return;
      // A click on a waiting ticket in the overview shows it, the cursor on its row.
      // A new ticket makes three waiting, from a requester with a long name in
      // a long-named group.
      var arrival = Fixtures.update(2, true);
      var longName = Array(40).join("Bergersen-");
      arrival[0].requester = longName;
      arrival[0].group = longName;
      arrival[0].comments[0].author = longName;
      // A comment taller than the pane, for scrolling it from the keyboard.
      arrival[0].comments[0].body = Array(80).join("A line of a long comment.\n")
        + "\nOn Thu, 5 Nov 2026 at 16:02, Alex <alex@acme.example> wrote:\n> The earlier mail.\n> Its second line.";
      // And one whose comments the helper deferred: it isn't counted as waiting.
      arrival.push({ id: "4950", subject: "Deferred comments", status: "Open", priority: "Normal", assignee: "Alex", mine: true,
                     group: "IT support", requester: "Ola", updated_at: "2026-11-06T09:00:00Z", deferred: true });
      store.receive(arrival);
      if (!check(view.overview.awaitingRows.count === 3 && store.ticketById("4950") !== null && shell.find(view.overview, "awaitingUnknown").visible
                 && !shell.find(view.overview, "nobodyWaiting").visible, "a new ticket waits for a reply too; the deferred one may, and the overview says so")) return;
      // Keyboard on an overview too short for its rows: the cursor's row scrolls into view.
      var overviewScroll = shell.find(view.overview, "overviewScroll");
      view.overview.anchors.fill = undefined;
      view.overview.height = 140;
      view.cursor.index = view.paneFirstStop - 1;
      view.moveRequested(0, 1);
      view.moveRequested(0, 1);
      view.moveRequested(0, 1);
      var lastRow = view.overview.awaitingRows.itemAt(2);
      var rowY = lastRow.mapToItem(overviewScroll.contentItem, 0, 0).y;
      var revealed = overviewScroll.contentY > 0 && rowY >= overviewScroll.contentY && rowY + lastRow.height <= overviewScroll.contentY + overviewScroll.height;
      view.overview.anchors.fill = view.overview.parent;
      if (!check(revealed && view.cursor.index === view.paneFirstStop + 2, "the keyboard scrolls the overview to the waiting ticket under the cursor")) return;
      if (!check(shell.keysBorder(lastRow) && shell.keysBorders(view).length === 1, "the overview's row under the keys shows their border (" + shell.keysBorders(view) + ")")) return;
      // Enter on the last waiting ticket: the selection leaves the pane two
      // stops, and the cursor lands on the ticket's row.
      view.activateRequested();
      if (!check(view.selected && view.selected.ticket.id === "4902" && view.cursor.index === view.firstTicketStop + view.selected.index,
                 "Enter on the overview's last waiting ticket shows it, the cursor on its row")) return;
      // The conversation, from the keyboard: Down scrolls it to its end, then
      // the cursor moves on to Refresh; Up scrolls back to the top, then to View.
      var conversation = view.pane.conversation;
      // A comment of over 40 lines is cut, with Show more; m shows it in full.
      // The columns lay out before the next frame; the keys come after one.
      var lengthLink = shell.find(view.pane, "lengthLink");
      var longEntry = lengthLink;
      while (longEntry && String(longEntry.objectName).indexOf("comment-") !== 0) longEntry = longEntry.parent;
      view.pane.settle(longEntry);
      if (!check(lengthLink && lengthLink.visible && view.pane.showMore() && !shell.find(view.pane, "fade").visible,
                 "a comment of over 40 lines is cut in the pane, and m shows the rest")) return;
      view.pane.settle(longEntry);
      // m showed the rest from where the comment was cut, and stays there.
      var cutAt = isNaN(view.pane.wheel.destination) ? conversation.contentY : view.pane.wheel.destination;
      if (!check(cutAt > 0 && cutAt < conversation.contentHeight - conversation.height - 100, "m shows the rest from where the comment was cut, not from its end (" + Math.round(cutAt) + ")")) return;
      view.pane.wheel.scrollTo(0, false);
      view.cursor.index = view.conversationStop;
      if (!check(shell.find(view.pane, "conversationCursor").visible && conversation.contentHeight > conversation.height,
                 "the cursor rings the conversation, which is taller than the pane")) return;
      var steps = 0;
      while (view.cursor.index === view.conversationStop && steps++ < 100) view.moveRequested(0, 1);
      var bottom = conversation.contentY;
      if (!check(steps > 2 && Math.abs(bottom - (conversation.contentHeight - conversation.height)) < 1 && view.cursor.index === view.refreshStop,
                 "Down scrolls the conversation to its end, then moves on")) return;
      view.moveRequested(0, -1);
      // Enter on the conversation opens nothing.
      shell.openBase = shell.opened().length;
      view.activateRequested();
      if (!check(view.cursor.index === view.conversationStop && !store.launching && store.launches.length === 0 && view.selected.ticket.id === "4902",
                 "Enter on the conversation does nothing")) return;
      // A wheel notch still animating doesn't undo a key's step.
      var wheel = view.pane.wheel;
      wheel.scrollBy(-wheel.notch, true);
      view.moveRequested(0, -1);
      if (!check(Math.abs(conversation.contentY - (bottom - 2 * wheel.notch)) < 1, "a key during a wheel animation scrolls from where the wheel goes")) return;
      steps = 0;
      while (view.cursor.index === view.conversationStop && steps++ < 100) view.moveRequested(0, -1);
      if (!check(conversation.contentY === 0 && view.cursor.index === view.paneFirstStop + 2, "Up scrolls it back to the top, then moves on to Hide ticket")) return;
      // Its quoted mail is folded behind Show quoted text; m shows it next.
      var quoteLink = shell.find(view.pane, "quoteLink");
      var quote = shell.find(view.pane, "commentQuote");
      if (!check(quoteLink.visible && quoteLink.text === "Show quoted text" && !quote.visible && quote.text.indexOf("> The earlier mail.") >= 0
                 && view.pane.showMore() && quote.visible && quoteLink.text === "Hide quoted text",
                 "the quoted mail at a comment's end folds behind Show quoted text")) return;
      // Shown once, the quote isn't followed: what changes next (here the
      // quote folding again) leaves the view where the reader put it.
      view.pane.wheel.scrollTo(0, false);
      view.pane.showQuote(longEntry, false);
      view.pane.settle(longEntry);
      if (!check(conversation.contentY === 0 && isNaN(view.pane.wheel.destination), "nothing pulls the view back to a quote it showed (" + Math.round(conversation.contentY) + ")")) return;
      // Long names stay inside the pane.
      var facts = shell.find(view.pane, "paneFacts");
      var fitted = facts.children.every(function(item) { return !item.visible || item.width <= facts.width; });
      var author = (function named(item) {
        // The model keeps 256 characters of a name (with "…").
        if (typeof item.text === "string" && item.text.indexOf("Bergersen-Bergersen-") === 0) return item;
        for (var child of item.children) { var hit = named(child); if (hit) return hit; }
        return null;
      })(shell.find(view.pane, "comment-49002"));
      if (!check(fitted && author && author.truncated && author.width < view.pane.comments.width, "long names elide inside the pane")) return;
      // The deferred ticket's comments are missing, not empty.
      view.toggleTicket("4950");
      if (!check(view.selected.ticket.id === "4950" && shell.find(view.pane, "paneNote").text === "Comments haven't loaded yet. They come with the next update.",
                 "a ticket whose comments haven't come says so")) return;
      view.toggleTicket("4950");
      // A click on a waiting ticket shows it too.
      var waitingRow = shell.find(view.overview, "awaiting-4824");
      ev.mouseClick(waitingRow, waitingRow.width / 2, waitingRow.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(view.selected && view.selected.ticket.id === "4824" && view.cursor.index === view.firstTicketStop + view.selected.index,
                 "a click on a waiting ticket in the overview shows it")) return;
      // The pane's × hides the ticket: the overview is back.
      var paneClose = shell.find(view.pane, "paneClose");
      ev.mouseClick(paneClose, paneClose.width / 2, paneClose.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(view.selected === null && view.overview.visible && !view.pane.visible, "the pane's Hide ticket shows the overview again")) return;
      // #4824 is read now: with read tickets hidden it leaves the list, but
      // still needs a reply. Chosen in the overview, it is listed while shown.
      store.hideRead = true;
      if (!check(store.ticketById("4824") === null && shell.find(view.overview, "awaiting-4824") !== null, "a hidden read ticket still shows in the overview")) return;
      view.toggleTicket("4824");
      if (!check(view.selected && view.selected.ticket.id === "4824" && store.ticketById("4824") !== null, "the overview shows a ticket that Hide read tickets keeps out of the list")) return;
      view.toggleTicket("4824");
      if (!check(store.ticketById("4824") === null && view.overview.visible, "closed, it leaves the list again")) return;
      store.hideRead = false;
      view.editingSettings = true;
      break;
    case 59:
      if (!shell.wideGrown) {
        if (!check(one.popup.contentWidth === one.wideWidth && one.popup.contentHeight === shell.savedY && shell.find(view.settingsPage, "panelWidth").value === "wide",
                   "Settings keep Wide's size")) return;
        view.settingsPage.back();
        // A short inbox gives Wide its 640; a long one makes it grow.
        if (!check(one.popup.contentHeight === one.popup.fittedContentHeight(Kit.FoamyStyle.popupMaxHeight), "a short inbox keeps Wide at 640 (" + one.popup.contentHeight + ")")) return;
        store.loadFixtures(shell.many().concat(shell.many().map(function(ticket) { return Object.assign({}, ticket, { id: String(Number(ticket.id) + 1000) }); })));
        shell.wideGrown = true;
        shell.step--;
        return;
      }
      // Needs a reply shows five; the link shows the rest, and folds them again.
      var moreLink = shell.find(view.overview, "awaitingMore");
      var total = store.overview.awaitingTotal;
      if (!check(total > 5 && view.overview.awaitingRows.count === 5 && moreLink.visible && moreLink.text === (total - 5) + " more need a reply",
                 "the overview shows five that need a reply and counts the rest (" + total + ")")) return;
      moreLink.clicked();
      if (!check(view.overview.awaitingRows.count === total && moreLink.text === "Show less", "its link shows every ticket that needs a reply")) return;
      moreLink.clicked();
      if (!check(view.overview.awaitingRows.count === 5, "Show less folds them again")) return;
      // The keys through the overview: five rows and the link, each with the keys' border.
      var overviewWalk = shell.keysWalk(view, view.paneFirstStop, view.paneFirstStop + 5);
      if (!check(overviewWalk.length === 0 && moreLink.hasCursor, "↓ through the overview and its link: the keys' border on each (" + overviewWalk + ")")) return;
      // Enter on "Show less": the cursor lands on the fifth row, a key's cursor.
      view.activateRequested();
      view.cursor.index = view.paneFirstStop + total - 1;
      view.moveRequested(0, 1);
      if (!check(moreLink.hasCursor && moreLink.text === "Show less", "↓ onto Show less")) return;
      view.activateRequested();
      var fifth = view.overview.awaitingRows.itemAt(4);
      if (!check(view.overview.awaitingRows.count === 5 && view.cursor.index === view.paneFirstStop + 4 && shell.keysBorder(fifth) && shell.keysBorders(view).length === 1,
                 "Enter on Show less: the fifth row has the keys' border (" + JSON.stringify([view.cursor.index, shell.keysBorders(view)]) + ")")) return;
      // The pointer onto the link takes the cursor there, with no keys' border.
      ev.mouseMove(moreLink, moreLink.width / 2, moreLink.height / 2, -1, Qt.NoButton, Qt.NoModifier);
      if (!check(view.cursor.index === view.paneFirstStop + 5 && moreLink.hasCursor && shell.keysBorders(view).length === 0,
                 "the pointer on the more link: the cursor there, no keys' border (" + JSON.stringify([view.cursor.index, shell.keysBorders(view)]) + ")")) return;
      // The keys come to the row the pointer rests in; a move inside it takes the cursor back.
      ev.mouseMove(fifth, fifth.width / 2, fifth.height / 2, -1, Qt.NoButton, Qt.NoModifier);
      view.moveRequested(0, 1);
      view.moveRequested(0, -1);
      if (!check(shell.keysBorder(fifth), "the keys back on the row under the pointer: their border")) return;
      ev.mouseMove(fifth, fifth.width / 2 + 3, fifth.height / 2, -1, Qt.NoButton, Qt.NoModifier);
      if (!check(fifth.hasCursor && shell.keysBorders(view).length === 0, "a pointer move inside the row: no keys' border (" + shell.keysBorders(view) + ")")) return;
      ev.mouseMove(view.band, 10, 10, -1, Qt.NoButton, Qt.NoModifier);
      // At most 70 % of the 1080 px screen.
      if (!check(one.popup.contentHeight > one.popup.fittedContentHeight(Kit.FoamyStyle.popupMaxHeight) && one.popup.contentHeight <= Math.round(1080 * 0.7),
                 "a long inbox makes Wide grow, up to 70 % of the screen (" + one.popup.contentHeight + ")")) return;
      one.prefs.save("panelWidth", "standard");
      break;
    case 60:
      if (!check(one.popup.contentWidth === one.popup.fittedContentWidth(Kit.FoamyStyle.popupWidth) && !view.wide && !view.paneShown && view.list.width === view.width
                 && view.repeater.itemAt(0).wide === false, "Small again: 420, the list across the popup")) return;
      // Zendesk's comment ids exceed an int. A ticket read up to one comment
      // gets a reply: opened in place, only the reply is new.
      var big = shell.bigId;
      store.loadFixtures(shell.bigTicket([shell.bigComment(big, 10)], "2026-11-06T09:30:00Z"));
      store.markRead("7001");
      store.receive(shell.bigTicket([shell.bigComment(big + 1, 1), shell.bigComment(big, 10)], "2026-11-06T09:39:00Z"));
      view.toggleTicket("7001");
      var bigCard = shell.find(view, "ticket-7001");
      if (!check(bigCard.expanded && bigCard.openedSince === big && bigCard.historyRepeater.itemAt(0).fresh && !bigCard.historyRepeater.itemAt(1).fresh,
                 "opened in place, a ticket with large comment ids marks only the reply as new")) return;
      one.close();
      view.fixedNow = 0;
      break;
    case 61:
      // A check that started before a sign-out answers for a sign-in that is
      // gone: its reply, slower than the sign-out's, is ignored.
      account.error = "";
      account.state = "signed_in";
      account.user = { name: "Alex", email: "alex@acme.example" };
      shell.statusRuns = 0;
      account.helperCommand = function(args) {
        if (args[0] === "auth-status") {
          shell.statusRuns++;
          return shell.fake("slow", { ok: true, state: "signed_in", verified: true, user: { name: "Stale", email: "stale@example.invalid" } });
        }
        return shell.fake("now", { ok: true, state: "signed_out" });
      };
      shell.signOutBase = shell.signOutsEnded;
      account.check();
      account.signOut();
      if (!check(account.statusProcess.running && account.logoutProcess.running, "a check and a sign-out run at once")) return;
      break;
    case 62:
      if (!check(account.state === "signed_out" && account.user === null && shell.statusRuns === 1,
                 "a status reply from before the sign-out is ignored (" + account.state + ", " + JSON.stringify(account.user) + ")")) return;
      // A sign-out that can't use the sign-in's lock file: still signed in, and why.
      account.state = "signed_in";
      account.user = { name: "Alex", email: "alex@acme.example" };
      account.helperCommand = function(args) {
        return shell.fake("now", { ok: false, code: "LOCK_UNAVAILABLE", error: "Sign-out didn't finish: the Zendesk sign-in's lock file can't be used (%1). Try again.\u001ftest" });
      };
      shell.signOutBase = shell.signOutsEnded;
      account.signOut();
      break;
    case 63:
      if (!check(account.state === "signed_in" && account.user && account.user.name === "Alex"
                 && account.error === "Sign-out didn't finish: the Zendesk sign-in's lock file can't be used (test). Try again.",
                 "a sign-out that can't use the lock file stays signed in and says why (" + account.state + ": " + account.error + ")")) return;
      // An account whose fetches fail, then refuse: first its inbox.
      account.error = "";
      account.helperCommand = function(args) {
        if (args[0] === "auth-status") shell.statusRuns++;
        return shell.fake("now", { ok: true, state: "signed_in", verified: true, user: { name: "Alex", email: "alex@acme.example" } });
      };
      shell.fetchReply = shell.inboxReply("failing", 9601);
      store.helperCommand = function(args) {
        shell.fetches = shell.fetches.concat([args[args.indexOf("--address") + 1]]);
        return shell.fake("now", shell.fetchReply);
      };
      // Signed out while the store leaves fixtures, so only the sign-in below starts a fetch.
      account.state = "signed_out";
      store.fixtures = false;
      account.address = "failing";
      shell.fetchProbe = shell.fetches.length;
      account.state = "signed_in";
      break;
    case 64:
      if (!check(shell.fetches.length === shell.fetchProbe + 1 && store.count === 1 && store.tickets.get(0).id === "9601" && store.error === "" && store.failures === 0,
                 "the failing account's inbox arrived, from one fetch")) return;
      // Zendesk answers 503: the inbox stays, the footer says why, the next check waits twice as long.
      shell.fetchReply = { ok: false, code: "HTTP", error: "Zendesk answered HTTP %1.\u001f503" };
      shell.fetchEndBase = shell.fetchesEnded;
      store.refresh();
      break;
    case 65:
      var refreshError = shell.find(one.popup.bodyItem, "refreshError");
      if (!check(store.count === 1 && store.error === "Zendesk answered HTTP 503." && shell.footer().statusError && shell.footer().status.indexOf("Updated") === 0
                 && one.popup.bodyItem.refreshFailed && refreshError.text === store.error && refreshError.linkText === "Retry",
                 "a failed fetch keeps the inbox, the notice bar says why with Retry, the footer keeps the age in red (" + store.error + ")")) return;
      if (!check(store.failures === 1 && store.pollTimer.running && store.pollTimer.interval === 2 * store.refreshSeconds * 1000 && store.retryAt > Date.now(),
                 "a failed fetch doubles the wait for the next (" + store.failures + ", " + store.pollTimer.interval + ")")) return;
      if (!check(button.trouble === "" && !one.barContent.troubleSign.visible && one.barContent.icon.opacity === 1, "one failed check does not mark the bar button yet")) return;
      // An expired sign-in: the account checks again.
      shell.statusRuns = 0;
      shell.fetchReply = { ok: false, code: "EXPIRED", error: "Zendesk answered HTTP %1.\u001f401" };
      shell.fetchEndBase = shell.fetchesEnded;
      // The notice bar's Retry refreshes.
      shell.find(refreshError, "retryRefresh").clicked();
      break;
    case 66:
      if (!check(shell.statusRuns === 1 && store.failures === 2 && account.state === "signed_in" && account.user && account.user.name === "Alex",
                 "an expired sign-in makes the account check again (" + shell.statusRuns + " checks, " + store.failures + " failures)")) return;
      // Two failed checks in a row: the inbox is stale. The icon dims, the
      // sign shows, and the tooltip says since when.
      if (!check(button.trouble === "stale" && one.barContent.troubleSign.visible && one.barContent.icon.opacity < 1 && button.lastLoaded !== ""
                 && button.tooltipText.indexOf("not updated since " + button.lastLoaded) >= 0,
                 "a stale inbox marks the bar button and says since when (" + button.tooltipText + ")")) return;
      // A reply with a broken ticket is refused whole: the valid new ticket
      // before it is not applied either.
      var refused = shell.inboxReply("failing", 9602);
      shell.fetchReply = { ok: true, state_path: refused.state_path, tickets: [refused.tickets[0], { id: "x" }] };
      shell.fetchEndBase = shell.fetchesEnded;
      store.refresh();
      break;
    case 67:
      // The next sync shows what the store holds, not only what the list showed before.
      store.sync();
      if (!check(store.error === "Zendesk sent an unexpected reply." && store.count === 1 && store.tickets.get(0).id === "9601"
                 && Object.keys(store.state.tickets).join() === "9601",
                 "a refused reply keeps the previous inbox and says so (" + store.error + ", " + Object.keys(store.state.tickets).join() + ")")) return;
      // A helper that ends without a reply.
      store.helperCommand = function() { return ["sh", "-c", "exit 1"]; };
      shell.fetchEndBase = shell.fetchesEnded;
      store.refresh();
      break;
    case 68:
      if (!check(store.error === "Can't reach Zendesk. Check your connection." && store.count === 1 && store.tickets.get(0).id === "9601",
                 "a helper that ends without a reply keeps the inbox and says to check the connection (" + store.error + ")")) return;
      // As if the timeout wrapper had ended the helper (exit 124).
      store.helperCommand = function() { return ["sh", "-c", "exit 124"]; };
      shell.fetchEndBase = shell.fetchesEnded;
      store.refresh();
      break;
    case 69:
      if (!check(store.error === "Zendesk didn't answer in time." && store.count === 1 && store.tickets.get(0).id === "9601",
                 "a helper the timeout ended keeps the inbox and says Zendesk didn't answer in time (" + store.error + ")")) return;
      // Read markers in an existing file load before the first inbox shows:
      // the store's unread count never rises above 0.
      store.helperCommand = function(args) {
        var address = args[args.indexOf("--address") + 1];
        shell.fetches = shell.fetches.concat([address]);
        return shell.fake("now", shell.inboxReply(address, 9501));
      };
      shell.maxUnread = 0;
      account.address = "preread";
      break;
    case 70:
      if (!check(store.count === 1 && store.unreadCount === 0 && shell.maxUnread === 0,
                 "markers from the read file load before the inbox shows: no flash of unread (" + shell.maxUnread + ")")) return;
      shell.maxUnread = -1;
      // Wide, with markup in every text field: each is shown as plain text.
      one.prefs.save("panelWidth", "wide");
      break;
    case 71:
      var marked = Fixtures.tickets();
      marked[0].subject = "<b>Bold</b> subject";
      marked[0].group = "<s>IT</s>";
      marked[0].comments[0].body = "<img src=\"https://example.invalid/x\"> <i>hi</i>";
      marked[0].comments[0].author = "<u>Anna</u>";
      marked[0].requester = "<u>Anna</u>";
      store.loadFixtures(marked);
      account.state = "signed_in";
      account.user = { name: "Alex", email: "alex@acme.example" };
      account.error = "";
      one.open();
      break;
    case 72:
      view.toggleTicket("4821");
      var markup = ["<b>Bold", "<img", "<u>Anna", "<s>IT"];
      var withMarkup = function(root) {
        var found = [];
        (function collect(item) {
          if (item.hasOwnProperty("textFormat") && typeof item.text === "string" && markup.some(function(mark) { return item.text.indexOf(mark) >= 0; }))
            found.push(item);
          for (var child of item.children) collect(child);
        })(root);
        return found;
      };
      // Of the markers `marks`, those that `root` does not show as plain text.
      var notPlain = function(root, marks) {
        var plain = withMarkup(root).filter(function(item) { return item.textFormat === Text.PlainText; });
        return marks.filter(function(mark) { return !plain.some(function(item) { return item.text.indexOf(mark) >= 0; }); });
      };
      var rich = withMarkup(view).filter(function(item) { return item.textFormat !== Text.PlainText; });
      // A Wide row shows the subject and the requester; the pane the comment
      // and its author too; the group shows in the overview only.
      var rowMissing = notPlain(shell.find(view, "ticket-4821"), ["<b>Bold", "<u>Anna"]);
      var paneMissing = notPlain(view.pane, ["<b>Bold", "<img", "<u>Anna"]);
      if (!check(rich.length === 0 && rowMissing.length === 0 && paneMissing.length === 0,
                 "markup in a subject, comment, author or requester shows as plain text in the list row and the pane (rich: "
                 + rich.map(function(item) { return item.text; }).join(" | ") + "; not plain in the row: " + rowMissing.join(" ")
                 + "; not plain in the pane: " + paneMissing.join(" ") + ")")) return;
      view.toggleTicket("4821");
      var overviewMissing = notPlain(view.overview, ["<b>Bold", "<s>IT"]);
      if (!check(withMarkup(view).every(function(item) { return item.textFormat === Text.PlainText; }) && overviewMissing.length === 0,
                 "markup in a subject or group shows as plain text in the overview (not plain: " + overviewMissing.join(" ") + ")")) return;
      // A ticket read up to a large comment id gets a reply: shown in the pane, only the reply is new.
      var big = shell.bigId;
      store.loadFixtures(shell.bigTicket([shell.bigComment(big, 10)], "2026-11-06T09:30:00Z"));
      store.markRead("7001");
      store.receive(shell.bigTicket([shell.bigComment(big + 1, 1), shell.bigComment(big, 10)], "2026-11-06T09:39:00Z"));
      view.toggleTicket("7001");
      if (!check(view.selected && view.selected.ticket.id === "7001" && view.pane.lastFresh === 0 && shell.find(view.pane, "newDivider").visible
                 && shell.find(shell.find(view.pane, "comment-" + big), "earlierDivider").visible, "in the pane, a ticket with large comment ids marks only the reply as new (" + view.pane.lastFresh + ")")) return;
      view.toggleTicket("7001");
      one.close();
      one.prefs.save("panelWidth", "standard");
      break;
    case 73:
      // The helper prints something that isn't JSON: an error, still signed in.
      account.state = "signed_in";
      account.user = { name: "Alex", email: "alex@acme.example" };
      account.error = "";
      account.helperCommand = function() { return ["sh", "-c", "echo not json"]; };
      account.check();
      break;
    case 74:
      if (!check(account.state === "signed_in" && account.error === "The Zendesk helper failed.",
                 "output that isn't JSON never signs the user out (" + account.state + ": " + account.error + ")")) return;
      // No helper for this CPU (the timeout wrapper exits 127): the inbox stops trying.
      store.helperCommand = function() { return ["/nonexistent/foamy-zendesk-helper"]; };
      // Leaving the fixtures starts the fetch at once (the store turns active).
      shell.fetchEndBase = shell.fetchesEnded;
      store.fixtures = false;
      if (!store.fetchProcess.running) store.refresh();
      break;
    case 75:
      if (!check(store.helperMissing && !store.connected && !store.pollTimer.running && store.error === Kit.FoamyI18n.t(FoamyNative.UNAVAILABLE_TEXT),
                 "a missing helper stops the inbox and says why (" + store.error + ")")) return;
      store.refresh();
      if (!check(!store.fetchProcess.running, "and nothing is fetched again")) return;
      account.helperCommand = function() { return ["/nonexistent/foamy-zendesk-helper"]; };
      account.check();
      break;
    case 76:
      if (!check(account.state === "unavailable" && account.error === Kit.FoamyI18n.t(FoamyNative.UNAVAILABLE_TEXT),
                 "a missing helper makes the account unavailable (" + account.state + ": " + account.error + ")")) return;
      view.editingSettings = true;
      if (!check(!shell.find(view.settingsPage, "accountButton").actionEnabled, "Sign in is off without a helper")) return;
      view.editingSettings = false;
      account.check();
      account.signIn();
      if (!check(!account.statusProcess.running && !account.loginProcess.running && account.state === "unavailable", "no more checks or sign-ins")) return;
      languageFile.setText("no\n");
      break;
    case 77:
      one.prefs.save("panelWidth", "wide");
      break;
    case 78:
      // Tickets without a subject (none given, or an empty one), in Norwegian.
      var untitled = Fixtures.tickets();
      delete untitled[0].subject;
      untitled[2].subject = "";
      store.loadFixtures(untitled);
      account.state = "signed_in";
      account.user = { name: "Alex", email: "alex@acme.example" };
      account.error = "";
      one.open();
      break;
    case 79:
      var none = "(uten emne)";
      // [shown subject, screen-reader name] of each untitled row: each one checked on its own.
      var listed = ["4821", "4824"].map(function(id) { var row = shell.find(view, "ticket-" + id); return [shell.find(row, "subject").text, row.bodyItem.Accessible.name]; });
      var awaiting = ["4821", "4824"].map(function(id) { var row = shell.find(view.overview, "awaiting-" + id); return [shell.find(row, "subject").text, row.Accessible.name]; });
      var shows = function(rows) { return rows.every(function(row) { return row[0] === none; }); };
      var names = function(rows) { return rows.every(function(row) { return row[1].indexOf(none + ", ") === 0; }); };
      var sent = function(list) { var argv = store.notificationCommand(list); return argv.slice(argv.indexOf("--") + 1); };
      var vpn = store.state.tickets["4821"], display = store.state.tickets["4824"];
      if (!check(shows(listed), "a list row shows a ticket without a subject in the reader's language (" + JSON.stringify(listed) + ")")) return;
      if (!check(names(listed), "and names it so for screen readers (" + JSON.stringify(listed) + ")")) return;
      if (!check(shows(awaiting), "so does the overview (" + JSON.stringify(awaiting) + ")")) return;
      if (!check(names(awaiting), "and its name for screen readers (" + JSON.stringify(awaiting) + ")")) return;
      if (!check(sent([vpn])[0] === none && sent([vpn, display])[1].split("\n").slice(0, 2).join("|") === none + "|" + none,
                 "and its notification (" + JSON.stringify(sent([vpn])[0]) + ")")) return;
      view.toggleTicket("4821");
      if (!check(shell.find(view.pane, "paneSubject").text === none, "and the reading pane (" + shell.find(view.pane, "paneSubject").text + ")")) return;
      // Signed out, on Settings. The sign-in's stand-in waits in the
      // "browser" until the test lets it finish; an account check finds
      // any address signed out.
      account.helperCommand = function(args) {
        if (args[0] !== "auth-login") return shell.fake("now", { ok: true, state: "signed_out" });
        return shell.fake("held", { ok: true, state: "signed_in", verified: true, user: { name: "Waited", email: "waited@example.invalid" } });
      };
      account.state = "signed_out";
      account.user = null;
      account.error = "";
      view.editingSettings = true;
      break;
    case 80:
      var page = view.settingsPage;
      shell.toAccount(page);
      var address = shell.find(page, "addressField");
      var signIn = shell.find(page, "accountButton");
      shell.savedAddress = one.prefs.value("zendeskAddress");
      if (!check(shell.onPage(page, signIn) && shell.onPage(page, address) && address.field.text === shell.savedAddress && account.address === shell.savedAddress,
                 "signed out, Sign in and the address field with the saved address are on screen")) return;
      ev.mouseClick(signIn, signIn.width / 2, signIn.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(account.state === "waiting", "a click on Sign in starts the sign-in (" + account.state + ")")) return;
      break;
    case 81:
      // While it waits in the browser: a real click into the address field
      // and a key, then the sign-in finishes.
      var address = shell.find(view.settingsPage, "addressField");
      ev.mouseClick(address.field, address.field.width / 2, address.field.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      ev.keyClick(Qt.Key_X, Qt.NoModifier, -1);
      shell.typedWhileWaiting = address.field.text;
      loginRelease.setText("go\n");
      break;
    case 82:
      if (!check(account.signedIn && account.user && account.user.name === "Waited" && one.prefs.value("zendeskAddress") === shell.savedAddress && account.address === shell.savedAddress,
                 "a key typed into the address field while the sign-in waits is not saved when it ends, and the user who signed in stays signed in ("
                 + account.state + ", " + JSON.stringify(account.user) + ", saved address " + one.prefs.value("zendeskAddress") + ")")) return;
      // A field that takes no key while the sign-in waits has no draft to
      // save when the browser takes the focus either.
      if (!check(shell.typedWhileWaiting === shell.savedAddress, "the address field takes no key while the sign-in waits (" + shell.typedWhileWaiting + ")")) return;
      // Then Sign in and Cancel: this stand-in waits until it is stopped.
      account.helperCommand = function(args) {
        return shell.fake(args[0] === "auth-login" ? "stopped" : "now", { ok: true, state: "signed_out" });
      };
      account.state = "signed_out";
      account.user = null;
      break;
    case 83:
      var page = view.settingsPage;
      shell.toAccount(page);
      var signIn = shell.find(page, "accountButton");
      if (!check(shell.onPage(page, signIn) && shell.onPage(page, shell.find(page, "addressField")), "signed out again, Sign in and the address field are on screen")) return;
      ev.mouseClick(signIn, signIn.width / 2, signIn.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      break;
    case 84:
      var cancel = shell.find(view.settingsPage, "accountButton");
      ev.mouseClick(cancel, cancel.width / 2, cancel.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      break;
    case 85:
      // Cancelled, the address field takes typing again; Esc drops the draft.
      var address = shell.find(view.settingsPage, "addressField");
      ev.mouseClick(address.field, address.field.width / 2, address.field.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      ev.keyClick(Qt.Key_X, Qt.NoModifier, -1);
      if (!check(address.editing && address.field.text === shell.savedAddress + "x", "after Cancel the address field takes typing again (" + address.field.text + ")")) return;
      ev.keyClick(Qt.Key_Escape, Qt.NoModifier, -1);
      // A widget without a bar entry: its settings queue refuses every save.
      one.moduleName = "";
      view.settingsPage.resetScroll();
      break;
    case 86:
      var size = shell.find(view.settingsPage, "panelWidth");
      if (!check(view.editingSettings && shell.onPage(view.settingsPage, size) && size.value === "wide", "Settings shows the saved size, Wide")) return;
      ev.mouseClick(size.triggerItem, size.triggerItem.width / 2, size.triggerItem.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      break;
    case 87:
      // Small, picked with the keys, is refused: the dropdown shows the
      // saved Wide again at once, not Small for its 10 s hold.
      var size = shell.find(view.settingsPage, "panelWidth");
      if (!check(size.popupOpen, "a click on the size opens its list")) return;
      shell.refused = [];
      ev.keyClick(Qt.Key_Up, Qt.NoModifier, -1);
      ev.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
      if (!check(JSON.stringify(shell.refused) === JSON.stringify([["panelWidth", "standard"]]), "the queue refuses the pick of Small (" + JSON.stringify(shell.refused) + ")")) return;
      if (!check(size.shownValue === "wide", "a refused pick shows the saved size again at once (shows " + size.shownValue + ")")) return;
      // The schedule on, so that Outside the schedule shows too.
      one.moduleName = "foamy.zendesk";
      one.prefs.save("scheduleEnabled", true);
      one.moduleName = "";
      // The other three dropdowns, each picked as its list picks (select()):
      // the queue refuses the pick, and the dropdown shows the saved value
      // again at once. Check every saves its choice as a number.
      for (var linked of [["notify", String], ["scheduleOutsideMode", String], ["refreshSeconds", Number]]) {
        var dropdown = shell.find(view.settingsPage, linked[0]);
        var savedValue = dropdown.value;
        var picked = dropdown.options.map(function(option) { return dropdown.optionValue(option); }).find(function(value) { return value !== savedValue; });
        if (!check(dropdown.visible && picked !== undefined, linked[0] + " shows, with an option other than the saved " + savedValue)) return;
        shell.refused = [];
        dropdown.select(picked);
        if (!check(JSON.stringify(shell.refused) === JSON.stringify([[linked[0], linked[1](picked)]]), "the queue refuses the pick of " + picked + " in " + linked[0] + " (" + JSON.stringify(shell.refused) + ")")) return;
        if (!check(dropdown.shownValue === savedValue, "a refused pick in " + linked[0] + " shows the saved value again at once (shows " + dropdown.shownValue + ", saved " + savedValue + ")")) return;
      }
      // Wednesday's saved range.
      one.moduleName = "foamy.zendesk";
      one.prefs.save("scheduleWednesday", "08:00-16:00");
      break;
    case 88:
      var wednesday = shell.find(view.settingsPage, "scheduleWednesday");
      if (!check(wednesday && shell.find(wednesday, "fromTime").text === "08:00", "Settings shows Wednesday's saved range")) return;
      one.moduleName = "";
      view.settingsPage.ensureVisible(wednesday);
      break;
    case 89:
      // A new From time, typed and sent with Return, is refused: the row
      // shows the saved 08:00 again at once, not the unsaved 09:00.
      var from = shell.find(shell.find(view.settingsPage, "scheduleWednesday"), "fromTime");
      if (!check(shell.onPage(view.settingsPage, from), "Wednesday's From time is on screen")) return;
      ev.mouseClick(from, from.width / 2, from.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      ev.keyClick(Qt.Key_A, Qt.ControlModifier, -1);
      for (var c of "09:00") ev.keyClickChar(c, Qt.NoModifier, -1);
      shell.refused = [];
      ev.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
      if (!check(JSON.stringify(shell.refused) === JSON.stringify([["scheduleWednesday", "09:00-16:00"]]), "the queue refuses Wednesday's new range (" + JSON.stringify(shell.refused) + ")")) return;
      if (!check(from.text === "08:00", "a refused range shows the saved range again at once (From shows " + from.text + ")")) return;
      one.moduleName = "foamy.zendesk";
      // The connection fields next. The page follows the item it scrolls
      // to for a moment as it grows (the error line just came back): hand
      // that to the Zendesk section.
      view.settingsPage.ensureVisible(shell.find(view.settingsPage, "zendeskSection"));
      break;
    case 90:
      // In each connection field a new value, typed and sent with Return,
      // is refused: the field shows the saved value again at once, not the
      // unsaved text, and the same text, typed again, is sent again.
      var page = view.settingsPage;
      one.moduleName = "";
      for (var connection of [["addressField", "zendeskAddress", "umbrella"], ["clientIdField", "oauthClientId", "other-client-2"], ["portField", "oauthPort", "48002"]]) {
        var field = shell.find(page, connection[0]);
        var savedText = one.prefs.value(connection[1]);
        if (!check(shell.onPage(page, field) && field.field.text === savedText && savedText !== connection[2],
                   connection[0] + " is on screen and shows the saved " + savedText + " (on screen: " + shell.onPage(page, field) + ", shows " + field.field.text + ")")) return;
        for (var attempt of ["once", "again"]) {
          ev.mouseClick(field.field, field.field.width / 2, field.field.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
          ev.keyClick(Qt.Key_A, Qt.ControlModifier, -1);
          for (var c of connection[2]) ev.keyClickChar(c, Qt.NoModifier, -1);
          shell.refused = [];
          ev.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
          if (!check(JSON.stringify(shell.refused) === JSON.stringify([[connection[1], connection[2]]]), connection[0] + " sends " + connection[2] + " " + attempt + " and the queue refuses it (" + JSON.stringify(shell.refused) + ")")) return;
          if (!check(field.field.text === savedText, "a refused " + connection[0] + " shows the saved " + savedText + " again at once (shows " + field.field.text + ")")) return;
        }
      }
      // The bar entry back, a save the queue takes (of the saved address,
      // so nothing changes) clears the page's error line: the next step
      // sees the error that Sign in brings.
      one.moduleName = "foamy.zendesk";
      one.prefs.save("zendeskAddress", one.prefs.value("zendeskAddress"));
      page.ensureVisible(shell.find(page, "zendeskSection"));
      break;
    case 91:
      // A new address typed, then a click on Sign in: the queue refuses the
      // address, so the sign-in does not start (it would use the saved
      // address). The field shows the saved address again, the page the
      // save error.
      var page = view.settingsPage;
      var address = shell.find(page, "addressField");
      var signIn = shell.find(page, "accountButton");
      var saveError = shell.find(page, "settingsErrorText");
      var savedAddress = one.prefs.value("zendeskAddress");
      if (!check(shell.onPage(page, address) && shell.onPage(page, signIn) && !saveError.visible && account.state === "signed_out",
                 "signed out, the address field and Sign in are on screen, with no save error (" + account.state + ", error " + saveError.text + ")")) return;
      one.moduleName = "";
      ev.mouseClick(address.field, address.field.width / 2, address.field.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      ev.keyClick(Qt.Key_A, Qt.ControlModifier, -1);
      for (var c of "umbrella") ev.keyClickChar(c, Qt.NoModifier, -1);
      shell.refused = [];
      ev.mouseClick(signIn, signIn.width / 2, signIn.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(JSON.stringify(shell.refused) === JSON.stringify([["zendeskAddress", "umbrella"]]), "Sign in sends the typed address and the queue refuses it (" + JSON.stringify(shell.refused) + ")")) return;
      if (!check(account.state === "signed_out" && !account.loginProcess.running, "a sign-in whose address was refused does not start (" + account.state + ")")) return;
      if (!check(address.field.text === savedAddress, "the address field shows the saved " + savedAddress + " again (shows " + address.field.text + ")")) return;
      if (!check(one.prefs.error !== "" && saveError.visible && saveError.text === Kit.FoamyI18n.t(one.prefs.error),
                 "the settings page shows the save error (" + one.prefs.error + "; shows " + saveError.text + ")")) return;
      one.moduleName = "foamy.zendesk";
      page.ensureVisible(shell.find(page, "zendeskSection"));
      break;
    case 92:
      // Without the inline save the queue saves through the CLI, one save at
      // a time; the fake omarchy holds the first. A new Check every choice
      // is saved first, and the new address that a click on Sign in sends
      // waits behind it. The sign-in does not start: it would use the saved
      // address.
      var page = view.settingsPage;
      var address = shell.find(page, "addressField");
      var signIn = shell.find(page, "accountButton");
      var every = shell.find(page, "refreshSeconds");
      var savedEvery = every.value;
      var picked = every.options.map(function(option) { return every.optionValue(option); }).find(function(value) { return value !== savedEvery; });
      if (!check(shell.onPage(page, address) && shell.onPage(page, signIn) && picked !== undefined && account.state === "signed_out",
                 "signed out, the address field and Sign in are on screen, and Check every has an option other than the saved " + savedEvery)) return;
      shell.inlineSaves = bar.shell;
      bar.shell = null;
      omarchyMode.setText("hold\n");
      every.select(picked);
      if (!check(one.prefs.saving, "without the inline save Check every is saved through the CLI")) return;
      ev.mouseClick(address.field, address.field.width / 2, address.field.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      ev.keyClick(Qt.Key_A, Qt.ControlModifier, -1);
      for (var c of "umbrella") ev.keyClickChar(c, Qt.NoModifier, -1);
      shell.refused = [];
      ev.mouseClick(signIn, signIn.width / 2, signIn.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
      if (!check(shell.refused.length === 0 && one.prefs.busy && one.prefs.value("zendeskAddress") !== "umbrella",
                 "the address that Sign in sends waits behind the held save (" + JSON.stringify(shell.refused) + ", saved " + one.prefs.value("zendeskAddress") + ")")) return;
      if (!check(account.state === "signed_out" && !account.loginProcess.running, "a sign-in whose address waits to be saved does not start (" + account.state + ")")) return;
      // The held save fails, then the address after it (step 93 waits).
      omarchyRelease.setText("go\n");
      break;
    case 93:
      bar.shell = shell.inlineSaves;
      omarchyMode.setText("");
      // Steps 93 to 103 switch the theme live (applyTheme).
      themeFile.reload();
      shell.savedTheme = themeFile.text();
      shell.savedColours = shell.colours();
      if (!check(shell.savedTheme !== "" && dimRed.text() !== "" && lightToml.text() !== "",
                 "the theme files are read (" + themeFile.path + ", dim-red.toml, light.toml)")) return;
      // A theme whose red does not read on the popup (step 94 waits).
      if (!shell.applyTheme(dimRed.text())) return;
      break;
    case 94:
      // An expired sign-in after a failed refresh: the empty state's icon on
      // its red disc, and the failing notice on the notice bar.
      view.editingSettings = false;
      account.state = "expired";
      store.loadFixtures([]);
      store.error = "Zendesk answered HTTP 503.";
      break;
    case 95:
      var card = one.popup.cardItem.color;
      var icon = shell.find(view, "emptyIcon");
      if (!check(one.opened && shell.find(view, "emptyState").kind === "expired", "the popup shows the expired sign-in")) return;
      if (!shell.readsOn("the empty state's icon", icon, Qt.tint(card, icon.parent.color), Kit.FoamyPalette.onSurface(Kit.FoamyPalette.error))) return;
      if (!shell.readsOn("a failing notice", shell.find(view, "refreshText"), Qt.tint(card, shell.find(view, "statusBar").color), Commons.Color.urgent)) return;
      // A light theme, whose yellow must darken: #4821's newest comment is
      // an internal note (step 96 waits).
      if (!shell.applyTheme(lightToml.text())) return;
      var noted = Fixtures.tickets();
      noted[0].comments[0].public = false;
      store.loadFixtures(noted);
      account.state = "signed_in";
      account.user = { name: "Alex", email: "alex@acme.example" };
      account.error = "";
      break;
    case 96:
      // Wide with nothing selected: the cursor on #4821 (High, late) in the
      // overview's "Needs a reply".
      if (!check(one.wide && view.selected === null && view.overview.visible && store.overview.awaiting[0].id === "4821",
                 "the overview lists #4821 first under Needs a reply")) return;
      view.cursor.index = view.paneFirstStop;
      break;
    case 97:
      // The overview row's priority word and late wait, on the row's fill
      // under the cursor.
      var overviewRow = shell.find(view.overview, "awaiting-4821");
      if (!check(overviewRow.hasCursor, "the cursor is on #4821's overview row")) return;
      var overviewPill = shell.find(overviewRow, "priorityPill");
      var surface = Qt.tint(Qt.tint(one.popup.cardItem.color, overviewRow.color), overviewPill.color);
      if (!shell.readsOn("the overview's priority word", overviewPill.children[0], surface,
                         Kit.FoamyPalette.onSurface(overviewPill.tone, Qt.tint(Kit.FoamyPalette.background, overviewPill.color)))) return;
      var wait = shell.find(overviewRow, "age");
      if (!shell.readsOn("the overview's late wait", wait, Qt.tint(one.popup.cardItem.color, overviewRow.color), Kit.FoamyPalette.onSurface(Kit.FoamyPalette.error))) return;
      shell.underCursor = { "the overview's priority word": overviewPill.children[0].color, "the overview's late wait": wait.color };
      view.cursor.reset();
      break;
    case 98:
      var overviewRow = shell.find(view.overview, "awaiting-4821");
      var overviewPill = shell.find(overviewRow, "priorityPill");
      if (!check(!overviewRow.hasCursor, "the cursor is off #4821's overview row")) return;
      if (!shell.keeps("the overview's priority word", overviewPill.children[0], Qt.tint(Qt.tint(one.popup.cardItem.color, overviewRow.color), overviewPill.color))) return;
      if (!shell.keeps("the overview's late wait", shell.find(overviewRow, "age"), Qt.tint(one.popup.cardItem.color, overviewRow.color))) return;
      // #4821 in the Wide pane, its row selected with the cursor.
      view.cursor.index = view.firstTicketStop;
      view.activateRequested();
      break;
    case 99:
      var paneEntry = view.pane.comments.children.find(function(item) { return item.model && item.model.internal; });
      if (!check(view.pane.visible && paneEntry, "the pane shows #4821 with its internal note")) return;
      if (!shell.readsOn("the pane's Internal note label", shell.find(paneEntry, "noteLabel"), Qt.tint(one.popup.cardItem.color, shell.find(paneEntry, "bubble").color),
                         Kit.FoamyPalette.onSurface(Kit.FoamyPalette.warning))) return;
      // The selected row's soft status tag and priority word, on the
      // selected fill under the cursor.
      var row = shell.find(view, "ticket-4821");
      if (!check(row.selected && row.bodyItem.hasCursor, "#4821's row is selected and has the cursor")) return;
      var rowSurface = Qt.tint(one.popup.cardItem.color, row.bodyItem.color);
      var tag = shell.find(row, "statusTag");
      var pill = shell.find(row, "priorityPill");
      if (!shell.readsOn("the selected row's status tag", tag.children[0], Qt.tint(rowSurface, tag.color),
                         Status.softInk(tag.tone, Kit.FoamyPalette.text, Kit.FoamyPalette.background, tag.softAlpha))) return;
      if (!shell.readsOn("the selected row's priority word", pill.children[0], Qt.tint(rowSurface, pill.color), row.priorityTone)) return;
      shell.underCursor = { "the selected row's status tag": tag.children[0].color, "the selected row's priority word": pill.children[0].color };
      view.cursor.reset();
      break;
    case 100:
      var row = shell.find(view, "ticket-4821");
      if (!check(row.selected && !row.bodyItem.hasCursor, "#4821's row is selected, without the cursor")) return;
      var rowSurface = Qt.tint(one.popup.cardItem.color, row.bodyItem.color);
      var tag = shell.find(row, "statusTag");
      var pill = shell.find(row, "priorityPill");
      if (!shell.keeps("the selected row's status tag", tag.children[0], Qt.tint(rowSurface, tag.color))) return;
      if (!shell.keeps("the selected row's priority word", pill.children[0], Qt.tint(rowSurface, pill.color))) return;
      // Small opens the ticket shown in the pane in place, with the cursor
      // on its header (step 101 waits).
      view.cursor.index = view.firstTicketStop;
      one.prefs.save("panelWidth", "standard");
      break;
    case 101:
      // The open card: the note label on its tinted surface, and the
      // triangle and the priority word on the header with and without the
      // cursor.
      var row = shell.find(view, "ticket-4821");
      var noteEntry = row.historyRepeater.itemAt(0);
      if (!check(row.expanded && noteEntry.internal, "#4821 is open in Small with its internal note (open: " + view.expandedIds.join() + ")")) return;
      var frame = shell.find(row, "frame").color;
      if (!shell.readsOn("the open card's Internal note label", shell.find(noteEntry, "noteLabel"), Qt.tint(frame, shell.find(noteEntry, "noteSurface").color),
                         Kit.FoamyPalette.onSurface(Kit.FoamyPalette.warning))) return;
      var pill = shell.find(row, "priorityPill");
      var triangle = shell.find(row, "disclosure");
      if (!check(row.bodyItem.hasCursor, "the cursor is on #4821's header")) return;
      if (!shell.readsOn("the open card's triangle", triangle, Qt.tint(frame, row.bodyItem.color), Kit.FoamyPalette.onSurface(row.statusColor))) return;
      if (!shell.readsOn("the priority word under the cursor", pill.children[0], Qt.tint(Qt.tint(frame, row.bodyItem.color), pill.color), row.priorityTone)) return;
      shell.underCursor = { "the open card's triangle": triangle.color, "the priority word": pill.children[0].color };
      view.cursor.reset();
      break;
    case 102:
      var row = shell.find(view, "ticket-4821");
      var frame = shell.find(row, "frame").color;
      var pill = shell.find(row, "priorityPill");
      if (!check(!row.bodyItem.hasCursor, "the cursor is off #4821's header")) return;
      if (!shell.readsOn("the priority word at rest", pill.children[0], Qt.tint(Qt.tint(frame, row.bodyItem.color), pill.color), row.priorityTone)) return;
      if (!shell.keeps("the priority word", pill.children[0], Qt.tint(Qt.tint(frame, row.bodyItem.color), pill.color))) return;
      if (!shell.keeps("the open card's triangle", shell.find(row, "disclosure"), Qt.tint(frame, row.bodyItem.color))) return;
      // #4821 closed again, with the cursor on its row.
      view.toggleTicket("4821");
      view.cursor.index = view.firstTicketStop;
      break;
    case 103:
      // A closed one-line row under the cursor: its triangle and its
      // priority word on the cursor's fill (an Open row shows no status tag).
      var row = shell.find(view, "ticket-4821");
      if (!check(!row.expanded && !row.selected && row.oneLine && row.bodyItem.hasCursor, "#4821 is closed on one line, with the cursor on its row")) return;
      var rowSurface = Qt.tint(one.popup.cardItem.color, row.bodyItem.color);
      var pill = shell.find(row, "linePriority");
      if (!shell.readsOn("the closed row's triangle", shell.find(row, "disclosure"), rowSurface, Kit.FoamyPalette.onSurface(row.statusColor))) return;
      if (!shell.readsOn("the closed row's priority word", pill.children[0], Qt.tint(rowSurface, pill.color), row.priorityTone)) return;
      // The theme from before step 93 (step 104 waits for its colours).
      if (!shell.applyTheme(shell.savedTheme)) return;
      break;
    case 104:
      themeFile.reload();
      if (!check(themeFile.text() === shell.savedTheme, "the theme file is back as it was before step 93")) return;
      shell.finished = true;
      console.log("FOAMY DONE runtime interactions passed"); Qt.quit();
    }
  }
}
"""

# Stands in for the browser: logs the URL, then does what $FOAMY_OUT/xdg-open.mode
# says: "fail" exits 3 (xdg-open's "no handler"), "lock" makes the lockable
# read folder read-only first, "hold" waits (at most 4 s) for xdg-open.release.
FAKE_OPENER = r"""#!/bin/sh
printf '%s\n' "$1" >>"$FOAMY_OUT/opened.log"
case $(cat "$FOAMY_OUT/xdg-open.mode" 2>/dev/null) in
fail) exit 3 ;;
lock) chmod 0555 "$FOAMY_OUT/lockable" ;;
hold)
  i=0
  while [ ! -e "$FOAMY_OUT/xdg-open.release" ] && [ "$i" -lt 80 ]; do
    sleep 0.05
    i=$((i + 1))
  done
  ;;
esac
exit 0
"""

# Stands in for `omarchy bar set`, the settings save without the inline save
# (steps 92 and 93): with $FOAMY_OUT/omarchy.mode "hold" it waits (at most
# 10 s) for omarchy.release and fails. Otherwise it is any other host
# command: refused and logged as the harness's stub does (run.host_commands()).
FAKE_OMARCHY = r"""#!/bin/sh
if [ "$(cat "$FOAMY_OUT/omarchy.mode" 2>/dev/null)" != hold ]; then
  printf '%s\n' "omarchy $*" >>"$FOAMY_OUT/host-commands.log"
  exit 127
fi
i=0
while [ ! -e "$FOAMY_OUT/omarchy.release" ] && [ "$i" -lt 200 ]; do
  sleep 0.05
  i=$((i + 1))
done
exit 1
"""

# The read file the "broken" account names (steps 22 to 24): it holds a
# marker but can't be read. Write-only, so an atomic save could still replace
# it (a file that can't be written can't be). Root reads it anyway, so the
# steps would prove nothing.
BROKEN_READ = '{"version":1,"read":{"9001":{"revision":90010,"at":1}}}\n'
if os.geteuid() == 0:
    print("FAIL: run tests/runtime.py as a normal user; root can read a write-only file")
    sys.exit(1)

run = harness.Run(
    "4.5",
    SHELL,
    plugin=plugin,
    prefix="foamy-zendesk-runtime-",
    fakebin={"xdg-open": FAKE_OPENER, "omarchy": FAKE_OMARCHY},
)
broken = run.out / "read-broken.json"
try:
    broken.write_text(BROKEN_READ)
    broken.chmod(0o200)
    # Ticket 9501 is read up to its only comment (steps 69 and 70).
    (run.out / "read-preread.json").write_text('{"version":1,"read":{"9501":{"revision":95010,"at":1}}}\n')
    # The read-only state folder for the failed saves (steps 27 to 32), and
    # the one the fake opener locks (steps 42 to 46).
    (run.out / "locked").mkdir(mode=0o555)
    (run.out / "lockable").mkdir()
    shutil.copyfile(kit / "tests/fixtures/themes/dim-red.toml", run.out / "dim-red.toml")
    shutil.copyfile(kit / "preview/themes/light.toml", run.out / "light.toml")
    run.run(timeout=90)
    if os.environ.get("FOAMY_TEST_OUTPUT"):
        output = Path(os.environ["FOAMY_TEST_OUTPUT"])
        output.mkdir(parents=True, exist_ok=True)
        for image in run.out.glob("*.png"):
            shutil.copyfile(image, output / image.name)
    # Every host command the plugin runs has a stand-in here (the helper,
    # links, notifications); one that reached the harness's stub is a defect.
    refused = run.host_commands()
    if refused:
        print("FAIL: the plugin ran host commands:", *refused, sep="\n  ")
        sys.exit(1)
    if run.ok:
        # An atomic save would have replaced the file (and its mode).
        mode = broken.stat().st_mode & 0o777
        broken.chmod(0o600)
        if mode != 0o200 or broken.read_text() != BROKEN_READ:
            print("FAIL: the unreadable read file was written over")
            sys.exit(1)
    # A binding loop is a defect even when the value comes out right: it
    # writes a warning to the shell log on every pass (as a snooze without a
    # weekly schedule once did, step 30).
    loops = sorted({line.strip() for line in run.log.splitlines() if "Binding loop detected" in line})
    if run.ok and loops:
        print("FAIL: QML binding loops:", *loops, sep="\n  ")
        sys.exit(1)
    print(run.log if not run.ok else "PASS: real plugin runtime interactions")
    sys.exit(0 if run.ok else 1)
finally:
    # The fake opener may have left it read-only, with the read file inside.
    (run.out / "lockable").chmod(0o755)
    if broken.exists():
        broken.chmod(0o600)
    run.cleanup()
