pragma ComponentBehavior: Bound
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
  // That queue itself: a dropdown or schedule row linked to it (queue,
  // queueKey) shows the saved value again at once when the queue refuses
  // its save.
  property FoamyPrefsQueue prefsQueue: null
  signal saveRequested(string key, var value)
  signal retryRequested
  function pref(key) {
    return Prefs.value(Schema.fields, preferences, key)
  }
  // Wide (Panel.qml): the list on the reading start and a reading pane
  // beside it, one size whatever is shown. Selecting a ticket (a click or
  // Enter) shows it in the pane instead of opening it in place; with none
  // selected the pane shows the overview.
  property bool wide: false
  // The open ticket ([id] or []): expanded in place, or (Wide) selected.
  property var expandedIds: []
  readonly property alias list: ticketList
  readonly property alias pane: ticketPane
  readonly property alias overview: ticketOverview
  readonly property alias cursor: cursor
  readonly property alias band: heroBand
  readonly property alias repeater: ticketRows
  readonly property alias settingsPage: settingsView
  // Cursor stops in on-screen order: header actions, the empty state's button,
  // three per ticket (body, Mark as read, View in Zendesk), then Refresh.
  // Wide: one per ticket, then the pane's (its three actions and the
  // conversation, or the overview's tickets that need a reply and its "more"
  // link), then Refresh.
  readonly property int markAllStop: 0
  // The ⋯ button (Snooze and Settings are in its menu), or the cog.
  readonly property int settingsStop: 1
  readonly property int firstTicketStop: 2
  readonly property int stopsPerTicket: wide ? 1 : 3
  readonly property int paneFirstStop: firstTicketStop + TicketStore.count * stopsPerTicket
  readonly property int paneStops: !paneShown ? 0 : selected ? 4 : TicketStore.overview.awaiting.length + (ticketOverview.moreShown ? 1 : 0)
  // Wide: the stop on the selected ticket's conversation, where Up and Down scroll it.
  readonly property int conversationStop: paneFirstStop + 3
  readonly property int refreshStop: cursor.count - 1
  // Wide: the list's width while the pane shows (always, unless the inbox is
  // empty: then the empty state takes the whole width).
  readonly property int listWidth: Style.space(340)
  readonly property bool paneShown: wide && TicketStore.count > 0
  // Wide: the selected ticket ({ index, ticket } in TicketStore.tickets), or null.
  readonly property var selected: wide && expandedIds.length > 0 && TicketStore.revision >= 0 ? TicketStore.ticketById(expandedIds[0]) : null
  // The selected ticket's read marker when it was selected, for the pane's
  // "New". A comment id: Zendesk's exceed an int.
  property double openedSince: 0
  signal closeView
  signal switchPanel(int direction)
  // Signed out, there is nothing to refresh or date: no footer.
  readonly property bool footerShown: ZendeskAccount.signedIn
  // What the notice bar (statusBar) has to say.
  readonly property bool openFailed: TicketStore.notice !== "" && TicketStore.notice === TicketStore.openFailedText
  readonly property bool refreshFailed: TicketStore.loaded && TicketStore.error !== ""
  readonly property bool barShown: TicketStore.pendingChanges > 0 || TicketStore.notice !== "" || refreshFailed || TicketStore.saveError !== ""
  // Wide's width and height are Panel.qml's: one size, Settings included.
  implicitWidth: FoamyStyle.popupWidth
  implicitHeight: editingSettings ? settingsView.implicitHeight : heroBand.implicitHeight + body.implicitHeight + (barShown ? statusBar.height + statusBar.anchors.bottomMargin : 0) + (footerShown ? footer.implicitHeight : 0)
  // Wide (Panel.qml): the height the whole inbox would take: the band, the
  // list's content and the footer. The card is at least 640 high and grows
  // with this, up to the popup's cap. It keeps the value it had while
  // Settings is open, so opening Settings (which also closes the selected
  // ticket and lets held updates in) never resizes the card under the page.
  readonly property real inboxImplicitHeight: inboxHeight.value
  QtObject {
    id: inboxHeight
    property real value: 0
  }
  Binding {
    target: inboxHeight
    property: "value"
    value: heroBand.implicitHeight + body.implicitHeight + (root.footerShown ? footer.implicitHeight : 0)
    when: !root.editingSettings
    restoreMode: Binding.RestoreNone
  }
  // The ⋯ menu takes the keys while it is open.
  blocked: editingSettings || heroBand.menuOpen

  FoamyMember {
    scope: "zendesk-reading"
    demanding: root.active && root.expandedIds.length > 0 && !root.applyingUpdates
  }
  FoamyCursor {
    id: cursor
    count: root.paneFirstStop + root.paneStops + (ZendeskAccount.signedIn ? 1 : 0)
  }
  // Minute ticks for "Updated 3 minutes ago" while the popup is open.
  FoamyWallClock {
    id: clock
    enabled: root.active
  }
  // The time ticket rows are dated against ("10:40", "Yesterday", "Thu"): the
  // wall clock, or a fixed time in ms (the preview's, so its dates never drift).
  property double fixedNow: 0
  Connections {
    target: TicketStore
    // Reset releases readers on every monitor, not only the panel that invoked it.
    function onResetting() {
      root.closeReading()
      ticketList.contentY = 0
    }
    // Signed in (or the helper found) while open: fetch now, not at the next
    // background check (outside the schedule there is none). Later, so an
    // account change's restart runs first.
    function onConnectedChanged() {
      if (root.active && TicketStore.connected)
        Qt.callLater(root.refreshIfStale)
    }
  }

  function closeReading() {
    expandedIds = []
    cursor.reset()
    heroBand.closeMenu()
  }
  // Opening the popup refreshes an inbox older than 30 seconds.
  function refreshIfStale() {
    if (root.active)
      TicketStore.refreshIfStale(30000)
  }
  onActiveChanged: {
    if (active)
      refreshIfStale()
    else {
      closeReading()
      editingSettings = false
    }
  }
  // The popup builds this view on its first open with `active` already true,
  // so onActiveChanged never fires for that open.
  Component.onCompleted: refreshIfStale()
  onEditingSettingsChanged: {
    if (editingSettings) {
      closeReading()
      settingsView.resetScroll()
      Qt.callLater(settingsView.focusBack)
    } else
      Qt.callLater(function () {
        root.forceActiveFocus()
      })
  }
  // One ticket open at a time. Opening marks it read; it keeps its place
  // (the store's hold) until it closes, then moves or hides like any read ticket.
  readonly property string holdKey: "inbox-" + Math.random().toString(36).slice(2)
  function toggleTicket(id) {
    var opening = expandedIds.indexOf(id) < 0
    var found = opening ? TicketStore.ticketById(id) : null
    // From the overview, a read ticket that "Hide read tickets" keeps out of
    // the list: held as it would be unread, it is listed while it is open.
    var surfaced = opening && !found && TicketStore.inInbox(id)
    if (surfaced) {
      TicketStore.hold(holdKey, id, false)
      found = TicketStore.ticketById(id)
    }
    if (opening && !found)
      return
    var onTicket = cursor.index >= firstTicketStop && cursor.index < paneFirstStop
    var part = onTicket ? (cursor.index - firstTicketStop) % stopsPerTicket : 0
    // Wide, from the overview: read before the selection swaps the pane's stops.
    var onOverview = wide && !selected && cursor.index >= paneFirstStop && cursor.index < paneFirstStop + paneStops
    // Small: where the ticket's card is in the view now, kept while the
    // cards lay out again (see revealAnchor).
    var current = found || TicketStore.ticketById(id)
    var before = !wide && current ? ticketRows.itemAt(current.index) as TicketRow : null
    var offset = before ? rowTop(before) - ticketList.contentY : 0
    // Swap the hold before collapsing the other ticket, so the list re-sorts once.
    if (opening) {
      openedSince = found.ticket.since
      TicketStore.hold(holdKey, id, surfaced ? false : found.ticket.read)
    }
    expandedIds = opening ? [id] : []
    if (opening)
      TicketStore.markRead(id)
    else
      TicketStore.hold(holdKey, "")
    // The ticket may have moved: keep the cursor and the view on it.
    var now = TicketStore.ticketById(id)
    if (!now)
      return
    // From the overview the cursor goes to the ticket's row.
    if (onTicket || onOverview)
      cursor.index = firstTicketStop + now.index * stopsPerTicket + part
    // Wide rows never change height: the row can be placed at once.
    if (wide || !before) {
      revealTicket(now.index)
      return
    }
    revealAnchor = {
      id: id,
      offset: offset
    }
    anchorTimer.restart()
    placeAnchor()
  }
  // Small: opening a ticket closes the one before it, and both cards change
  // height only after the list's next layout passes; a scroll made from the
  // old places would carry the ticket out of view. So the card keeps the
  // place in the view it had when clicked ({ id, offset }), set again after
  // every layout pass for a fixed time (as FoamyWheelScroll follows an item)
  // or until the user drags the list (a wheel notch in that time does not end
  // it). The whole card shows when it fits; a taller
  // card shows its top.
  property var revealAnchor: null
  // The notice bar takes its height from the list: what is being read keeps
  // its place then, so the anchor ends.
  onBarShownChanged: revealAnchor = null
  Timer {
    id: anchorTimer
    interval: 450
    onTriggered: root.revealAnchor = null
  }
  Connections {
    target: root.revealAnchor ? body : null
    function onPositioningComplete() {
      root.placeAnchor()
    }
  }
  Connections {
    target: root.revealAnchor ? ticketList : null
    function onHeightChanged() {
      root.placeAnchor()
    }
    function onMovementStarted() {
      root.revealAnchor = null
    }
  }
  // The top of a ticket's card in the list's content (below its section header).
  function rowTop(row: TicketRow): real {
    return row.mapToItem(ticketList.contentItem, 0, 0).y + (row.sectionHeader.visible ? row.sectionHeader.height : 0)
  }
  function placeAnchor() {
    var found = revealAnchor ? TicketStore.ticketById(revealAnchor.id) : null
    var row = found ? ticketRows.itemAt(found.index) as TicketRow : null
    if (!row)
      return
    var top = rowTop(row)
    var card = row.height - (row.sectionHeader.visible ? row.sectionHeader.height : 0)
    var offset = Math.max(FoamyStyle.gap, Math.min(revealAnchor.offset, ticketList.height - card - FoamyStyle.gap))
    ticketList.contentY = Math.max(0, Math.min(ticketList.contentHeight - ticketList.height, top - offset))
  }
  // Opens the ticket (from a notification), or just shows the inbox when it
  // has left it.
  function showTicket(id) {
    editingSettings = false
    if (expandedIds.indexOf(id) < 0) {
      toggleTicket(id)
      return
    }
    var found = TicketStore.ticketById(id)
    if (found)
      revealTicket(found.index)
  }
  onExpandedIdsChanged: if (expandedIds.length === 0)
    TicketStore.hold(holdKey, "")
  Component.onDestruction: TicketStore.hold(holdKey, "")
  // Scrolls so the ticket's top is in view, after the list lays out.
  function revealTicket(index) {
    body.forceLayout()
    var row = ticketRows.itemAt(index) as TicketRow
    if (!row)
      return
    var y = rowTop(row)
    var bottom = y + Math.min(row.height, ticketList.height)
    if (y < ticketList.contentY)
      ticketList.contentY = Math.max(0, y - FoamyStyle.gap)
    else if (bottom > ticketList.contentY + ticketList.height)
      ticketList.contentY = Math.max(0, Math.min(ticketList.contentHeight - ticketList.height, bottom - ticketList.height))
  }
  function toggleRead(id, index) {
    TicketStore.toggleRead(id)
    if (!TicketStore.hideRead)
      return
    // With read tickets hidden, the ticket leaves the list: keep the cursor on its neighbour.
    expandedIds = expandedIds.filter(function (value) {
      return value !== id
    })
    cursor.index = TicketStore.count ? firstTicketStop + Math.min(index, TicketStore.count - 1) * stopsPerTicket : settingsStop
    root.forceActiveFocus()
  }
  function markAllRead() {
    if (TicketStore.hideRead)
      closeReading()
    TicketStore.markAllRead()
  }
  // The notice bar's "Show": lets in the update the store holds back while a
  // ticket is open. Small: the ticket closes, which releases the update, and
  // the list goes to its top. Wide: the update is applied under the selected
  // ticket, which stays selected and read (as when it was selected), unless
  // it has left the inbox.
  property bool applyingUpdates: false
  function showUpdates() {
    if (!wide) {
      closeReading()
      ticketList.contentY = 0
      return
    }
    var id = expandedIds.length > 0 ? expandedIds[0] : ""
    // This view stops counting as a reader for the moment of the flush.
    applyingUpdates = true
    TicketStore.flush()
    applyingUpdates = false
    if (id === "")
      return
    if (TicketStore.ticketById(id))
      TicketStore.markRead(id)
    else
      expandedIds = []
  }
  function ticketIndex() {
    return Math.floor((cursor.index - firstTicketStop) / stopsPerTicket)
  }
  function activateCursor() {
    if (cursor.index === markAllStop) {
      markAllRead()
      return
    }
    if (cursor.index === settingsStop) {
      if (heroBand.settingsInMenu)
        heroBand.openMenu(true)
      else
        editingSettings = true
      return
    }
    if (cursor.index === refreshStop) {
      TicketStore.refresh()
      return
    }
    var paneAt = cursor.index - paneFirstStop
    if (paneAt >= 0 && paneAt < paneStops) {
      // The conversation stop (3) only scrolls: Enter there does nothing.
      if (!selected && paneAt < TicketStore.overview.awaiting.length)
        toggleTicket(TicketStore.overview.awaiting[paneAt].id)
      else if (!selected)
        ticketOverview.toggleMore()
      else if (paneAt === 0)
        toggleRead(selected.ticket.id, selected.index)
      else if (paneAt === 1)
        TicketStore.openTicket(selected.ticket.id)
      else if (paneAt === 2)
        toggleTicket(selected.ticket.id)
      return
    }
    var index = ticketIndex()
    if (index < 0 || index >= TicketStore.count)
      return
    var id = TicketStore.tickets.get(index).id
    var part = (cursor.index - firstTicketStop) % stopsPerTicket
    if (part === 0)
      toggleTicket(id)
    else if (part === 1)
      toggleRead(id, index)
    else
      TicketStore.openTicket(id)
  }
  function reveal() {
    // Wide: the overview's rows and its link scroll in their own list.
    if (wide && !selected && cursor.index >= paneFirstStop && cursor.index < paneFirstStop + paneStops) {
      ticketOverview.revealRow(cursor.index - paneFirstStop)
      return
    }
    var ticket = ticketRows.itemAt(ticketIndex()) as TicketRow
    if (!ticket || cursor.index < firstTicketStop || cursor.index >= paneFirstStop)
      return
    var item = (cursor.index - firstTicketStop) % stopsPerTicket === 0 ? ticket : ticket.openButton
    var y = item.mapToItem(ticketList.contentItem, 0, 0).y
    // Tall expanded tickets keep their top in view; actions scroll to the actual button.
    if (y < ticketList.contentY)
      ticketList.contentY = Math.max(0, y)
    else if (y + Math.min(item.height, ticketList.height) > ticketList.contentY + ticketList.height)
      ticketList.contentY = Math.max(0, Math.min(ticketList.contentHeight - ticketList.height, y + Math.min(item.height, ticketList.height) - ticketList.height))
  }
  onMoveRequested: function (dx, dy) {
    var direction = dy || dx
    // On the conversation, Up and Down scroll it; at its end the cursor moves on.
    if (selected && cursor.index === conversationStop && dy !== 0 && ticketPane.scrollBy(dy))
      return
    cursor.move(direction)
    // "Mark all as read" is disabled while nothing is unread; the cursor stops at the top.
    if (cursor.index === markAllStop && TicketStore.unreadCount === 0) {
      if (direction < 0)
        cursor.index = settingsStop
      else
        cursor.move(direction)
    }
    reveal()
  }
  onActivateRequested: activateCursor()
  onCloseRequested: {
    closeReading()
    root.closeView()
  }
  onTabRequested: function (direction) {
    root.switchPanel(direction)
  }
  onTextKey: function (text, modifiers) {
    if (!cursor.plain(modifiers))
      return
    if (text === "u" && TicketStore.canUndoMarkAll)
      TicketStore.undoMarkAll()
    else if (text === "s")
      editingSettings = true
    else if (text === "r")
      TicketStore.refresh()
    else if (text === "m")
      showMore()
  }
  // The ticket under the cursor opens; once open, each press shows one more
  // thing: the newest clipped comment in full, then the earlier comments.
  // Wide: the next folded thing in the pane (a long comment, a quote).
  function showMore() {
    if (selected && cursor.index >= paneFirstStop && cursor.index < paneFirstStop + paneStops) {
      ticketPane.showMore()
      return
    }
    var index = ticketIndex()
    var row = cursor.index >= firstTicketStop && cursor.index < paneFirstStop ? ticketRows.itemAt(index) as TicketRow : null
    if (!row)
      return
    if (expandedIds.indexOf(row.ticket.id) < 0)
      toggleTicket(row.ticket.id)
    else if (wide)
      ticketPane.showMore()
    else
      row.showMore()
  }
  readonly property var sectionTitles: ({
      mine: FoamyI18n.t("Assigned to you"),
      unassigned: FoamyI18n.t("Unassigned in your groups"),
      waiting: FoamyI18n.t("Waiting on others")
    })

  // "Mark all as read" shows only while there are tickets to mark.
  readonly property bool markAllShown: ZendeskAccount.signedIn && TicketStore.count > 0
  // The band's meta. A state is said once: while the list is empty its block
  // names the state, so the meta is left with the account's host (not signed
  // in: the footer that names it is hidden) or the schedule state.
  readonly property string bandMeta: {
    if (!ZendeskAccount.signedIn)
      return Model.host(ZendeskAccount.address)
    if (TicketStore.count === 0)
      return TicketStore.snoozed ? FoamyI18n.t("Snoozed") : TicketStore.withinSchedule ? "" : FoamyI18n.t("Outside your schedule")
    var counts = TicketStore.unreadCount ? FoamyI18n.tn("%1 unread", TicketStore.unreadCount) + (TicketStore.count > TicketStore.unreadCount ? " · " + FoamyI18n.tn("%1 tickets", TicketStore.count) : "") : FoamyI18n.t("All read")
    return counts + (TicketStore.snoozed ? " · " + FoamyI18n.t("snoozed") : TicketStore.withinSchedule ? "" : " · " + FoamyI18n.t("outside your schedule"))
  }

  FoamyHeroBand {
    id: heroBand
    visible: !root.editingSettings
    width: parent.width
    title: "Zendesk"
    iconName: "zendesk"
    meta: root.bandMeta
    // Snooze and Settings live in the ⋯ menu: Mark all as read and ⋯ on the
    // right. Without Mark all as read, ⋯ keeps the last slot and its menu;
    // not signed in there is no Snooze either, and the cog takes the slot.
    maxButtons: root.markAllShown ? 2 : 1
    settingsHasCursor: cursor.at(root.settingsStop)
    menuHasCursor: cursor.at(root.settingsStop)
    onSettingsClicked: root.editingSettings = true
    onSettingsHovered: function (hovered) {
      if (hovered)
        cursor.hover(root.settingsStop)
    }
    onMenuHovered: function (hovered) {
      if (hovered)
        cursor.hover(root.settingsStop)
    }
    menuItems: [
      FoamyMenuItem {
        objectName: "snoozeItem"
        // Not signed in, nothing is checked or announced: nothing to snooze.
        visible: ZendeskAccount.signedIn
        text: TicketStore.snoozed ? FoamyI18n.t("Stop snoozing") : TicketStore.withinSchedule ? FoamyI18n.t("Snooze until tomorrow") : FoamyI18n.t("Resume now")
        iconName: TicketStore.withinSchedule ? "moon" : "sun"
        onTriggered: TicketStore.toggleSnooze()
      }
    ]
    trailing: [
      FoamyAction {
        objectName: "markAllRead"
        visible: root.markAllShown
        iconName: "check-check"
        tooltipText: FoamyI18n.t("Mark all as read")
        actionEnabled: TicketStore.unreadCount > 0
        hasCursor: cursor.at(root.markAllStop)
        onHoveredChanged: if (hovered && actionEnabled)
          cursor.hover(root.markAllStop)
        onClicked: root.markAllRead()
      }
    ]
  }
  Flickable {
    id: ticketList
    objectName: "ticketList"
    visible: !root.editingSettings
    anchors.top: heroBand.bottom
    // The list ends above the notice bar, so the bar never covers a ticket.
    anchors.bottom: root.barShown ? statusBar.top : root.footerShown ? footer.top : parent.bottom
    anchors.left: parent.left
    width: root.paneShown ? root.listWidth : parent.width
    contentWidth: width
    contentHeight: body.y + body.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      policy: Controls.ScrollBar.AsNeeded
    }
    FoamyWheelScroll {
      target: ticketList
    }
    Column {
      id: body
      // Wide: the empty-state block sits at 40 % of the free height, not at
      // the top of a blank card. An offset, not padding: the body's own
      // height (and with it inboxImplicitHeight) never depends on the list's.
      y: root.wide && emptyState.visible ? Math.max(0, Math.round((ticketList.height - implicitHeight) * 0.4)) : 0
      width: ticketList.width
      spacing: 0
      topPadding: FoamyStyle.gap
      bottomPadding: FoamyStyle.gapLarge
      Column {
        id: emptyState
        objectName: "emptyState"
        // Why the list is empty. Not signed in, the account's state:
        // not_configured, signed_out, checking, waiting, expired, error or
        // unavailable. Signed in: failed, loading or caughtup.
        readonly property string kind: !ZendeskAccount.signedIn ? ZendeskAccount.state : !TicketStore.loaded ? (TicketStore.error !== "" ? "failed" : "loading") : "caughtup"
        // The line under the title is the reason for an error.
        readonly property bool reason: kind === "error" || kind === "unavailable" || kind === "failed"
        readonly property color tone: kind === "caughtup" ? FoamyPalette.success : reason || kind === "expired" ? FoamyPalette.error : FoamyPalette.accent
        readonly property string title: {
          switch (kind) {
          case "signed_out":
            return FoamyI18n.t("Signed out")
          case "checking":
            return FoamyI18n.t("Checking the sign-in…")
          case "waiting":
            return FoamyI18n.t("Waiting for the browser…")
          case "expired":
            return FoamyI18n.t("Sign-in expired")
          case "error":
          case "unavailable":
            return FoamyI18n.t("Can't sign in")
          case "failed":
            return FoamyI18n.t("Couldn't load tickets")
          case "loading":
            return FoamyI18n.t("Loading tickets…")
          case "caughtup":
            return FoamyI18n.t("All caught up")
          default:
            return FoamyI18n.t("Sign in to see your tickets")
          }
        }
        readonly property string detail: {
          switch (kind) {
          case "signed_out":
            return FoamyI18n.t("Sign in again in the settings.")
          case "checking":
          case "loading":
            return ""
          case "waiting":
            return FoamyI18n.t("Finish signing in in your browser.")
          case "expired":
            return FoamyI18n.t("Sign in again to keep checking for updates.")
          case "error":
            return ZendeskAccount.error
          case "unavailable":
            return FoamyI18n.t("This plugin's helper isn't available for this CPU.")
          case "failed":
            return TicketStore.error
          case "caughtup":
            return FoamyI18n.t("Your tickets and unassigned tickets in your groups show up here.")
          default:
            return FoamyI18n.t("Connect your Zendesk account in the settings.")
          }
        }
        readonly property string iconName: {
          switch (kind) {
          case "checking":
          case "loading":
            return "refresh-cw"
          case "waiting":
            return "globe"
          case "expired":
            return "clock"
          case "error":
          case "unavailable":
            return "triangle-alert"
          case "failed":
            return "disconnected"
          case "caughtup":
            return "check-check"
          default:
            return "zendesk"
          }
        }
        // At most one button: "Open settings", or the state's own action.
        readonly property bool settingsOffered: ["checking", "waiting", "expired", "unavailable", "failed", "loading", "caughtup"].indexOf(kind) < 0
        readonly property string action: kind === "waiting" ? FoamyI18n.t("Cancel") : kind === "expired" ? FoamyI18n.t("Sign in") : kind === "failed" && !TicketStore.helperMissing ? FoamyI18n.t("Retry") : ""
        // The text keeps the Small panel's measure in Wide.
        readonly property real textWidth: Math.min(width, FoamyStyle.popupWidth) - FoamyStyle.padding * 2
        visible: TicketStore.count === 0
        width: parent.width
        topPadding: FoamyStyle.gapLarge
        bottomPadding: FoamyStyle.gapLarge
        spacing: FoamyStyle.gap
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: 44
          height: 44
          radius: 22
          color: Qt.alpha(emptyState.tone, 0.14)
          FoamyIcon {
            id: emptyIcon
            objectName: "emptyIcon"
            anchors.centerIn: parent
            width: 22
            height: 22
            name: emptyState.iconName
            // Measured on the tinted disc it is drawn on.
            color: FoamyPalette.onSurface(emptyState.tone, Qt.tint(FoamyPalette.background, parent.color))
            // Turns while the sign-in is checked or the first inbox is being
            // fetched, like the footer's Refresh.
            RotationAnimation on rotation {
              running: (emptyState.kind === "checking" || (emptyState.kind === "loading" && TicketStore.loading)) && emptyState.visible && root.active && !FoamyMotion.reduceMotion
              from: 0
              to: 360
              duration: FoamyMotion.spin
              loops: Animation.Infinite
              onStopped: emptyIcon.rotation = 0
            }
          }
        }
        PlainText {
          objectName: "emptyTitle"
          anchors.horizontalCenter: parent.horizontalCenter
          width: emptyState.textWidth
          horizontalAlignment: Text.AlignHCenter
          text: emptyState.title
          font.pixelSize: FoamyStyle.font.subtitle
          font.weight: Font.DemiBold
          Accessible.role: Accessible.Heading
        }
        PlainText {
          objectName: "emptyDetail"
          anchors.horizontalCenter: parent.horizontalCenter
          width: emptyState.textWidth
          horizontalAlignment: Text.AlignHCenter
          text: emptyState.detail
          visible: text !== ""
          color: emptyState.reason ? FoamyPalette.onSurface(FoamyPalette.error) : FoamyPalette.mutedText
          font.pixelSize: FoamyStyle.font.bodySmall
          Accessible.role: emptyState.reason ? Accessible.AlertMessage : Accessible.StaticText
          Accessible.name: text
        }
        FoamyButton {
          objectName: "openSettings"
          visible: emptyState.settingsOffered
          anchors.horizontalCenter: parent.horizontalCenter
          text: FoamyI18n.t("Open settings")
          // After an error the settings are where to look, not a sure fix:
          // no call to action.
          kind: emptyState.kind === "error" ? "secondary" : "primary"
          onClicked: root.editingSettings = true
        }
        FoamyButton {
          objectName: "emptyAction"
          visible: emptyState.action !== ""
          anchors.horizontalCenter: parent.horizontalCenter
          text: emptyState.action
          kind: emptyState.kind === "expired" ? "primary" : "secondary"
          busy: emptyState.kind === "failed" && TicketStore.loading
          onClicked: {
            if (emptyState.kind === "waiting")
              ZendeskAccount.cancelSignIn()
            else if (emptyState.kind === "expired")
              ZendeskAccount.signIn()
            else
              TicketStore.refresh()
          }
        }
      }
      Repeater {
        id: ticketRows
        model: TicketStore.tickets
        TicketRow {
          required property var model
          required property int index
          readonly property int firstStop: root.firstTicketStop + index * root.stopsPerTicket
          ticket: model
          wide: root.wide
          objectName: "ticket-" + model.id
          // Read tickets take one line; unread ones show their latest comment.
          compact: model.read
          sectionTitle: model.sectionHead ? root.sectionTitles[model.sectionHead] : ""
          sectionCount: model.sectionSize
          now: root.fixedNow > 0 ? root.fixedNow : clock.date.getTime()
          x: FoamyStyle.gapLarge
          width: body.width - FoamyStyle.gapLarge * 2
          expanded: !root.wide && root.expandedIds.indexOf(model.id) >= 0
          selected: root.wide && root.expandedIds.indexOf(model.id) >= 0
          cursorPart: cursor.index >= firstStop && cursor.index < firstStop + root.stopsPerTicket ? cursor.index - firstStop : -1
          onHovered: function (part) {
            cursor.hover(firstStop + part)
          }
          onToggleRequested: root.toggleTicket(model.id)
          onOpenRequested: TicketStore.openTicket(model.id)
          onReadToggleRequested: root.toggleRead(model.id, index)
        }
      }
      // Below the last ticket, where the ones left out would be.
      PlainText {
        objectName: "truncatedNote"
        visible: TicketStore.count > 0 && text !== ""
        x: FoamyStyle.gapLarge
        width: body.width - FoamyStyle.gapLarge * 2
        topPadding: FoamyStyle.gap
        horizontalAlignment: Text.AlignHCenter
        text: TicketStore.ticketsTruncated ? FoamyI18n.t("Showing the 100 most recently updated tickets") : TicketStore.groupsTruncated ? FoamyI18n.t("Showing unassigned tickets from your first 20 groups") : ""
        color: FoamyPalette.mutedText
        font.pixelSize: FoamyStyle.font.bodySmall
      }
    }
  }
  // Wide: the reading pane beside the list. It runs down to the footer: the
  // notice bar takes room from the list only.
  Rectangle {
    id: paneEdge
    visible: root.paneShown && !root.editingSettings
    anchors.left: ticketList.right
    anchors.top: ticketList.top
    anchors.bottom: root.footerShown ? footer.top : parent.bottom
    width: FoamyStyle.borderWidth
    color: FoamyPalette.divider
  }
  Item {
    id: paneArea
    visible: paneEdge.visible
    anchors.left: paneEdge.right
    anchors.right: parent.right
    anchors.top: ticketList.top
    anchors.bottom: paneEdge.bottom
    TicketPane {
      id: ticketPane
      objectName: "ticketPane"
      anchors.fill: parent
      visible: root.selected !== null
      ticket: root.selected ? root.selected.ticket : null
      openedSince: root.openedSince
      now: root.fixedNow > 0 ? root.fixedNow : clock.date.getTime()
      cursorPart: root.selected && cursor.index >= root.paneFirstStop && cursor.index < root.paneFirstStop + root.paneStops ? cursor.index - root.paneFirstStop : -1
      onHovered: function (part) {
        cursor.hover(root.paneFirstStop + part)
      }
      onReadToggleRequested: root.toggleRead(root.selected.ticket.id, root.selected.index)
      // Hide ticket: back to the overview.
      onCloseRequested: if (root.selected)
        root.toggleTicket(root.selected.ticket.id)
      onOpenRequested: TicketStore.openTicket(root.selected.ticket.id)
    }
    TicketOverview {
      id: ticketOverview
      objectName: "ticketOverview"
      anchors.fill: parent
      visible: root.selected === null
      summary: TicketStore.overview
      showWaiting: TicketStore.groupWaiting
      now: root.fixedNow > 0 ? root.fixedNow : clock.date.getTime()
      cursorRow: !root.selected && cursor.index >= root.paneFirstStop && cursor.index < root.paneFirstStop + root.paneStops ? cursor.index - root.paneFirstStop : -1
      onHovered: function (row) {
        cursor.hover(root.paneFirstStop + row)
      }
      onSelectRequested: function (id) {
        root.toggleTicket(id)
      }
    }
  }
  FoamyPanelFooter {
    id: footer
    visible: !root.editingSettings && root.footerShown
    anchors.bottom: parent.bottom
    width: parent.width
    horizontalPadding: FoamyStyle.padding
    source: ZendeskAccount.signedIn ? Model.host(ZendeskAccount.address) : ""
    // Always how old the inbox on show is; in the error tone while a refresh
    // error stands (the notice bar says which). Without an inbox there is
    // nothing to date and the list says why: here is when the next try is.
    status: TicketStore.loaded ? FoamyI18n.updatedAgo(TicketStore.lastUpdated, clock.date.getTime()) : TicketStore.error !== "" ? root.retryText : ""
    statusError: root.refreshFailed
    showRefresh: ZendeskAccount.signedIn
    refreshing: TicketStore.loading
    refreshEnabled: TicketStore.connected && !TicketStore.loading
    refreshHasCursor: cursor.at(root.refreshStop)
    onRefreshHovered: function (hovered) {
      if (hovered)
        cursor.hover(root.refreshStop)
    }
    onRefreshClicked: TicketStore.refresh()
  }

  readonly property string retryText: {
    var left = TicketStore.retryAt - clock.date.getTime()
    return TicketStore.active && left > 0 ? FoamyI18n.tn("Trying again in %1 minutes", Math.max(1, Math.ceil(left / 60000))) : FoamyI18n.t("Not updated")
  }

  // One line of the notice bar: what happened and, at its end, a text link
  // for what can be done about it.
  component NoticeRow: Item {
    id: noticeRow
    property alias text: noticeLabel.text
    // An error: in the urgent colour, announced as an alert.
    property bool failing: false
    property string linkText: ""
    // Object names of the text and the link, for the tests.
    property string textName: ""
    property string linkName: ""
    signal linkClicked
    width: parent ? parent.width : 0
    height: Math.max(FoamyStyle.actionSize, noticeLabel.implicitHeight + FoamyStyle.gapSmall * 2)
    PlainText {
      id: noticeLabel
      objectName: noticeRow.textName
      anchors.left: parent.left
      anchors.leftMargin: FoamyStyle.gapLarge
      anchors.right: noticeLink.visible ? noticeLink.left : parent.right
      anchors.rightMargin: noticeLink.visible ? FoamyStyle.gapSmall : FoamyStyle.gapLarge
      anchors.verticalCenter: parent.verticalCenter
      font.pixelSize: FoamyStyle.font.bodySmall
      // Measured on the notice bar's fill (statusBar.color).
      color: noticeRow.failing ? FoamyPalette.onSurface(FoamyPalette.error, Qt.tint(FoamyPalette.background, FoamyPalette.menuFill)) : FoamyPalette.text
      maximumLineCount: 2
      elide: Text.ElideRight
      Accessible.role: noticeRow.failing ? Accessible.AlertMessage : Accessible.StaticText
      Accessible.name: text
    }
    FoamyCursorSurface {
      id: noticeLink
      objectName: noticeRow.linkName
      visible: noticeRow.linkText !== ""
      anchors.right: parent.right
      anchors.rightMargin: FoamyStyle.gapSmall
      anchors.verticalCenter: parent.verticalCenter
      width: noticeLinkLabel.implicitWidth + FoamyStyle.gap * 2
      height: FoamyStyle.actionSize - 4
      foreground: FoamyPalette.accent
      onClicked: noticeRow.linkClicked()
      Accessible.role: Accessible.Button
      Accessible.name: noticeRow.linkText
      Accessible.onPressAction: noticeRow.linkClicked()
      PlainText {
        id: noticeLinkLabel
        anchors.centerIn: parent
        text: noticeRow.linkText
        color: FoamyPalette.onSurface(FoamyPalette.accent)
        font.pixelSize: FoamyStyle.font.bodySmall
        font.weight: Font.DemiBold
        wrapMode: Text.NoWrap
      }
    }
  }

  // The notice bar, between the list and the footer: updates held back while
  // a ticket is open, the last "Mark all as read" with its Undo, and errors,
  // in that order when several stand. The list ends above it, so it covers no
  // ticket, and what is being read keeps its place when a notice comes.
  Rectangle {
    id: statusBar
    objectName: "statusBar"
    visible: !root.editingSettings && root.barShown
    anchors.bottom: root.footerShown ? footer.top : parent.bottom
    anchors.bottomMargin: root.footerShown ? FoamyStyle.gap : FoamyStyle.gapLarge
    anchors.horizontalCenter: ticketList.horizontalCenter
    // An empty Wide list is the card's whole width: the bar keeps Small's.
    width: Math.min(ticketList.width, FoamyStyle.popupWidth) - FoamyStyle.gapLarge * 2
    height: statusRows.implicitHeight
    radius: FoamyStyle.radius
    color: Qt.tint(FoamyPalette.background, FoamyPalette.menuFill)
    border.width: FoamyStyle.borderWidth
    border.color: FoamyPalette.border
    // The bar takes every press on it: nothing beside its links reacts.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }
    Column {
      id: statusRows
      width: parent.width
      topPadding: FoamyStyle.gapSmall
      bottomPadding: FoamyStyle.gapSmall
      NoticeRow {
        objectName: "updatesNotice"
        visible: TicketStore.pendingChanges > 0
        textName: "updatesText"
        text: FoamyI18n.tn("%1 updates waiting", TicketStore.pendingChanges)
        linkName: "showUpdates"
        linkText: FoamyI18n.t("Show")
        onLinkClicked: root.showUpdates()
      }
      NoticeRow {
        objectName: "markedNotice"
        visible: TicketStore.notice !== "" && !root.openFailed
        textName: "statusText"
        text: TicketStore.notice
        linkName: "undoMarkAll"
        linkText: TicketStore.canUndoMarkAll ? FoamyI18n.t("Undo") : ""
        onLinkClicked: TicketStore.undoMarkAll()
      }
      // A failed refresh while an inbox is shown: the footer keeps its age.
      NoticeRow {
        objectName: "refreshError"
        visible: root.refreshFailed
        failing: true
        text: TicketStore.error
        linkName: "retryRefresh"
        // Without the helper there is nothing to try again.
        linkText: TicketStore.helperMissing ? "" : FoamyI18n.t("Retry")
        onLinkClicked: TicketStore.refresh()
      }
      NoticeRow {
        objectName: "openError"
        visible: root.openFailed
        failing: true
        text: TicketStore.notice
      }
      // What was marked or snoozed is kept only in memory.
      NoticeRow {
        objectName: "saveError"
        visible: TicketStore.saveError !== ""
        failing: true
        text: TicketStore.saveError + "\n" + FoamyI18n.t("Kept only until the shell restarts.")
      }
    }
  }

  FoamySettingsPage {
    id: settingsView
    visible: root.editingSettings
    width: parent.width
    height: parent.height
    saving: root.saving
    error: root.settingsError
    retryable: root.retryable
    onBack: root.editingSettings = false
    onRetry: root.retryRequested()
    // Wide keeps its size on Settings; the sections keep the standard
    // settings width, centred.
    readonly property real columnWidth: FoamyStyle.popupWidthWide - FoamyStyle.padding * 2

    // The account comes first: "Open settings" on the first run lands on it.
    // Signed in, it is who and Sign out. Signed out, a form read from the
    // top: what an admin must do first, the three fields, the redirect URL
    // they give, then the state and Sign in. Nothing here is secret: the
    // OAuth tokens live in the keyring, handled by the helper.
    FoamySettingsSection {
      id: zendeskSection
      objectName: "zendeskSection"
      width: Math.min(parent.width, settingsView.columnWidth)
      anchors.horizontalCenter: parent.horizontalCenter
      title: FoamyI18n.t("Account")
      description: ZendeskAccount.signedIn ? "" : FoamyI18n.t("Before you can sign in, a Zendesk admin must create an OAuth client. The sign-in is kept in your keyring.")
      info: FoamyI18n.t("A Zendesk admin creates the OAuth client once, in Admin Center › Apps and integrations › APIs › OAuth clients: kind Public, redirect URL %1, read access. Enter its unique identifier as the OAuth client ID.", [settingsView.redirectUrl])
      FoamyTextSettingField {
        id: addressField
        objectName: "addressField"
        visible: !ZendeskAccount.signedIn
        enabled: settingsView.connectionEditable
        opacity: enabled ? 1 : FoamyStyle.disabledOpacity
        width: parent.width
        label: FoamyI18n.t("Zendesk address")
        placeholderText: "acme.zendesk.com"
        value: root.pref("zendeskAddress")
        validate: function (text) {
          return new RegExp(Schema.addressPattern).test(text) || FoamyI18n.t("Enter your Zendesk address, like acme or acme.zendesk.com.")
        }
        onCommitted: function (value) {
          root.saveRequested("zendeskAddress", value)
        }
      }
      FoamyTextSettingField {
        id: clientIdField
        objectName: "clientIdField"
        visible: !ZendeskAccount.signedIn
        enabled: settingsView.connectionEditable
        opacity: enabled ? 1 : FoamyStyle.disabledOpacity
        width: parent.width
        label: FoamyI18n.t("OAuth client ID")
        placeholderText: FoamyI18n.t("Unique identifier")
        value: root.pref("oauthClientId")
        validate: function (text) {
          return /^$|^[A-Za-z0-9_.-]{1,128}$/.test(text) || FoamyI18n.t("Enter the OAuth client's unique identifier.")
        }
        onCommitted: function (value) {
          root.saveRequested("oauthClientId", value)
        }
      }
      FoamyTextSettingField {
        id: portField
        objectName: "portField"
        visible: !ZendeskAccount.signedIn
        enabled: settingsView.connectionEditable
        opacity: enabled ? 1 : FoamyStyle.disabledOpacity
        width: parent.width
        label: FoamyI18n.t("Redirect port")
        // Empty means the default; the placeholder shows it.
        placeholderText: String(Schema.defaultPort)
        value: root.pref("oauthPort")
        validate: function (text) {
          return text === "" || (/^[0-9]{4,5}$/.test(text) && Number(text) >= 1024 && Number(text) <= 65535) || FoamyI18n.t("Choose a redirect port between 1024 and 65535.")
        }
        onCommitted: function (value) {
          root.saveRequested("oauthPort", value)
        }
      }
      PlainText {
        objectName: "redirectHint"
        visible: !ZendeskAccount.signedIn
        width: parent.width
        text: FoamyI18n.t("Redirect URL for the OAuth client: %1", [settingsView.redirectUrl])
        color: FoamyPalette.mutedText
        font.pixelSize: FoamyStyle.font.bodySmall
      }
      // Signed in, the only row. Signed out, the form's last: the state on
      // the reading start and Sign in at the end, after the fields it needs.
      RowLayout {
        objectName: "accountRow"
        width: parent.width
        // As tall as the page's toggle and dropdown rows.
        height: Math.max(implicitHeight, FoamyStyle.rowHeight + FoamyStyle.gapSmall)
        spacing: FoamyStyle.gapLarge
        Column {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: FoamyStyle.gapTiny
          PlainText {
            objectName: "accountTitle"
            width: parent.width
            text: settingsView.accountTitle
            font.pixelSize: FoamyStyle.font.subtitle
          }
          PlainText {
            objectName: "accountDetail"
            visible: text !== ""
            width: parent.width
            text: settingsView.accountDetail
            color: ZendeskAccount.state === "error" || ZendeskAccount.state === "unavailable" || ZendeskAccount.state === "expired" ? FoamyPalette.onSurface(FoamyPalette.error) : FoamyPalette.secondaryText
            font.pixelSize: FoamyStyle.font.bodySmall
          }
        }
        FoamyButton {
          objectName: "accountButton"
          focusable: true
          Layout.alignment: Qt.AlignVCenter
          text: ZendeskAccount.signedIn ? FoamyI18n.t("Sign out") : ZendeskAccount.state === "waiting" ? FoamyI18n.t("Cancel") : FoamyI18n.t("Sign in")
          kind: ZendeskAccount.signedIn || ZendeskAccount.state === "waiting" ? "secondary" : "primary"
          busy: ZendeskAccount.state === "checking" || ZendeskAccount.logoutProcess.running
          // Typed but not yet saved counts: the click saves the fields first.
          actionEnabled: ZendeskAccount.state !== "unavailable" && (ZendeskAccount.signedIn || ZendeskAccount.state === "waiting" || settingsView.connectionReady)
          onClicked: {
            if (ZendeskAccount.signedIn)
              ZendeskAccount.signOut()
            else if (ZendeskAccount.state === "waiting")
              ZendeskAccount.cancelSignIn()
            else if (settingsView.saveConnection())
              ZendeskAccount.signIn()
          }
        }
      }
    }

    FoamySettingsSection {
      width: Math.min(parent.width, settingsView.columnWidth)
      anchors.horizontalCenter: parent.horizontalCenter
      title: FoamyI18n.t("Panel")
      FoamyDropdown {
        objectName: "panelWidth"
        width: parent.width
        compact: true
        label: FoamyI18n.t("Size")
        description: FoamyI18n.t("Wide shows the list and a reading pane side by side.")
        value: root.pref("panelWidth")
        enabled: !root.saving
        queue: root.prefsQueue
        queueKey: "panelWidth"
        options: [
          {
            value: "standard",
            label: FoamyI18n.t("Small")
          },
          {
            value: "wide",
            label: FoamyI18n.t("Wide")
          }
        ]
        onChanged: function (value) {
          root.saveRequested("panelWidth", value)
        }
      }
      FoamyDropdown {
        objectName: "refreshSeconds"
        width: parent.width
        compact: true
        label: FoamyI18n.t("Refresh every")
        value: String(root.pref("refreshSeconds"))
        enabled: !root.saving
        queue: root.prefsQueue
        queueKey: "refreshSeconds"
        options: Schema.refreshChoices.map(function (seconds) {
          return {
            value: String(seconds),
            label: FoamyI18n.tn("%1 minutes", seconds / 60)
          }
        })
        onChanged: function (value) {
          root.saveRequested("refreshSeconds", Number(value))
        }
      }
    }
    FoamySettingsSection {
      width: Math.min(parent.width, settingsView.columnWidth)
      anchors.horizontalCenter: parent.horizontalCenter
      title: FoamyI18n.t("Read tickets")
      description: FoamyI18n.t("Read state stays on this computer; nothing changes in Zendesk.")
      FoamyToggle {
        objectName: "hideReadToggle"
        width: parent.width
        label: FoamyI18n.t("Hide read tickets")
        description: FoamyI18n.t("Read tickets leave the list and come back with their next update. The two settings below then have no effect.")
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

    FoamySettingsSection {
      width: Math.min(parent.width, settingsView.columnWidth)
      anchors.horizontalCenter: parent.horizontalCenter
      title: FoamyI18n.t("Notifications")
      description: FoamyI18n.t("A desktop notification for a new ticket or a new reply from someone else. None while this inbox is open, outside your schedule or while snoozed.")
      FoamyDropdown {
        objectName: "notify"
        width: parent.width
        compact: true
        label: FoamyI18n.t("Desktop notifications")
        value: root.pref("notify")
        enabled: !root.saving
        queue: root.prefsQueue
        queueKey: "notify"
        options: [
          {
            value: "off",
            label: FoamyI18n.t("Off")
          },
          {
            value: "mine",
            label: FoamyI18n.t("Assigned to you")
          },
          {
            value: "all",
            label: FoamyI18n.t("All tickets")
          }
        ]
        onChanged: function (value) {
          root.saveRequested("notify", value)
        }
      }
    }

    // Turning the schedule on scrolls the new day rows into view.
    property bool revealSchedule: false
    readonly property bool scheduleOn: root.pref("scheduleEnabled") === true
    onScheduleOnChanged: if (scheduleOn && revealSchedule) {
      revealSchedule = false
      Qt.callLater(function () {
        settingsView.ensureVisible(scheduleSection)
      })
    }
    FoamySettingsSection {
      id: scheduleSection
      width: Math.min(parent.width, settingsView.columnWidth)
      anchors.horizontalCenter: parent.horizontalCenter
      title: FoamyI18n.t("Schedule")
      description: settingsView.scheduleOn ? FoamyI18n.t("Local time. Turn a day off to skip it. Overnight ranges are supported.") : ""
      FoamyToggle {
        objectName: "scheduleEnabled"
        width: parent.width
        label: FoamyI18n.t("Use a weekly schedule")
        description: FoamyI18n.t("Dim or hide Zendesk outside your working hours.")
        checked: settingsView.scheduleOn
        enabled: !root.saving
        onClicked: {
          settingsView.revealSchedule = !checked
          root.saveRequested("scheduleEnabled", !checked)
        }
      }
      FoamyDropdown {
        objectName: "scheduleOutsideMode"
        visible: settingsView.scheduleOn
        width: parent.width
        compact: true
        label: FoamyI18n.t("Outside the schedule")
        value: root.pref("scheduleOutsideMode")
        enabled: !root.saving
        queue: root.prefsQueue
        queueKey: "scheduleOutsideMode"
        options: [
          {
            value: "mute",
            label: FoamyI18n.t("Dim")
          },
          {
            value: "hide",
            label: FoamyI18n.t("Hide")
          }
        ]
        onChanged: function (value) {
          root.saveRequested("scheduleOutsideMode", value)
        }
      }
      RowLayout {
        visible: settingsView.scheduleOn
        width: parent.width
        spacing: FoamyStyle.gap
        Item {
          Layout.fillWidth: true
        }
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
        model: settingsView.scheduleOn ? Schema.dayKeys : []
        FoamyScheduleDay {
          required property string modelData
          required property int index
          width: parent.width
          objectName: modelData
          label: FoamyI18n.t(Schema.dayLabels[index])
          labelComponent: Component {
            PlainText {}
          }
          fromLabel: FoamyI18n.t("From")
          toLabel: FoamyI18n.t("To")
          value: root.pref(modelData)
          enabled: !root.saving
          queue: root.prefsQueue
          queueKey: modelData
          onChanged: function (range) {
            root.saveRequested(modelData, range)
          }
          onInvalid: root.saveRequested(modelData, "invalid")
        }
      }
    }

    // What the fields hold now, saved or still being typed.
    readonly property bool connectionReady: addressField.field.text.trim() !== "" && addressField.problem(addressField.field.text.trim()) === "" && clientIdField.field.text.trim() !== "" && clientIdField.problem(clientIdField.field.text.trim()) === "" && portField.problem(portField.field.text.trim()) === ""
    // While a sign-in waits in the browser, the connection fields take no
    // input. A value typed then would be saved when its field loses the
    // focus (as when the browser takes it), which stops the sign-in, or when
    // the sign-in ends and the fields hide, which drops the user who just
    // signed in.
    readonly property bool connectionEditable: ZendeskAccount.state !== "waiting"
    // A connection field whose save the queue refuses or fails shows the
    // saved value again, and the same text can be sent again. A save the
    // queue refuses at once fails inside the field's own commit.
    Connections {
      target: root.prefsQueue
      function onFailed(key) {
        if (key === "zendeskAddress")
          addressField.saveFailed()
        else if (key === "oauthClientId")
          clientIdField.saveFailed()
        else if (key === "oauthPort")
          portField.saveFailed()
      }
    }
    // Saves any field still being edited. False when one is invalid (the
    // field says why), or when the saved connection is then not the one the
    // fields held: the queue refused a save (the field shows the saved value
    // again, the page the error) or keeps it waiting behind another save.
    // Sign in would then use the connection saved before.
    function saveConnection() {
      var typed = [addressField.field.text.trim(), clientIdField.field.text.trim(), portField.field.text.trim()]
      if (!(addressField.commitEdit(false) && clientIdField.commitEdit(false) && portField.commitEdit(false)))
        return false
      return root.pref("zendeskAddress") === typed[0] && root.pref("oauthClientId") === typed[1] && root.pref("oauthPort") === typed[2]
    }
    readonly property string redirectUrl: "http://127.0.0.1:" + (Number(root.pref("oauthPort")) || Schema.defaultPort) + "/callback"
    readonly property string accountTitle: {
      switch (ZendeskAccount.state) {
      case "checking":
        return FoamyI18n.t("Checking the sign-in…")
      case "signed_out":
        return FoamyI18n.t("Not signed in")
      case "waiting":
        return FoamyI18n.t("Waiting for the browser…")
      case "signed_in":
        return ZendeskAccount.user && ZendeskAccount.user.name ? FoamyI18n.t("Signed in as %1", [ZendeskAccount.user.name]) : FoamyI18n.t("Signed in")
      case "expired":
        return FoamyI18n.t("Sign-in expired")
      case "error":
      case "unavailable":
        return FoamyI18n.t("Can't sign in")
      default:
        return FoamyI18n.t("Not connected")
      }
    }
    readonly property string accountDetail: {
      switch (ZendeskAccount.state) {
      case "not_configured":
        return FoamyI18n.t("Enter the Zendesk address and OAuth client ID above.")
      case "waiting":
        return FoamyI18n.t("Finish signing in in your browser.")
      case "signed_in":
        {
          var email = ZendeskAccount.user && ZendeskAccount.user.email ? ZendeskAccount.user.email : ""
          // The error: why it isn't verified, or why sign-out didn't finish.
          return [email, ZendeskAccount.error].filter(function (part) {
            return part
          }).join(" · ")
        }
      case "expired":
        return FoamyI18n.t("Sign in again to keep checking for updates.")
      default:
        return ZendeskAccount.error
      }
    }
  }
}
