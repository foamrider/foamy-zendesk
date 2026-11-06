import QtQuick
import "../kit"
import ".." as Plugin
import "Fixtures.js" as Fixtures

Item {
  id: preview
  required property QtObject bar
  required property Item anchorItem
  property var previewStates: ["tickets", "expanded", "pending", "all-read", "hide-read", "grouped", "grouped-expanded",
    "signed-out", "loading", "failed", "offline", "empty", "settings", "connection", "schedule", "outside-schedule",
    "narrow", "narrow-expanded", "focused", "scrolling"]
  property string previewState: "tickets"
  readonly property Item popup: popup

  function many() {
    var list = Fixtures.tickets();
    for (var i = 1; i <= 10; i++) list = list.concat([Fixtures.update(i, true)[0]]);
    return list;
  }

  function applyState() {
    var view = popup.ensureBody();
    if (!view) return;
    var store = Plugin.TicketStore;
    var account = Plugin.ZendeskAccount;
    view.closeReading();
    view.editingSettings = false;
    store.openUrl = function(url) { console.log("preview: would open " + url); };
    store.hideRead = previewState === "hide-read";
    store.unreadFirst = false;
    store.groupWaiting = true;
    // An empty week with the schedule on is "outside" at any time.
    store.scheduleEnabled = previewState === "outside-schedule";
    store.week = ["", "", "", "", "", "", ""];

    var signedIn = previewState !== "signed-out" && previewState !== "connection";
    var sample = ["signed-out", "loading", "failed", "empty"].indexOf(previewState) >= 0 ? null
      : previewState === "scrolling" ? many() : Fixtures.tickets();
    store.loadFixtures(sample);
    if (previewState === "empty") store.loadFixtures([]);
    account.address = signedIn ? "acme" : "";
    account.clientId = signedIn ? "foamy_zendesk" : "";
    account.port = signedIn ? 47823 : 0;
    account.state = signedIn ? "signed_in" : "not_configured";
    account.user = signedIn ? { name: "Tomas", email: "tomas@acme.example" } : null;
    account.verified = signedIn;
    view.preferences = signedIn ? { zendeskAddress: "acme", oauthClientId: "foamy_zendesk" }
      : previewState === "schedule" ? { scheduleEnabled: true, scheduleOutsideMode: "mute",
        scheduleMonday: "08:00-16:00", scheduleTuesday: "08:00-16:00", scheduleWednesday: "08:00-16:00",
        scheduleThursday: "08:00-16:00", scheduleFriday: "08:00-14:00" } : ({});
    if (previewState === "schedule") view.preferences = Object.assign({}, view.preferences, {
      zendeskAddress: "acme", oauthClientId: "foamy_zendesk", scheduleEnabled: true, scheduleOutsideMode: "mute",
      scheduleMonday: "08:00-16:00", scheduleTuesday: "08:00-16:00", scheduleWednesday: "08:00-16:00",
      scheduleThursday: "08:00-16:00", scheduleFriday: "08:00-14:00" });
    if (previewState === "failed" || previewState === "offline") store.error = "Can't reach Zendesk. Check your connection.";
    view.list.contentY = 0;

    // A typical inbox: #4818 (waiting on its requester) was read earlier.
    if (sample && previewState !== "all-read") store.markRead("4818");
    if (previewState === "expanded" || previewState === "pending" || previewState === "narrow-expanded") view.toggleTicket("4821");
    if (previewState === "pending") Qt.callLater(function() { store.receive(Fixtures.update(1, false)); });
    if (previewState === "all-read") view.markAllRead();
    if (previewState === "grouped-expanded") view.toggleTicket("4818");
    if (["settings", "connection", "schedule"].indexOf(previewState) >= 0) {
      view.editingSettings = true;
      if (previewState !== "settings") Qt.callLater(function() { view.settingsPage.flickable.contentY = 9999; view.settingsPage.flickable.returnToBounds(); });
    }
    if (previewState === "focused") view.cursor.index = view.firstTicketStop;
    if (previewState === "scrolling") Qt.callLater(function() { view.list.contentY = 160; });
  }
  onPreviewStateChanged: Qt.callLater(applyState)
  Component.onCompleted: Qt.callLater(applyState)
  FoamyPopup {
    id: popup
    anchorItem: preview.anchorItem
    bar: preview.bar
    open: true
    contentWidth: fittedContentWidth(preview.previewState.indexOf("narrow") === 0 ? 320 : FoamyStyle.popupWidth)
    body: Component { Plugin.InboxView {} }
  }
}
