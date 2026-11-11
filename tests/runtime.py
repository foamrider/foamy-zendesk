"""Run the real plugin, singletons and UI in foamy-kit's isolated offscreen shell.

The account check runs the real helper (the isolated session has no keyring,
so it reports that); the inbox is then filled from preview/Fixtures.js, as if
signed in, and ticket links go to a stub instead of a browser.

  python3 tests/runtime.py [4.5|4.0]

The host is Omarchy 4.5, the installed /usr/share/omarchy/shell
(FOAMY_HOST_45 picks another 4.5 tree). 4.0 runs only when FOAMY_HOST_40
names a 4.0 shell tree; otherwise it prints a SKIP line.
"""
import os
import shutil
import sys
from pathlib import Path

plugin = Path(__file__).resolve().parents[1]
# The sibling checkout, else the usual one (a worktree has no sibling kit).
kit = Path(os.environ.get("FOAMY_KIT") or next(
    (p for p in (plugin.parent / "foamy-kit", Path.home() / "GitHub/Personal/foamy-kit") if p.is_dir()),
    plugin.parent / "foamy-kit"))
# Set before the harness reads them.
os.environ.setdefault("FOAMY_HOST_45", "/usr/share/omarchy/shell")
sys.path.insert(0, str(kit / "preview"))
import harness

SHELL = r'''
import QtQuick
import QtTest
import Quickshell
import "harness"
import "plugin" as Plugin
import "plugin/kit" as Kit
import "plugin/preview/Fixtures.js" as Fixtures
import "plugin/Model.js" as Model
ShellRoot {
  id: shell
  property int step: 0
  property real savedY: 0
  property string savedBody: ""
  property real savedScroll: 0
  property int waited: 0
  property int fetchProbe: 0
  property var opened: []
  property var sent: []
  property var fetches: []
  // The shell reflects saved settings back to every instance, like the host.
  property var entry: ({})
  TestEvent { id: ev }
  function find(item, name) {
    if (!item) return null;
    if (item.objectName === name) return item;
    for (var child of item.children) { var hit = find(child, name); if (hit) return hit; }
    return null;
  }
  function check(ok, message) {
    if (!ok) { console.log("FOAMY FAIL " + message); Qt.quit(); }
    return ok;
  }
  // A stand-in helper: "now" replies at once, "slow" after a second;
  // "late" replies only when stopped (a full reply already on its way),
  // "stopped" then exits 143 with nothing.
  function fake(mode, reply) {
    var script = mode === "now" ? "printf '%s\\n' \"$1\""
      : mode === "slow" ? "sleep 1; printf '%s\\n' \"$1\""
      : "trap 'kill $! 2>/dev/null; " + (mode === "late" ? "printf \"%s\\n\" \"$1\"; exit 0" : "exit 143") + "' TERM; sleep 30 & wait";
    return ["sh", "-c", script, "fake", JSON.stringify(reply)];
  }
  function inboxReply(address, id) {
    return { ok: true, state_path: Quickshell.env("FOAMY_OUT") + "/read-" + address + ".json",
             tickets: [{ id: String(id), subject: "Ticket " + id, status: "Open", priority: "Normal", assignee: "Alex", mine: true,
                         group: "IT support", requester: "Jonas", updated_at: "2026-11-06T10:00:00Z",
                         comments: [{ id: id * 10, author: "Jonas", mine: false, public: true, created: Fixtures.BASE, body: "Hello." }] }] };
  }
  function many() {
    var list = Fixtures.tickets();
    for (var i = 1; i <= 10; i++) list = list.concat([Fixtures.update(i, true)[0]]);
    return list;
  }
  FloatingWindow {
    implicitWidth: 1920; implicitHeight: 1080
    ScreenSim { fullScreenBar: true }
    Plugin.Panel { id: one; settings: shell.entry; x: 1400; y: 4; width: 45; height: 26 }
    Plugin.Panel { id: two; settings: shell.entry; x: 1450; y: 4; width: 45; height: 26 }
  }
  MockBar {
    id: bar
    onSavedChanged: if (saved.length) shell.entry = saved[saved.length - 1].settings
  }
  Component.onCompleted: {
    for (var panel of [one, two]) { panel.bar = bar; panel.moduleName = "foamy.zendesk"; }
    Plugin.TicketStore.openUrl = function(url) { shell.opened = shell.opened.concat([url]); };
    tick.start();
  }
  Timer {
    id: tick
    interval: 150
    repeat: true
    onTriggered: {
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
        one.prefs.save("zendeskAddress", "acme");
        one.prefs.save("oauthClientId", "foamy-test");
        break;
      case 1:
        // The real helper runs; the isolated session has no keyring, so it says so.
        if (account.busy || account.state === "checking") { shell.step--; if (++shell.waited > 160) check(false, "auth-status finished"); return; }
        if (!check(account.state === "error" && account.error.indexOf("keyring") >= 0, "a missing keyring is explained (" + account.state + ": " + account.error + ")")) return;
        if (!check(!store.active, "nothing is fetched without a sign-in")) return;
        // From here on: signed in, with the sample inbox.
        store.loadFixtures(Fixtures.tickets());
        account.state = "signed_in";
        account.user = { name: "Alex", email: "alex@acme.example" };
        if (!check(store.count === 3 && store.unreadCount === 3, "fixture inbox loaded")) return;
        if (!check(one.barContent.countLabel.visible && one.barContent.countLabel.text === "3" && one.barContent.icon.known
                   && one.barContent.countLabel.color == bar.urgent && one.barContent.icon.color == button.foreground, "bar badge counts unread tickets")) return;
        button.grabToImage(function(result) { result.saveToFile(Quickshell.env("FOAMY_OUT") + "/bar.png"); });
        button.triggerPress(Qt.LeftButton);
        shell.waited = 0;
        break;
      case 2:
        // The header lays out its actions once the popup is shown (a 0 ms
        // timer); under load that can come after this tick.
        if (!view || !view.band.settingsInMenu) { shell.step--; if (++shell.waited > 40) check(false, "the popup's header laid out"); return; }
        if (!check(view !== null && view.repeater.count === 3, "real popup loads ticket cards")) return;
        // Rows are dated against the wall clock, or the preview's fixed time.
        var dated = shell.find(view, "ticket-4824");
        if (!check(dated !== null && Math.abs(dated.now - Date.now()) < 120000, "rows date against the wall clock")) return;
        view.fixedNow = Fixtures.NOW;
        if (!check(dated.now === Fixtures.NOW && dated.when(Fixtures.BASE - 26 * 3600000) === "Yesterday"
                   && dated.when(Fixtures.BASE) === dated.format(Fixtures.BASE, "HH:mm"), "a fixed time dates the rows")) return;
        view.fixedNow = 0;
        if (!check(Math.abs(dated.now - Date.now()) < 120000, "back on the wall clock")) return;
        if (!check(shell.find(view, "emptyState").visible === false && view.band.meta.indexOf("3 unread") === 0, "header counts unread")) return;
        if (!check(view.band.settingsInMenu && view.band.menuItems[0].iconName === "moon" && view.band.menuItems[0].text === "Snooze until tomorrow",
                   "Snooze and Settings are in the ⋯ menu")) return;
        for (var m = 0; m < 3; m++) view.moveRequested(0, 1);
        if (!check(view.cursor.index === view.firstTicketStop, "keyboard walks Mark all and ⋯ before tickets")) return;
        var closed = view.repeater.itemAt(0);
        if (!check(closed.unreadDot.visible && !closed.frameItem.visible && closed.bodyItem.height === closed.bodyItem.parent.height,
                   "closed, an unread ticket has the dot and the whole card is its target")) return;
        // A real click low on the closed card, on its latest comment, opens it.
        ev.mouseClick(closed.bodyItem, closed.bodyItem.width / 3, closed.bodyItem.height - 12, Qt.LeftButton, Qt.NoModifier, -1);
        break;
      case 3:
        var card = view.repeater.itemAt(0);
        if (!check(card.expanded && card.detailsItem.visible && store.reading, "click expands the ticket")) return;
        if (!check(card.commentItem.textFormat === Text.PlainText, "comments use plain text")) return;
        if (!check(card.historyRepeater.count === 4 && card.historyRepeater.itemAt(1).textItem.text.indexOf("restart the client") >= 0, "expanded history includes the agent's reply")) return;
        if (!check(card.shownCount === 3 && !card.historyRepeater.itemAt(3).visible && card.moreButton.visible, "the timeline shows the unread comments and the one before them")) return;
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
                   && !card.historyRepeater.itemAt(1).full && card.shownCount === 3, "Show more expands only that comment")) return;
        click(longest.lengthButton);
        if (!check(card.expanded && !longest.full && longest.clipped && longest.lengthButton.text === "Show more", "Show less folds it back")) return;
        if (!check(card.showMore() && longest.full, "m shows the clipped comment in full first")) return;
        ev.mouseClick(card.moreButton, card.moreButton.width / 2, card.moreButton.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
        if (!check(card.expanded && card.showEarlier && card.historyRepeater.itemAt(3).visible && !card.moreButton.visible
                   && !card.historyRepeater.itemAt(3).full, "Show earlier lists the rest without expanding them, and the ticket stays open")) return;
        if (!check(!card.showMore(), "m has nothing more to show")) return;
        if (!check(card.historyRepeater.itemAt(0).textItem.textFormat === Text.PlainText, "history uses plain text")) return;
        if (!check(card.read && store.unreadCount === 2 && one.barContent.countLabel.text === "2", "opening a ticket marks it read")) return;
        if (!check(card.openedUpdates === 2 && card.historyRepeater.itemAt(0).fresh && !card.historyRepeater.itemAt(1).fresh && card.historyRepeater.itemAt(2).fresh,
                   "the opened ticket still marks what was new; my reply never is")) return;
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
        if (!check(shell.opened.length === 1 && shell.opened[0] === "https://acme.zendesk.com/agent/tickets/4821" && card.expanded,
                   "View opens the ticket in Zendesk; it stays open")) return;
        // A real click on the header band (left of the actions) closes it.
        ev.mouseClick(card.bodyItem, card.bodyItem.width / 3, card.bodyItem.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
        break;
      case 5:
        if (!check(store.pending === null && store.tickets.get(0).updates === 1 && store.tickets.get(0).history.count === 5, "collapse applies the waiting inbox; only the newer reply is unread")) return;
        if (!check(!view.repeater.itemAt(0).showEarlier, "collapsing forgets Show earlier")) return;
        view.repeater.itemAt(0).readButton.clicked();
        if (!check(store.count === 3 && store.unreadCount === 2 && view.repeater.itemAt(0).read && one.barContent.countLabel.text === "2", "Mark as read keeps the ticket and lowers the count")) return;
        if (!check(view.repeater.itemAt(0).compact && !view.repeater.itemAt(0).unreadDot.visible && shell.find(view.repeater.itemAt(0), "when").text.indexOf("Anna · ") === 0,
                   "a read ticket takes one line: no unread dot, the sender and time by the subject")) return;
        view.cursor.reset();
        if (!check(!view.repeater.itemAt(0).readActionShown && view.repeater.itemAt(1).readActionShown && view.repeater.itemAt(0).readButton.visible,
                   "Mark as unread waits for hover, keeping its place; Mark as read stays shown")) return;
        view.cursor.index = view.firstTicketStop + 1;
        if (!check(view.repeater.itemAt(0).readActionShown, "the keyboard cursor shows Mark as unread")) return;
        view.repeater.itemAt(0).readButton.clicked();
        if (!check(store.unreadCount === 3 && !view.repeater.itemAt(0).read && view.repeater.itemAt(0).unread === 1, "Mark as unread brings back the newest reply")) return;
        view.markAllRead();
        if (!check(store.count === 3 && store.unreadCount === 0 && store.canUndoMarkAll && !one.barContent.countLabel.visible, "Mark all as read keeps every ticket")) return;
        view.cursor.index = view.settingsStop;
        view.moveRequested(0, -1);
        if (!check(view.cursor.index !== view.markAllStop, "keyboard skips the disabled Mark all")) return;
        store.undoMarkAll();
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
        // Positioners lay out on the next frame; check sizes a tick later.
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
        store.error = "Can't reach Zendesk. Check your connection.";
        var footer = view.children.find(function(item) { return item.hasOwnProperty("statusError"); });
        if (!check(footer && footer.statusError && footer.status.indexOf("Can't reach") === 0 && store.count === 3, "a failed refresh keeps the tickets and says why")) return;
        store.error = "";
        store.loadFixtures(shell.many());
        account.state = "signed_in";
        break;
      case 9:
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
        one.close();
        break;
      case 12:
        if (shell.fetchProbe === 1) {
          // Let the on-demand fetch end (the isolated session has no keyring), then go back to the sample inbox.
          if (store.fetchProcess.running) { shell.step--; if (++shell.waited > 160) check(false, "the on-demand fetch finished"); return; }
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
          shell.waited = 0;
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
        // Signed out: the inbox asks for a sign-in.
        account.state = "signed_out";
        store.loadFixtures(null);
        one.open();
        break;
      case 13:
        var empty = shell.find(view, "emptyState");
        if (!check(empty.visible && empty.kind === "signin" && shell.find(view, "openSettings").visible, "signed out, the inbox offers the settings")) return;
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
        // The buttons' IPC: a newer reply (here: after the one announced) stays unread.
        store.receive(Fixtures.update(3, false));
        shell.sent = shell.sent.slice(0, 1);
        shell.opened = [];
        store.viewInZendesk("acme.zendesk.com/4821:48215");
        if (!check(shell.opened[0] === "https://acme.zendesk.com/agent/tickets/4821" && store.ticketById("4821").ticket.updates === 1,
                   "View in Zendesk opens it and reads up to the reply shown")) return;
        store.markReadUpTo("acme.zendesk.com/4821:48216,4824:48241,junk");
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
        one.prefs.save("notify", "off");
        store.receive(Fixtures.update(6, false));
        if (!check(shell.sent.length === 2, "off: nothing is announced")) return;
        // The notification's click (the show IPC): the inbox with that ticket open and read.
        one.showNotified("acme.zendesk.com/4824");
        if (!check(one.opened && view.expandedIds.length === 1 && view.expandedIds[0] === "4824" && !view.editingSettings
                   && store.ticketById("4824").ticket.read, "show opens the inbox on the ticket and marks it read")) return;
        one.close();
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
        shell.opened = [];
        store.markReadUpTo("acme.zendesk.com/4821:48299,4824:48241");
        store.viewInZendesk("acme.zendesk.com/4818:48181");
        store.markReadUpTo("4821:48213");
        store.viewInZendesk("4818:48181");
        if (!check(shell.opened.length === 0 && store.unreadCount === 3 && Object.keys(store.state.read).length === 0,
                   "another account's (or an older) notification marks nothing read and opens nothing")) return;
        one.showNotified("acme.zendesk.com/4824");
        if (!check(one.opened && view.expandedIds.length === 0 && !store.ticketById("4824").ticket.read, "its click opens only the inbox")) return;
        one.close();
        store.viewInZendesk("globex.zendesk.com/4818:48181");
        store.markReadUpTo("globex.zendesk.com/4824:48241");
        if (!check(shell.opened.length === 1 && shell.opened[0] === "https://globex.zendesk.com/agent/tickets/4818"
                   && store.ticketById("4818").ticket.read && store.ticketById("4824").ticket.read && store.unreadCount === 1,
                   "this account's notifications still work")) return;
        break;
      case 16:
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
        // As in step 1: the check's process can be gone a tick before its
        // reply is applied; a reply applied after the fields set below would
        // sign the stand-in accounts out ("no keyring").
        if (account.busy || account.state === "checking") { shell.step--; if (++shell.waited > 160) check(false, "the account check finished"); return; }
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
        shell.waited = 0;
        break;
      case 18:
        if (shell.fetches.length < 2 || !store.fetchProcess.running) { shell.step--; if (++shell.waited > 40) check(false, "the new account's fetch started"); return; }
        if (!check(store.error === "" && store.failures === 0 && store.retryAt === 0 && store.pollTimer.interval === store.refreshSeconds * 1000,
                   "a fetch stopped by an account switch (143) is no error and doubles no poll interval (" + store.error + ")")) return;
        account.address = "initech";
        shell.waited = 0;
        break;
      case 19:
        // The previous account's full reply came in as it was stopped; its
        // exit starts the next account's fetch (a process exit and a start:
        // under load, more than one tick).
        if (shell.fetches.length < 3) { shell.step--; if (++shell.waited > 40) check(false, "the next account's fetch started"); return; }
        if (!check(shell.fetches.length === 3 && store.fetchProcess.running, "the next account's fetch is under way")) return;
        if (!check(store.count === 0 && !store.loaded && store.readPath === "" && store.error === "" && store.failures === 0,
                   "the previous account's late reply is ignored (" + store.count + " tickets, " + store.readPath + ")")) return;
        shell.waited = 0;
        break;
      case 20:
        if (!store.loaded) { shell.step--; if (++shell.waited > 40) check(false, "the new account's inbox arrived"); return; }
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
        shell.waited = 0;
        break;
      case 22:
        if (account.busy || account.state === "waiting" || account.state === "checking") { shell.step--; if (++shell.waited > 40) check(false, "the new address was checked (" + account.state + ")"); return; }
        if (!check(account.state === "signed_in" && account.user && account.user.name === "New" && account.address === "newco",
                   "a sign-in stopped by another address never signs that address in; the new address is checked (" + account.state + ", " + JSON.stringify(account.user) + ")")) return;
        console.log("FOAMY DONE runtime interactions passed"); Qt.quit();
      }
    }
  }
}
'''

host = sys.argv[1] if len(sys.argv) > 1 else "4.5"
if host == "4.0" and not os.environ.get("FOAMY_HOST_40"):
    print("4.0: SKIP (set FOAMY_HOST_40 to a 4.0 shell tree to run it)")
    sys.exit(0)
run = harness.Run(host, SHELL, plugin=plugin, prefix="foamy-zendesk-runtime-")
try:
    run.run(timeout=60)
    if os.environ.get("FOAMY_TEST_OUTPUT"):
        output = Path(os.environ["FOAMY_TEST_OUTPUT"])
        output.mkdir(parents=True, exist_ok=True)
        for image in run.out.glob("*.png"):
            shutil.copyfile(image, output / image.name)
    print(run.log if not run.ok else "PASS: real plugin runtime interactions")
    sys.exit(0 if run.ok else 1)
finally:
    run.cleanup()
