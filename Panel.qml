import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "kit"
import "Preferences.js" as Schema
import "Schedule.js" as Schedule

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

  FoamyPrefsQueue {
    id: prefs
    bar: root.bar
    moduleName: root.moduleName
    fields: Schema.fields
    settings: root.settings
  }
  // Demand: this popup is open, so the store holds back notifications.
  FoamyMember { id: member; scope: "zendesk"; demanding: root.opened }
  // Whichever instance saves pushes at once, before the host reflects the value
  // back; every instance then pushes the same reflected settings.
  function pushSettings() {
    TicketStore.hideRead = prefs.value("hideRead");
    TicketStore.unreadFirst = prefs.value("unreadFirst");
    TicketStore.groupWaiting = prefs.value("groupWaiting");
    TicketStore.notify = prefs.value("notify");
    TicketStore.scheduleEnabled = prefs.value("scheduleEnabled");
    TicketStore.week = Schedule.week(prefs.effectiveSettings || ({}));
    TicketStore.refreshSeconds = prefs.value("refreshSeconds");
    ZendeskAccount.configure({
      address: String(prefs.value("zendeskAddress")).trim(),
      clientId: String(prefs.value("oauthClientId")).trim(),
      port: Number(prefs.value("oauthPort")) || Schema.defaultPort
    });
  }
  Connections {
    target: prefs
    function onEffectiveSettingsChanged() { root.pushSettings(); }
  }
  Component.onCompleted: pushSettings()

  function openSettings() {
    root.open();
    var view = popup.ensureBody();
    if (view) view.editingSettings = true;
  }
  // A notification's click: the inbox with that ticket open (and read).
  function showTicket(id) {
    root.open();
    var view = popup.ensureBody();
    if (view) view.showTicket(String(id));
  }
  // The show IPC, "host/id": that ticket, or only the inbox when the
  // notification came from another account.
  function showNotified(ticket) {
    var id = TicketStore.shownTicket(ticket);
    if (id) showTicket(id);
    else root.open();
  }
  FoamyIpc {
    enabled: member.isLeader
    target: "foamy.zendesk"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function settings(): void { root.openSettings() }
    function show(ticket: string): void { root.showNotified(ticket) }
    // A notification's buttons: "host/id:revision" (comma-separated for
    // markRead); from another account they do nothing.
    function markRead(tickets: string): void { TicketStore.markReadUpTo(tickets) }
    function viewInZendesk(ticket: string): void { TicketStore.viewInZendesk(ticket) }
    function snooze(): void { TicketStore.toggleSnooze() }
  }
  readonly property alias barContent: barContent
  Ui.WidgetButton {
    id: button
    objectName: "zendeskButton"
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    dimmed: !TicketStore.withinSchedule
    fixedWidth: root.bar && root.bar.vertical ? -1 : Math.max(Style.bar.iconSlot, barContent.implicitWidth + Style.bar.iconSlot - Style.bar.iconCanvas)
    active: TicketStore.unreadCount > 0 && TicketStore.withinSchedule
    activeColor: Commons.Color.accent
    tooltipText: TicketStore.snoozed ? FoamyI18n.t("Zendesk — snoozed")
      : !TicketStore.withinSchedule ? FoamyI18n.t("Zendesk — outside your schedule")
      : !ZendeskAccount.signedIn ? FoamyI18n.t("Zendesk — not signed in")
      : TicketStore.unreadCount ? FoamyI18n.tn("Zendesk — %1 unread", TicketStore.unreadCount) : "Zendesk"
    onPressed: function(pressedButton) {
      if (pressedButton === Qt.RightButton) root.openSettings();
      else root.toggle();
    }
    Row {
      id: barContent
      readonly property alias icon: brand
      readonly property alias countLabel: countLabel
      anchors.centerIn: parent
      spacing: Style.space(1)
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
          color: button.foreground
        }
      }
      PlainText {
        id: countLabel
        // Outside the schedule the dimmed icon stands alone: no count.
        visible: TicketStore.unreadCount > 0 && TicketStore.withinSchedule && !(root.bar && root.bar.vertical)
        anchors.verticalCenter: parent.verticalCenter
        text: FoamyI18n.number(TicketStore.unreadCount)
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        color: root.bar ? root.bar.urgent : Commons.Color.urgent
      }
    }
  }
  FoamyPopup {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    body: Component {
      InboxView {
        active: root.opened
        preferences: prefs.effectiveSettings
        saving: prefs.busy
        settingsError: prefs.error !== "" ? FoamyI18n.t(prefs.error) : ""
        retryable: prefs.canRetry
        onCloseView: root.close()
        onSwitchPanel: function(direction) { root.switchPanel(direction) }
        onSaveRequested: function(key, value) { prefs.save(key, value) }
        onRetryRequested: prefs.retry()
      }
    }
  }
}
