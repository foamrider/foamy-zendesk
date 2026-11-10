import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "kit"
import "kit/FoamyPrefs.js" as Prefs
import "Preferences.js" as Schema
import "Model.js" as Model

PanelKeyCatcher {
  id: root
  property bool active: true
  property bool editingSettings: false
  // Saved settings and their save state, from the Panel's FoamyPrefsQueue.
  property var preferences: ({})
  property bool saving: false
  property string settingsError: ""
  property bool retryable: false
  signal saveRequested(string key, var value)
  signal retryRequested()
  function pref(key) { return Prefs.value(Schema.fields, preferences, key); }
  property var expandedIds: []
  readonly property alias list: list
  readonly property alias cursor: cursor
  readonly property alias band: band
  readonly property alias repeater: ticketRows
  readonly property alias settingsPage: settingsPage
  // Cursor stops in on-screen order: header actions, the empty state's button,
  // three per ticket (body, Mark as read, View in Zendesk), then Refresh.
  readonly property int markAllStop: 0
  // The ⋯ button (Snooze and Settings are in its menu), or the cog.
  readonly property int settingsStop: 1
  readonly property int firstTicketStop: 2
  readonly property int refreshStop: cursor.count - 1
  signal closeView()
  signal switchPanel(int direction)
  implicitWidth: FoamyStyle.popupWidth
  implicitHeight: editingSettings ? settingsPage.implicitHeight
    : band.implicitHeight + body.implicitHeight + (footer.visible ? footer.implicitHeight : 0)
  // The ⋯ menu takes the keys while it is open.
  blocked: editingSettings || band.menuOpen

  FoamyMember { scope: "zendesk-reading"; demanding: root.active && root.expandedIds.length > 0 }
  FoamyCursor { id: cursor; count: root.firstTicketStop + TicketStore.count * 3 + (ZendeskAccount.signedIn ? 1 : 0) }
  // Minute ticks for "Updated 3 minutes ago" while the popup is open.
  FoamyWallClock { id: clock; enabled: root.active }
  // The time ticket rows are dated against ("10:40", "Yesterday", "Thu"): the
  // wall clock, or a fixed time in ms (the preview's, so its dates never drift).
  property double fixedNow: 0
  Connections {
    target: TicketStore
    // Reset releases readers on every monitor, not only the panel that invoked it.
    function onResetting() { root.closeReading(); list.contentY = 0; }
    // Signed in (or the helper found) while open: fetch now, not at the next
    // background check (outside the schedule there is none). Later, so an
    // account change's restart runs first.
    function onConnectedChanged() { if (root.active && TicketStore.connected) Qt.callLater(root.refreshIfStale); }
  }

  function closeReading() { expandedIds = []; cursor.reset(); band.closeMenu(); }
  // Opening the popup refreshes an inbox older than 30 seconds.
  function refreshIfStale() { if (root.active) TicketStore.refreshIfStale(30000); }
  onActiveChanged: {
    if (active) refreshIfStale();
    else { closeReading(); editingSettings = false; }
  }
  // The popup builds this view on its first open with `active` already true,
  // so onActiveChanged never fires for that open.
  Component.onCompleted: refreshIfStale()
  onEditingSettingsChanged: {
    if (editingSettings) { closeReading(); settingsPage.resetScroll(); Qt.callLater(settingsPage.focusBack); }
    else Qt.callLater(function() { root.forceActiveFocus(); });
  }
  // One ticket open at a time. Opening marks it read; it keeps its place
  // (the store's hold) until it closes, then moves or hides like any read ticket.
  readonly property string holdKey: "inbox-" + Math.random().toString(36).slice(2)
  function toggleTicket(id) {
    var opening = expandedIds.indexOf(id) < 0;
    var found = opening ? TicketStore.ticketById(id) : null;
    if (opening && !found) return;
    var onTicket = cursor.index >= firstTicketStop && cursor.index < refreshStop;
    var part = onTicket ? (cursor.index - firstTicketStop) % 3 : 0;
    // Swap the hold before collapsing the other ticket, so the list re-sorts once.
    if (opening) TicketStore.hold(holdKey, id, found.ticket.read);
    expandedIds = opening ? [id] : [];
    if (opening) TicketStore.markRead(id);
    else TicketStore.hold(holdKey, "");
    // The ticket may have moved: keep the cursor and the view on it.
    var now = TicketStore.ticketById(id);
    if (!now) return;
    if (onTicket) cursor.index = firstTicketStop + now.index * 3 + part;
    revealTicket(now.index);
  }
  onExpandedIdsChanged: if (expandedIds.length === 0) TicketStore.hold(holdKey, "")
  Component.onDestruction: TicketStore.hold(holdKey, "")
  // Scrolls so the ticket's top is in view, after the list lays out.
  function revealTicket(index) {
    body.forceLayout();
    var row = ticketRows.itemAt(index);
    if (!row) return;
    var y = row.mapToItem(list.contentItem, 0, 0).y + (row.sectionHeader.visible ? row.sectionHeader.height : 0);
    var bottom = y + Math.min(row.height, list.height);
    if (y < list.contentY) list.contentY = Math.max(0, y - FoamyStyle.gap);
    else if (bottom > list.contentY + list.height)
      list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, bottom - list.height));
  }
  function toggleRead(id, index) {
    TicketStore.toggleRead(id);
    if (!TicketStore.hideRead) return;
    // With read tickets hidden, the ticket leaves the list: keep the cursor on its neighbour.
    expandedIds = expandedIds.filter(function(value) { return value !== id; });
    cursor.index = TicketStore.count ? firstTicketStop + Math.min(index, TicketStore.count - 1) * 3 : settingsStop;
    root.forceActiveFocus();
  }
  function markAllRead() {
    if (TicketStore.hideRead) closeReading();
    TicketStore.markAllRead();
  }
  function ticketIndex() { return Math.floor((cursor.index - firstTicketStop) / 3); }
  function activateCursor() {
    if (cursor.index === markAllStop) { markAllRead(); return; }
    if (cursor.index === settingsStop) {
      if (band.settingsInMenu) band.openMenu(true);
      else editingSettings = true;
      return;
    }
    if (cursor.index === refreshStop) { TicketStore.refresh(); return; }
    var index = ticketIndex();
    if (index < 0 || index >= TicketStore.count) return;
    var id = TicketStore.tickets.get(index).id;
    var part = (cursor.index - firstTicketStop) % 3;
    if (part === 0) toggleTicket(id);
    else if (part === 1) toggleRead(id, index);
    else TicketStore.openTicket(id);
  }
  function reveal() {
    var ticket = ticketRows.itemAt(ticketIndex());
    if (!ticket || cursor.index < firstTicketStop) return;
    var item = (cursor.index - firstTicketStop) % 3 === 0 ? ticket : ticket.openButton;
    var y = item.mapToItem(list.contentItem, 0, 0).y;
    // Tall expanded tickets keep their top in view; actions scroll to the actual button.
    if (y < list.contentY) list.contentY = Math.max(0, y);
    else if (y + Math.min(item.height, list.height) > list.contentY + list.height)
      list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, y + Math.min(item.height, list.height) - list.height));
  }
  onMoveRequested: function(dx, dy) {
    var direction = dy || dx;
    cursor.move(direction);
    // "Mark all as read" is disabled while nothing is unread; the cursor stops at the top.
    if (cursor.index === markAllStop && TicketStore.unreadCount === 0) {
      if (direction < 0) cursor.index = settingsStop;
      else cursor.move(direction);
    }
    reveal();
  }
  onActivateRequested: activateCursor()
  onCloseRequested: { closeReading(); root.closeView(); }
  onTabRequested: function(direction) { root.switchPanel(direction); }
  onTextKey: function(text, modifiers) {
    if (!cursor.plain(modifiers)) return;
    if (text === "u" && TicketStore.canUndoMarkAll) TicketStore.undoMarkAll();
    else if (text === "s") editingSettings = true;
    else if (text === "r") TicketStore.refresh();
    else if (text === "m") showMore();
  }
  // The ticket under the cursor opens; once open, each press shows one more
  // thing: the newest clipped comment in full, then the earlier comments.
  function showMore() {
    var index = ticketIndex();
    var row = cursor.index >= firstTicketStop ? ticketRows.itemAt(index) : null;
    if (!row) return;
    if (!row.expanded) toggleTicket(row.ticket.id);
    else row.showMore();
  }
  readonly property var sectionTitles: ({
    mine: FoamyI18n.t("Assigned to you"),
    unassigned: FoamyI18n.t("Unassigned in your groups"),
    waiting: FoamyI18n.t("Waiting on others")
  })

  FoamyHeroBand {
    id: band
    visible: !root.editingSettings
    width: parent.width
    title: "Zendesk"
    iconName: "zendesk"
    meta: !ZendeskAccount.signedIn ? FoamyI18n.t("Not signed in")
      : (TicketStore.unreadCount
        ? FoamyI18n.tn("%1 unread", TicketStore.unreadCount) + (TicketStore.count > TicketStore.unreadCount ? " · " + FoamyI18n.tn("%1 tickets", TicketStore.count) : "")
        : TicketStore.count ? FoamyI18n.t("All read") : TicketStore.loaded ? FoamyI18n.t("All caught up")
        : TicketStore.error !== "" ? FoamyI18n.t("Not updated") : FoamyI18n.t("Loading…"))
        + (TicketStore.snoozed ? " · " + FoamyI18n.t("snoozed") : TicketStore.withinSchedule ? "" : " · " + FoamyI18n.t("outside your schedule"))
    // Snooze and Settings live in the ⋯ menu: Mark all as read and ⋯ on the right.
    maxButtons: 2
    settingsHasCursor: cursor.at(root.settingsStop)
    menuHasCursor: cursor.at(root.settingsStop)
    onSettingsClicked: root.editingSettings = true
    onSettingsHovered: function(hovered) { if (hovered) cursor.hover(root.settingsStop); }
    onMenuHovered: function(hovered) { if (hovered) cursor.hover(root.settingsStop); }
    menuItems: [
      FoamyMenuItem {
        objectName: "snoozeItem"
        text: TicketStore.snoozed ? FoamyI18n.t("Stop snoozing")
          : TicketStore.withinSchedule ? FoamyI18n.t("Snooze until tomorrow") : FoamyI18n.t("Resume now")
        iconName: TicketStore.withinSchedule ? "moon" : "sun"
        onTriggered: TicketStore.toggleSnooze()
      }
    ]
    trailing: [
      FoamyAction {
        objectName: "markAllRead"
        iconName: "check-check"
        tooltipText: FoamyI18n.t("Mark all as read")
        actionEnabled: TicketStore.unreadCount > 0
        hasCursor: cursor.at(root.markAllStop)
        onHoveredChanged: if (hovered && actionEnabled) cursor.hover(root.markAllStop)
        onClicked: root.markAllRead()
      }
    ]
  }
  Flickable {
    id: list
    objectName: "ticketList"
    visible: !root.editingSettings
    anchors.top: band.bottom
    anchors.bottom: footer.visible ? footer.top : parent.bottom
    width: parent.width
    contentWidth: width
    contentHeight: body.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
    FoamyWheelScroll { target: list }
    Column {
      id: body
      width: list.width
      spacing: 0
      topPadding: FoamyStyle.gap
      // Room for the status bar, so it never covers the last ticket.
      bottomPadding: FoamyStyle.gapLarge + (statusBar.visible ? statusBar.height + FoamyStyle.gap : 0)
      Column {
        id: emptyState
        objectName: "emptyState"
        // signin, loading, failed, caughtup
        readonly property string kind: !ZendeskAccount.signedIn ? "signin"
          : !TicketStore.loaded ? (TicketStore.error !== "" ? "failed" : "loading") : "caughtup"
        visible: TicketStore.count === 0
        width: parent.width
        topPadding: FoamyStyle.gapLarge
        bottomPadding: FoamyStyle.gapLarge
        spacing: FoamyStyle.gap
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: 44; height: 44; radius: 22
          readonly property color tone: emptyState.kind === "caughtup" ? FoamyPalette.success
            : emptyState.kind === "failed" ? FoamyPalette.error : FoamyPalette.accent
          color: Qt.alpha(tone, 0.14)
          FoamyIcon {
            id: emptyIcon
            objectName: "emptyIcon"
            anchors.centerIn: parent; width: 22; height: 22
            name: emptyState.kind === "caughtup" ? "check-check" : emptyState.kind === "failed" ? "disconnected"
              : emptyState.kind === "loading" ? "refresh-cw" : "zendesk"
            color: FoamyPalette.onSurface(parent.tone)
            // Turns while the first inbox is being fetched, like the footer's Refresh.
            RotationAnimation on rotation {
              running: emptyState.kind === "loading" && TicketStore.loading && emptyState.visible && root.active && !FoamyMotion.reduceMotion
              from: 0
              to: 360
              duration: FoamyMotion.spin
              loops: Animation.Infinite
              onStopped: emptyIcon.rotation = 0
            }
          }
        }
        PlainText {
          anchors.horizontalCenter: parent.horizontalCenter
          text: emptyState.kind === "signin" ? FoamyI18n.t("Sign in to see your tickets")
            : emptyState.kind === "loading" ? FoamyI18n.t("Loading tickets…")
            : emptyState.kind === "failed" ? FoamyI18n.t("Couldn't load tickets") : FoamyI18n.t("All caught up")
          font.pixelSize: FoamyStyle.font.subtitle
          font.weight: Font.DemiBold
        }
        PlainText {
          x: FoamyStyle.padding
          width: parent.width - FoamyStyle.padding * 2
          horizontalAlignment: Text.AlignHCenter
          text: emptyState.kind === "signin" ? FoamyI18n.t("Connect your Zendesk account in the settings.")
            : emptyState.kind === "failed" ? TicketStore.error
            : emptyState.kind === "loading" ? "" : FoamyI18n.t("Your tickets and unassigned tickets in your groups show up here.")
          visible: text !== ""
          color: FoamyPalette.mutedText
          font.pixelSize: FoamyStyle.font.bodySmall
        }
        FoamyButton {
          objectName: "openSettings"
          visible: emptyState.kind === "signin"
          anchors.horizontalCenter: parent.horizontalCenter
          text: FoamyI18n.t("Open settings")
          kind: "primary"
          onClicked: root.editingSettings = true
        }
      }
      Repeater {
        id: ticketRows
        model: TicketStore.tickets
        TicketRow {
          required property var model
          required property int index
          readonly property int firstStop: root.firstTicketStop + index * 3
          ticket: model
          objectName: "ticket-" + model.id
          // Read tickets take one line; unread ones show their latest comment.
          compact: model.read
          sectionTitle: model.sectionHead ? root.sectionTitles[model.sectionHead] : ""
          sectionCount: model.sectionSize
          now: root.fixedNow > 0 ? root.fixedNow : clock.date.getTime()
          x: FoamyStyle.gapLarge
          width: body.width - FoamyStyle.gapLarge * 2
          expanded: root.expandedIds.indexOf(model.id) >= 0
          cursorPart: cursor.index >= firstStop && cursor.index < firstStop + 3 ? cursor.index - firstStop : -1
          onHovered: function(part) { cursor.hover(firstStop + part); }
          onToggleRequested: root.toggleTicket(model.id)
          onOpenRequested: TicketStore.openTicket(model.id)
          onReadToggleRequested: root.toggleRead(model.id, index)
        }
      }
    }
  }
  FoamyPanelFooter {
    id: footer
    // Signed out, there is nothing to refresh or date.
    visible: !root.editingSettings && ZendeskAccount.signedIn
    anchors.bottom: parent.bottom
    width: parent.width
    horizontalPadding: FoamyStyle.padding
    source: ZendeskAccount.signedIn ? Model.host(ZendeskAccount.address) : ""
    // The last good inbox stays shown; the footer says when it is from, or why not newer.
    // Without an inbox the error is already on screen: say when the next try is.
    status: TicketStore.error !== "" ? (TicketStore.loaded ? TicketStore.error : root.retryText)
      : TicketStore.loaded ? FoamyI18n.updatedAgo(TicketStore.lastUpdated, clock.date.getTime()) : ""
    statusError: TicketStore.error !== "" && TicketStore.loaded
    statusTooltip: TicketStore.error !== "" && TicketStore.loaded ? FoamyI18n.updatedAgo(TicketStore.lastUpdated, clock.date.getTime()) : ""
    showRefresh: ZendeskAccount.signedIn
    refreshing: TicketStore.loading
    refreshEnabled: TicketStore.connected && !TicketStore.loading
    refreshHasCursor: cursor.at(root.refreshStop)
    onRefreshHovered: function(hovered) { if (hovered) cursor.hover(root.refreshStop); }
    onRefreshClicked: TicketStore.refresh()
  }

  readonly property string retryText: {
    var left = TicketStore.retryAt - clock.date.getTime();
    return TicketStore.active && left > 0 ? FoamyI18n.tn("Trying again in %1 minutes", Math.max(1, Math.ceil(left / 60000)))
      : FoamyI18n.t("Not updated");
  }

  // Notices float over the bottom of the list instead of taking layout space,
  // so an update arriving while a ticket is open never moves what is being read.
  Rectangle {
    id: statusBar
    objectName: "statusBar"
    visible: !root.editingSettings && statusText.text.length > 0
    anchors.bottom: footer.top
    anchors.bottomMargin: FoamyStyle.gap
    x: FoamyStyle.gapLarge
    width: parent.width - FoamyStyle.gapLarge * 2
    height: Math.max(FoamyStyle.rowHeight, statusText.implicitHeight + FoamyStyle.gap * 2)
    radius: FoamyStyle.radiusSmall + 2
    color: Qt.tint(FoamyPalette.background, FoamyPalette.menuFill)
    border.width: FoamyStyle.borderWidth
    border.color: FoamyPalette.border
    PlainText {
      id: statusText
      anchors.left: parent.left
      anchors.leftMargin: FoamyStyle.gapLarge
      anchors.right: undoButton.visible ? undoButton.left : parent.right
      anchors.rightMargin: undoButton.visible ? FoamyStyle.gapSmall : FoamyStyle.gapLarge
      anchors.verticalCenter: parent.verticalCenter
      font.pixelSize: FoamyStyle.font.bodySmall
      color: FoamyPalette.text
      text: TicketStore.pendingChanges ? FoamyI18n.tn("%1 updates waiting — collapse tickets to show", TicketStore.pendingChanges)
        : TicketStore.notice
      maximumLineCount: 2
      elide: Text.ElideRight
      Accessible.role: Accessible.StaticText
    }
    FoamyCursorSurface {
      id: undoButton
      objectName: "undoMarkAll"
      visible: TicketStore.canUndoMarkAll && !TicketStore.pendingChanges
      anchors.right: parent.right
      anchors.rightMargin: FoamyStyle.gapSmall
      anchors.verticalCenter: parent.verticalCenter
      width: undoLabel.implicitWidth + FoamyStyle.gap * 2
      height: FoamyStyle.actionSize - 4
      foreground: FoamyPalette.accent
      onClicked: TicketStore.undoMarkAll()
      Accessible.role: Accessible.Button
      Accessible.name: FoamyI18n.t("Undo")
      Accessible.onPressAction: TicketStore.undoMarkAll()
      PlainText {
        id: undoLabel
        anchors.centerIn: parent
        text: FoamyI18n.t("Undo")
        color: FoamyPalette.onSurface(FoamyPalette.accent)
        font.pixelSize: FoamyStyle.font.bodySmall
        font.weight: Font.DemiBold
      }
    }
  }

  FoamySettingsPage {
    id: settingsPage
    visible: root.editingSettings
    width: parent.width
    height: parent.height
    saving: root.saving
    error: root.settingsError
    retryable: root.retryable
    onBack: root.editingSettings = false
    onRetry: root.retryRequested()
    FoamySettingsSection {
      width: parent.width
      title: FoamyI18n.t("Read tickets")
      description: FoamyI18n.t("Read state stays on this computer; nothing changes in Zendesk.")
      FoamyToggle {
        objectName: "hideReadToggle"
        width: parent.width
        label: FoamyI18n.t("Hide read tickets")
        description: FoamyI18n.t("Read tickets leave the list and come back with their next update.")
        checked: root.pref("hideRead")
        onClicked: root.saveRequested("hideRead", !checked)
      }
      FoamyToggle {
        objectName: "unreadFirstToggle"
        width: parent.width
        label: FoamyI18n.t("Show unread first")
        description: FoamyI18n.t("Otherwise tickets are sorted by their latest update.")
        checked: root.pref("unreadFirst")
        enabled: !root.pref("hideRead")
        onClicked: root.saveRequested("unreadFirst", !checked)
      }
      FoamyToggle {
        objectName: "groupWaitingToggle"
        width: parent.width
        label: FoamyI18n.t("Group waiting tickets")
        description: FoamyI18n.t("Pending and on-hold tickets you've read move to their own section at the end. A new reply brings them back up.")
        checked: root.pref("groupWaiting")
        enabled: !root.pref("hideRead")
        onClicked: root.saveRequested("groupWaiting", !checked)
      }
    }

    // Turning the schedule on scrolls the new day rows into view.
    property bool revealSchedule: false
    readonly property bool scheduleOn: root.pref("scheduleEnabled") === true
    onScheduleOnChanged: if (scheduleOn && revealSchedule) {
      revealSchedule = false;
      Qt.callLater(function() { settingsPage.ensureVisible(scheduleSection); });
    }
    FoamySettingsSection {
      id: scheduleSection
      width: parent.width
      title: FoamyI18n.t("Schedule")
      description: settingsPage.scheduleOn ? FoamyI18n.t("Local time. Turn a day off to skip it. Overnight ranges are supported.") : ""
      FoamyToggle {
        objectName: "scheduleEnabled"
        width: parent.width
        label: FoamyI18n.t("Use a weekly schedule")
        description: FoamyI18n.t("Dim or hide Zendesk outside your working hours.")
        checked: settingsPage.scheduleOn
        enabled: !root.saving
        onClicked: {
          settingsPage.revealSchedule = !checked;
          root.saveRequested("scheduleEnabled", !checked);
        }
      }
      FoamyDropdown {
        objectName: "scheduleOutsideMode"
        visible: settingsPage.scheduleOn
        width: parent.width
        compact: true
        label: FoamyI18n.t("Outside the schedule")
        value: root.pref("scheduleOutsideMode")
        enabled: !root.saving
        options: [{ value: "mute", label: FoamyI18n.t("Dim") }, { value: "hide", label: FoamyI18n.t("Hide") }]
        onChanged: function(value) { root.saveRequested("scheduleOutsideMode", value); }
      }
      RowLayout {
        visible: settingsPage.scheduleOn
        width: parent.width
        spacing: FoamyStyle.gap
        Item { Layout.fillWidth: true }
        PlainText {
          Layout.preferredWidth: Style.space(64)
          text: FoamyI18n.t("From")
          color: FoamyPalette.secondaryText
          horizontalAlignment: Text.AlignHCenter
          font.pixelSize: FoamyStyle.font.bodySmall
        }
        PlainText {
          Layout.preferredWidth: Style.space(64)
          text: FoamyI18n.t("To")
          color: FoamyPalette.secondaryText
          horizontalAlignment: Text.AlignHCenter
          font.pixelSize: FoamyStyle.font.bodySmall
        }
      }
      Repeater {
        model: settingsPage.scheduleOn ? Schema.dayKeys : []
        ScheduleDay {
          required property string modelData
          required property int index
          width: parent.width
          objectName: modelData
          label: FoamyI18n.t(Schema.dayLabels[index])
          fromLabel: FoamyI18n.t("From")
          toLabel: FoamyI18n.t("To")
          value: root.pref(modelData)
          enabled: !root.saving
          onChanged: function(range) { root.saveRequested(modelData, range); }
          onInvalid: root.saveRequested(modelData, "invalid")
        }
      }
    }

    // The account and connection. Nothing here is secret: the OAuth tokens
    // live in the keyring, handled by the helper.
    FoamySettingsSection {
      id: zendeskSection
      objectName: "zendeskSection"
      width: parent.width
      title: "Zendesk"
      description: ZendeskAccount.signedIn ? "" : FoamyI18n.t("Sign in with your Zendesk account. The sign-in is kept in your keyring.")
      info: FoamyI18n.t("A Zendesk admin creates the OAuth client once, in Admin Center › Apps and integrations › APIs › OAuth clients: kind Public, redirect URL %1, read access. Enter its unique identifier as the OAuth client ID.", [settingsPage.redirectUrl])
      RowLayout {
        objectName: "accountRow"
        width: parent.width
        spacing: FoamyStyle.gapLarge
        Column {
          Layout.fillWidth: true
          spacing: 2
          PlainText {
            objectName: "accountTitle"
            width: parent.width
            text: settingsPage.accountTitle
          }
          PlainText {
            objectName: "accountDetail"
            visible: text !== ""
            width: parent.width
            text: settingsPage.accountDetail
            color: ZendeskAccount.state === "error" || ZendeskAccount.state === "unavailable" || ZendeskAccount.state === "expired"
              ? FoamyPalette.onSurface(FoamyPalette.error) : FoamyPalette.secondaryText
            font.pixelSize: FoamyStyle.font.bodySmall
          }
        }
        FoamyButton {
          objectName: "accountButton"
          focusable: true
          text: ZendeskAccount.signedIn ? FoamyI18n.t("Sign out")
            : ZendeskAccount.state === "waiting" ? FoamyI18n.t("Cancel") : FoamyI18n.t("Sign in")
          kind: ZendeskAccount.signedIn || ZendeskAccount.state === "waiting" ? "secondary" : "primary"
          busy: ZendeskAccount.state === "checking" || ZendeskAccount.logoutProcess.running
          // Typed but not yet saved counts: the click saves the fields first.
          actionEnabled: ZendeskAccount.state !== "unavailable"
            && (ZendeskAccount.signedIn || ZendeskAccount.state === "waiting" || settingsPage.connectionReady)
          onClicked: {
            if (ZendeskAccount.signedIn) ZendeskAccount.signOut();
            else if (ZendeskAccount.state === "waiting") ZendeskAccount.cancelSignIn();
            else if (settingsPage.saveConnection()) ZendeskAccount.signIn();
          }
        }
      }
      FoamyTextSettingField {
        id: addressField
        objectName: "addressField"
        visible: !ZendeskAccount.signedIn
        width: parent.width
        label: FoamyI18n.t("Zendesk address")
        placeholderText: "acme.zendesk.com"
        value: root.pref("zendeskAddress")
        validate: function(text) {
          return new RegExp(Schema.addressPattern).test(text) || FoamyI18n.t("Enter your Zendesk address, like acme or acme.zendesk.com.");
        }
        onCommitted: function(value) { root.saveRequested("zendeskAddress", value); }
      }
      FoamyTextSettingField {
        id: clientIdField
        objectName: "clientIdField"
        visible: !ZendeskAccount.signedIn
        width: parent.width
        label: FoamyI18n.t("OAuth client ID")
        placeholderText: FoamyI18n.t("Unique identifier")
        value: root.pref("oauthClientId")
        validate: function(text) {
          return /^$|^[A-Za-z0-9_.-]{1,128}$/.test(text) || FoamyI18n.t("Enter the OAuth client's unique identifier.");
        }
        onCommitted: function(value) { root.saveRequested("oauthClientId", value); }
      }
      FoamyTextSettingField {
        id: portField
        objectName: "portField"
        visible: !ZendeskAccount.signedIn
        width: parent.width
        label: FoamyI18n.t("Redirect port")
        // Empty means the default; the placeholder shows it.
        placeholderText: String(Schema.defaultPort)
        value: root.pref("oauthPort")
        validate: function(text) {
          return text === "" || (/^[0-9]{4,5}$/.test(text) && Number(text) >= 1024 && Number(text) <= 65535)
            || FoamyI18n.t("Choose a redirect port between 1024 and 65535.");
        }
        onCommitted: function(value) { root.saveRequested("oauthPort", value); }
      }
      PlainText {
        objectName: "redirectHint"
        visible: !ZendeskAccount.signedIn
        width: parent.width
        text: FoamyI18n.t("Redirect URL for the OAuth client: %1", [settingsPage.redirectUrl])
        color: FoamyPalette.mutedText
        font.pixelSize: FoamyStyle.font.bodySmall
      }
      FoamyDropdown {
        objectName: "refreshSeconds"
        width: parent.width
        compact: true
        label: FoamyI18n.t("Check every")
        value: String(root.pref("refreshSeconds"))
        enabled: !root.saving
        options: Schema.refreshChoices.map(function(seconds) {
          return { value: String(seconds), label: FoamyI18n.tn("%1 minutes", seconds / 60) };
        })
        onChanged: function(value) { root.saveRequested("refreshSeconds", Number(value)); }
      }
    }

    // What the fields hold now, saved or still being typed.
    readonly property bool connectionReady: addressField.field.text.trim() !== "" && addressField.problem(addressField.field.text.trim()) === ""
      && clientIdField.field.text.trim() !== "" && clientIdField.problem(clientIdField.field.text.trim()) === ""
      && portField.problem(portField.field.text.trim()) === ""
    // Saves any field still being edited; false (with the field's message) when one is invalid.
    function saveConnection() {
      return addressField.commitEdit(false) && clientIdField.commitEdit(false) && portField.commitEdit(false);
    }
    readonly property string redirectUrl: "http://127.0.0.1:" + (Number(root.pref("oauthPort")) || Schema.defaultPort) + "/callback"
    readonly property string accountTitle: {
      switch (ZendeskAccount.state) {
      case "checking": return FoamyI18n.t("Checking the sign-in…");
      case "signed_out": return FoamyI18n.t("Not signed in");
      case "waiting": return FoamyI18n.t("Waiting for the browser…");
      case "signed_in": return ZendeskAccount.user && ZendeskAccount.user.name
        ? FoamyI18n.t("Signed in as %1", [ZendeskAccount.user.name]) : FoamyI18n.t("Signed in");
      case "expired": return FoamyI18n.t("Sign-in expired");
      case "error": case "unavailable": return FoamyI18n.t("Can't sign in");
      default: return FoamyI18n.t("Not connected");
      }
    }
    readonly property string accountDetail: {
      switch (ZendeskAccount.state) {
      case "not_configured": return FoamyI18n.t("Enter the Zendesk address and OAuth client ID below.");
      case "waiting": return FoamyI18n.t("Finish signing in in your browser.");
      case "signed_in": {
        var email = ZendeskAccount.user && ZendeskAccount.user.email ? ZendeskAccount.user.email : "";
        // The error: why it isn't verified, or why sign-out didn't finish.
        return [email, ZendeskAccount.error].filter(function(part) { return part; }).join(" · ");
      }
      case "expired": return FoamyI18n.t("Sign in again to keep checking for updates.");
      default: return ZendeskAccount.error;
      }
    }
  }
}
