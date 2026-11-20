import QtQuick
import qs.Commons as Commons
import "../kit"
import ".." as Plugin
import "Fixtures.js" as Fixtures

Item {
  id: preview
  required property QtObject bar
  required property Item anchorItem
  property var previewStates: ["tickets", "expanded", "pending", "all-read", "hide-read", "grouped", "grouped-expanded", "signed-out", "loading", "failed", "offline", "empty", "settings", "connection", "schedule", "outside-schedule", "narrow", "narrow-expanded", "focused", "scrolling", "menu", "wide", "wide-ticket", "wide-pending", "wide-focused", "wide-conversation", "wide-empty", "wide-settings"]
  property string previewState: "tickets"
  readonly property var popup: previewPopup
  // Wide: the list and the reading pane (Panel.qml's wideWidth).
  readonly property bool wide: previewState.indexOf("wide") === 0

  function many() {
    var list = Fixtures.tickets()
    for (var i = 1; i <= 10; i++)
      list = list.concat([Fixtures.update(i, true)[0]])
    return list
  }

  function applyState() {
    var view = popup.ensureBody()
    if (!view)
      return
    var store = Plugin.TicketStore
    var account = Plugin.ZendeskAccount
    view.closeReading()
    view.editingSettings = false
    view.wide = preview.wide
    // The ⋯ menu: Snooze, then Settings.
    if (previewState === "menu")
      Qt.callLater(function () {
        view.band.openMenu(false)
      })
    // Rows are dated against the fixtures' time, not the render's.
    view.fixedNow = Fixtures.NOW
    store.openUrl = function (url) {
      console.log("preview: would open " + url)
    }
    store.hideRead = previewState === "hide-read"
    store.unreadFirst = false
    store.groupWaiting = true
    // An empty week with the schedule on is "outside" at any time.
    store.scheduleEnabled = previewState === "outside-schedule"
    store.week = ["", "", "", "", "", "", ""]

    var signedIn = previewState !== "signed-out" && previewState !== "connection"
    var sample = ["signed-out", "loading", "failed", "empty"].indexOf(previewState) >= 0 ? null : previewState === "scrolling" ? many() : Fixtures.tickets()
    if (previewState === "wide-empty")
      sample = []
    store.loadFixtures(sample)
    if (previewState === "empty")
      store.loadFixtures([])
    account.address = signedIn ? "acme" : ""
    account.clientId = signedIn ? "foamy_zendesk" : ""
    account.port = signedIn ? 47823 : 0
    account.state = signedIn ? "signed_in" : "not_configured"
    account.user = signedIn ? {
      name: "Alex",
      email: "alex@acme.example"
    } : null
    account.verified = signedIn
    view.preferences = signedIn ? {
      zendeskAddress: "acme",
      oauthClientId: "foamy_zendesk"
    } : previewState === "schedule" ? {
      scheduleEnabled: true,
      scheduleOutsideMode: "mute",
      scheduleMonday: "08:00-16:00",
      scheduleTuesday: "08:00-16:00",
      scheduleWednesday: "08:00-16:00",
      scheduleThursday: "08:00-16:00",
      scheduleFriday: "08:00-14:00"
    } : ({})
    if (previewState === "schedule")
      view.preferences = Object.assign({}, view.preferences, {
        zendeskAddress: "acme",
        oauthClientId: "foamy_zendesk",
        scheduleEnabled: true,
        scheduleOutsideMode: "mute",
        scheduleMonday: "08:00-16:00",
        scheduleTuesday: "08:00-16:00",
        scheduleWednesday: "08:00-16:00",
        scheduleThursday: "08:00-16:00",
        scheduleFriday: "08:00-14:00"
      })
    if (preview.wide)
      view.preferences = Object.assign({}, view.preferences, {
        panelWidth: "wide"
      })
    if (previewState === "failed" || previewState === "offline")
      store.error = "Can't reach Zendesk. Check your connection."
    view.list.contentY = 0

    // A typical inbox: #4818 (waiting on its requester) was read earlier.
    if (sample && previewState !== "all-read")
      store.markRead("4818")
    if (previewState === "expanded" || previewState === "pending" || previewState === "narrow-expanded" || previewState === "wide-ticket" || previewState === "wide-pending" || previewState === "wide-conversation")
      view.toggleTicket("4821")
    if (previewState === "pending" || previewState === "wide-pending")
      Qt.callLater(function () {
        store.receive(Fixtures.update(1, false))
      })
    if (previewState === "all-read")
      view.markAllRead()
    if (previewState === "grouped-expanded")
      view.toggleTicket("4818")
    if (["settings", "connection", "schedule", "wide-settings"].indexOf(previewState) >= 0) {
      view.editingSettings = true
      if (previewState !== "settings" && previewState !== "wide-settings")
        Qt.callLater(function () {
          view.settingsPage.flickable.contentY = 9999
          view.settingsPage.flickable.returnToBounds()
        })
    }
    if (previewState === "focused")
      view.cursor.index = view.firstTicketStop
    // The overview's first waiting ticket under the keyboard cursor.
    if (previewState === "wide-focused")
      view.cursor.index = view.paneFirstStop
    // The keyboard cursor on the selected ticket's conversation.
    if (previewState === "wide-conversation")
      view.cursor.index = view.conversationStop
    if (previewState === "scrolling")
      Qt.callLater(function () {
        view.list.contentY = 160
      })
  }
  onPreviewStateChanged: Qt.callLater(applyState)
  Component.onCompleted: Qt.callLater(applyState)
  FoamyPopup {
    id: previewPopup
    anchorItem: preview.anchorItem
    bar: preview.bar
    open: true
    contentWidth: fittedContentWidth(preview.previewState.indexOf("narrow") === 0 ? 320 : preview.wide ? Commons.Style.space(880) : FoamyStyle.popupWidth)
    // As Panel.qml: Wide is one size.
    contentHeight: fittedContentHeight(Math.max(preview.wide ? FoamyStyle.popupMaxHeight : bodyImplicitHeight, menuReserve), maxHeight)
    body: Component {
      Plugin.InboxView {}
    }
  }
}
