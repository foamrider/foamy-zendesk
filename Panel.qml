pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "kit"
import "Preferences.js" as Schema
import "Model.js" as Model
import "kit/FoamySchedule.js" as Schedule

// One bar instance (4.5 draws one per monitor). The inbox lives in the
// TicketStore singleton; every instance pushes the saved settings into it
// and owns the IPC target. Any instance can save settings.
Ui.Panel {
  id: root
  ipcTarget: "foamy.zendesk"
  manageIpc: false
  readonly property alias popup: popup
  readonly property alias prefs: prefs
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  // Outside the schedule the widget dims, or hides unless its popup is open.
  visible: opened || TicketStore.withinSchedule || prefs.value("scheduleOutsideMode") !== "hide"
  // Wide is 880 wide (the list and the reading pane), where this bar's
  // screen has room for its width; elsewhere, and with the setting on Small,
  // the standard 420 and as tall as the inbox. Wide is 640 high whatever the
  // view shows (a ticket, the overview, Settings) and grows with the inbox
  // (InboxView.inboxImplicitHeight) up to 70 % of the screen, never under
  // 640, as foamy-todoist's Wide. preview/Preview.qml mirrors this.
  readonly property int wideWidth: Style.space(880)
  readonly property bool wide: prefs.value("panelWidth") === "wide" && root.popup.fittedContentWidth(wideWidth) >= wideWidth

  FoamyPrefsQueue {
    id: prefs
    bar: root.bar
    moduleName: root.moduleName
    fields: Schema.fields
    settings: root.settings
  }
  // Demand: this popup is open, so the store holds back notifications.
  FoamyMember {
    id: member
    scope: "zendesk"
    demanding: root.opened
  }
  // Whichever instance saves pushes at once, before the host reflects the value
  // back; every instance then pushes the same reflected settings.
  function pushSettings() {
    TicketStore.hideRead = prefs.value("hideRead")
    TicketStore.unreadFirst = prefs.value("unreadFirst")
    TicketStore.groupWaiting = prefs.value("groupWaiting")
    TicketStore.notify = prefs.value("notify")
    TicketStore.scheduleEnabled = prefs.value("scheduleEnabled")
    TicketStore.week = Schedule.week(prefs.effectiveSettings || ({}))
    TicketStore.refreshSeconds = prefs.value("refreshSeconds")
    ZendeskAccount.configure({
      address: String(prefs.value("zendeskAddress")).trim(),
      clientId: String(prefs.value("oauthClientId")).trim(),
      port: Number(prefs.value("oauthPort")) || Schema.defaultPort
    })
  }
  Connections {
    target: prefs
    function onEffectiveSettingsChanged() {
      root.pushSettings()
    }
  }
  Component.onCompleted: pushSettings()

  function openSettings() {
    root.open()
    var view = popup.ensureBody()
    if (view)
      view.editingSettings = true
  }
  // A notification's click: the inbox with that ticket open (and read).
  function showTicket(id) {
    root.open()
    var view = popup.ensureBody()
    if (view)
      view.showTicket(String(id))
  }
  // The show IPC, "host/id": that ticket, or only the inbox when the
  // notification came from another account.
  function showNotified(ticket) {
    var id = TicketStore.shownTicket(ticket)
    if (id)
      showTicket(id)
    else
      root.open()
  }
  FoamyIpc {
    enabled: member.isLeader
    target: "foamy.zendesk"
    function open(): void {
      root.open()
    }
    function close(): void {
      root.close()
    }
    function toggle(): void {
      root.toggle()
    }
    function settings(): void {
      root.openSettings()
    }
    function show(ticket: string): void {
      root.showNotified(ticket)
    }
    // A notification's buttons: "host/id:revision" (comma-separated for
    // markRead); from another account they do nothing.
    function markRead(tickets: string): void {
      TicketStore.markReadUpTo(tickets)
    }
    function viewInZendesk(ticket: string): void {
      TicketStore.viewInZendesk(ticket)
    }
    function snooze(): void {
      TicketStore.toggleSnooze()
    }
  }
  // The button on the bar. It takes what it shows as plain values, which this
  // panel binds to the account and the inbox (below).
  component BarButton: Ui.WidgetButton {
    id: barButton
    // ZendeskAccount.state.
    property string accountState: "not_configured"
    // The inbox: its unread tickets, the checks that failed in a row, and
    // when the last one worked (0: never).
    property int unread: 0
    property int failures: 0
    property double lastUpdated: 0
    property bool withinSchedule: true
    property bool snoozed: false
    // The time `lastUpdated` is dated against: when the checks last had an
    // outcome (so "today" is never older than the last check), or a fixed
    // time in ms (the preview's, so its tooltips never drift).
    property double checkedAt: Date.now()
    property double fixedNow: 0
    onFailuresChanged: checkedAt = Date.now()
    readonly property alias content: barContent
    // What the agent has to see without opening the popup: "signin" (the
    // sign-in ended or can't be read, so nothing is checked) or "stale"
    // (checks keep failing, so the count is the last one known). Not outside
    // the schedule, where nothing is checked on purpose.
    readonly property string trouble: !withinSchedule ? "" : ["expired", "error", "unavailable"].indexOf(accountState) !== -1 ? "signin" : accountState === "signed_in" && failures >= 2 ? "stale" : ""
    // Outside the schedule the dimmed icon stands alone: no count, no dot.
    readonly property bool showsUnread: unread > 0 && withinSchedule
    readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
    // The bar's own colour, opaque: a ring of it parts a mark from the icon.
    readonly property color surface: Qt.alpha(bar ? bar.background : Commons.Color.background, 1)
    readonly property int ring: Style.space(1)
    // When the inbox last loaded: "09:12" today, "5 Nov 16:40" before that.
    readonly property string lastLoaded: {
      if (lastUpdated <= 0)
        return ""
      var today = Model.daysAgo(lastUpdated, fixedNow > 0 ? fixedNow : checkedAt) <= 0
      return new Date(lastUpdated).toLocaleString(Qt.locale(FoamyI18n.formatLocale), today ? "HH:mm" : "d MMM HH:mm")
    }

    text: ""
    labelVisible: false
    hasVisualContent: true
    dimmed: !withinSchedule
    fixedWidth: root.bar && root.bar.vertical ? -1 : Math.max(Style.bar.iconSlot, barContent.implicitWidth + Style.bar.iconSlot - Style.bar.iconCanvas)
    tooltipText: {
      if (snoozed)
        return FoamyI18n.t("Zendesk — snoozed")
      if (!withinSchedule)
        return FoamyI18n.t("Zendesk — outside your schedule")
      if (accountState === "expired")
        return FoamyI18n.t("Zendesk — sign-in expired")
      if (trouble === "signin")
        return FoamyI18n.t("Zendesk — can't sign in")
      if (accountState === "checking")
        return FoamyI18n.t("Zendesk — checking the sign-in…")
      if (accountState !== "signed_in")
        return FoamyI18n.t("Zendesk — not signed in")
      var count = unread ? FoamyI18n.tn("Zendesk — %1 unread", unread) : ""
      if (trouble !== "stale")
        return count || "Zendesk"
      // Stale: the count is still the last one known, so it stays.
      if (lastLoaded === "")
        return FoamyI18n.t("Zendesk — can't load tickets")
      return count ? count + " · " + FoamyI18n.t("not updated since %1", [lastLoaded]) : FoamyI18n.t("Zendesk — not updated since %1", [lastLoaded])
    }
    Row {
      id: barContent
      readonly property alias icon: brand
      readonly property alias countLabel: countLabel
      readonly property alias unreadDot: unreadDot
      readonly property alias troubleSign: troubleSign
      anchors.centerIn: parent
      // The warning sign reaches past the icon: keep it off the count.
      spacing: Style.space(barButton.trouble !== "" ? 3 : 1)
      Item {
        width: Style.bar.iconCanvas
        height: width
        // Keep the bar's alignment canvas, but size the filled mark like adjacent glyphs.
        FoamyIcon {
          id: brand
          anchors.centerIn: parent
          name: "zendesk"
          width: Style.bar.iconSize
          height: width
          color: barButton.foreground
          // Stale: the mark dims as the host dims a muted widget; the count
          // beside it stays readable.
          opacity: barButton.trouble === "stale" ? FoamyStyle.disabledOpacity : 1
        }
        // A vertical bar has no room for the count: a dot on the icon's
        // corner says there are unread tickets.
        Rectangle {
          id: unreadDot
          visible: barButton.showsUnread && barButton.vertical
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: -barButton.ring
          anchors.rightMargin: -barButton.ring
          width: Style.space(6) + barButton.ring * 2
          height: width
          radius: width / 2
          color: barButton.surface
          Rectangle {
            anchors.fill: parent
            anchors.margins: barButton.ring
            radius: width / 2
            color: Commons.Color.accent
          }
        }
        // Trouble: a warning sign on the icon's other corner, in the theme's
        // warning colour, so it never reads as the count ("new tickets", in
        // the bar's urgent colour) or as the unread dot (round, the accent).
        // Nerd Font alert (a triangle with an exclamation mark) over a solid
        // triangle in the bar's colour, which rings it and backs the mark.
        Item {
          id: troubleSign
          readonly property int size: Style.space(9)
          visible: barButton.trouble !== ""
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          anchors.bottomMargin: -barButton.ring
          anchors.rightMargin: -barButton.ring * 2
          width: size + barButton.ring * 2
          height: width
          // OpticalGlyph centres a glyph's ink in its box. Each box moves
          // down by the room under its ink, so both triangles stand on a
          // whole pixel and the base stays sharp.
          Ui.OpticalGlyph {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: (paintedHeight - height) / 2
            width: troubleSign.size + barButton.ring * 3
            height: width
            text: "\u{f0536}"
            fontFamily: barButton.fontFamily
            fontSize: width
            paintedSize: width
            color: barButton.surface
          }
          Ui.OpticalGlyph {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: barButton.ring + (paintedHeight - height) / 2
            width: troubleSign.size
            height: width
            text: "\u{f0026}"
            fontFamily: barButton.fontFamily
            fontSize: width
            paintedSize: width
            color: FoamyPalette.warning
          }
        }
      }
      PlainText {
        id: countLabel
        visible: barButton.showsUnread && !barButton.vertical
        anchors.verticalCenter: parent.verticalCenter
        text: FoamyI18n.number(barButton.unread)
        font.family: barButton.fontFamily
        font.pixelSize: Style.font.body
        color: barButton.urgent
      }
    }
  }
  readonly property alias barContent: button.content
  BarButton {
    id: button
    objectName: "zendeskButton"
    anchors.fill: parent
    bar: root.bar
    accountState: ZendeskAccount.state
    unread: TicketStore.unreadCount
    failures: TicketStore.failures
    lastUpdated: TicketStore.lastUpdated
    withinSchedule: TicketStore.withinSchedule
    snoozed: TicketStore.snoozed
    onPressed: function (pressedButton) {
      if (pressedButton === Qt.RightButton)
        root.openSettings()
      else
        root.toggle()
    }
  }
  FoamyPopup {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    // The inbox's own height, whatever the view shows (0 before the first open).
    readonly property real inboxHeight: bodyItem ? (bodyItem as InboxView).inboxImplicitHeight : 0
    contentWidth: fittedContentWidth(root.wide ? root.wideWidth : FoamyStyle.popupWidth)
    maxHeight: root.wide ? Math.max(Math.round(screenH * 0.7), FoamyStyle.popupMaxHeight + verticalContentInset) : 0
    contentHeight: fittedContentHeight(Math.max(root.wide ? Math.max(FoamyStyle.popupMaxHeight, inboxHeight) : bodyImplicitHeight, menuReserve), maxHeight)
    body: Component {
      InboxView {
        active: root.opened
        wide: root.wide
        preferences: prefs.effectiveSettings
        prefsQueue: prefs
        saving: prefs.busy
        settingsError: prefs.error !== "" ? FoamyI18n.t(prefs.error) : ""
        retryable: prefs.canRetry
        onCloseView: root.close()
        onSwitchPanel: function (direction) {
          root.switchPanel(direction)
        }
        onSaveRequested: function (key, value) {
          prefs.save(key, value)
        }
        onRetryRequested: prefs.retry()
      }
    }
  }
}
