"""Run the real plugin, singletons and UI in foamy-kit's isolated offscreen shell.

The account check runs the real helper (the isolated session has no keyring,
so it reports that); the inbox is then filled from preview/Fixtures.js, as if
signed in, and ticket links go to a stub instead of a browser.
"""
import os
import shutil
import sys
from pathlib import Path

plugin = Path(__file__).resolve().parents[1]
kit = Path(os.environ.get("FOAMY_KIT", plugin.parent / "foamy-kit"))
sys.path.insert(0, str(kit / "preview"))
import harness

SHELL = r'''
import QtQuick
import Quickshell
import "harness"
import "plugin" as Plugin
import "plugin/kit" as Kit
import "plugin/preview/Fixtures.js" as Fixtures
ShellRoot {
  id: shell
  property int step: 0
  property real savedY: 0
  property string savedBody: ""
  property string railUnread: ""
  property real savedScroll: 0
  property int waited: 0
  property var opened: []
  // The shell reflects saved settings back to every instance, like the host.
  property var entry: ({})
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
        account.user = { name: "Tomas", email: "tomas@acme.example" };
        if (!check(store.count === 3 && store.unreadCount === 3, "fixture inbox loaded")) return;
        if (!check(one.barContent.countLabel.visible && one.barContent.countLabel.text === "3" && one.barContent.icon.known
                   && one.barContent.countLabel.color == bar.urgent && one.barContent.icon.color == button.foreground, "bar badge counts unread tickets")) return;
        button.grabToImage(function(result) { result.saveToFile(Quickshell.env("FOAMY_OUT") + "/bar.png"); });
        button.triggerPress(Qt.LeftButton);
        break;
      case 2:
        if (!check(view !== null && view.repeater.count === 3, "real popup loads ticket cards")) return;
        if (!check(shell.find(view, "emptyState").visible === false && view.band.meta.indexOf("3 unread") === 0, "header counts unread")) return;
        for (var m = 0; m < 3; m++) view.moveRequested(0, 1);
        if (!check(view.cursor.index === view.firstTicketStop, "keyboard walks Mark all and settings before tickets")) return;
        view.repeater.itemAt(0).bodyItem.clicked();
        break;
      case 3:
        var card = view.repeater.itemAt(0);
        if (!check(card.expanded && card.detailsItem.visible && store.reading, "click expands the ticket")) return;
        if (!check(card.commentItem.textFormat === Text.PlainText, "comments use plain text")) return;
        if (!check(card.historyRepeater.count === 4 && card.historyRepeater.itemAt(1).textItem.text.indexOf("restart the client") >= 0, "expanded history includes the agent's reply")) return;
        if (!check(card.shownCount === 3 && !card.historyRepeater.itemAt(3).visible && card.moreButton.visible, "the timeline shows the unread comments and the one before them")) return;
        card.moreButton.clicked();
        if (!check(card.showAll && card.historyRepeater.itemAt(3).visible && !card.moreButton.visible, "Show earlier reveals the rest")) return;
        shell.railUnread = String(shell.find(view.repeater.itemAt(1), "rail").color);
        if (!check(card.historyRepeater.itemAt(0).textItem.textFormat === Text.PlainText, "history uses plain text")) return;
        if (!check(card.read && store.unreadCount === 2 && one.barContent.countLabel.text === "2", "opening a ticket marks it read")) return;
        if (!check(card.openedUpdates === 2 && card.historyRepeater.itemAt(0).fresh && !card.historyRepeater.itemAt(1).fresh && card.historyRepeater.itemAt(2).fresh,
                   "the opened ticket still marks what was new; my reply never is")) return;
        if (!check(store.tickets.get(0).id === "4821" && String(shell.find(card, "rail").color) !== shell.railUnread, "it stays in place, without the unread rail")) return;
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
        card.bodyItem.clicked();
        break;
      case 5:
        if (!check(store.pending === null && store.tickets.get(0).updates === 1 && store.tickets.get(0).history.count === 5, "collapse applies the waiting inbox; only the newer reply is unread")) return;
        if (!check(!view.repeater.itemAt(0).showAll, "collapsing forgets Show earlier")) return;
        view.repeater.itemAt(0).readButton.clicked();
        if (!check(store.count === 3 && store.unreadCount === 2 && view.repeater.itemAt(0).read && one.barContent.countLabel.text === "2", "Mark as read keeps the ticket and lowers the count")) return;
        if (!check(view.repeater.itemAt(0).compact && String(shell.find(view.repeater.itemAt(0), "rail").color) !== shell.railUnread, "a read ticket takes one line and loses the unread rail")) return;
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
        if (!check(waitingRow.bodyItem.height >= shell.savedY && waitingRow.detailsItem.visible, "an expanded waiting ticket shows in full")) return;
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
        if (!check(!store.reading && store.pending === null, "closing releases the waiting inbox")) return;
        one.prefs.save("scheduleEnabled", true);
        // The default week has no days, so the schedule is off right now.
        if (!check(!store.withinSchedule && button.dimmed && one.visible && two.visible && !store.active, "outside the schedule the widget dims and nothing is fetched")) return;
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
        console.log("FOAMY DONE runtime interactions passed"); Qt.quit();
      }
    }
  }
}
'''

host = sys.argv[1] if len(sys.argv) > 1 else "4.5"
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
