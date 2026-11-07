import QtQuick
import "kit"
import "Model.js" as Model

// One ticket: an accent rail while unread, the subject, status pills, the
// latest comment and a footer with its time and assignment; expanded, its
// comments newest first: those unread when it was opened (opening marks it
// read) and the one before them, the rest (and long comments) behind "Show
// earlier".
// Read tickets stay listed, dimmed, with "Mark as unread" (shown on hover) in
// place of "Mark as read". `compact` (read tickets) is one line: subject, sender, time and
// actions; expanding a compact ticket shows it in full.
Item {
  id: ticketRow
  property var ticket
  property bool expanded: false
  property bool compact: false
  // Shown above this ticket when it starts a section, e.g. "Waiting on others".
  property string sectionTitle: ""
  property int sectionCount: 0
  property int cursorPart: -1
  signal hovered(int part)
  signal toggleRequested()
  signal openRequested()
  signal readToggleRequested()
  readonly property alias bodyItem: bodySurface
  readonly property alias commentItem: comment
  readonly property alias detailsItem: timeline
  readonly property alias historyRepeater: history
  readonly property alias openButton: openButton
  readonly property alias readButton: readButton
  readonly property alias sectionHeader: sectionHeader
  readonly property alias moreButton: moreButton
  // The clock for "Yesterday", weekdays and dates.
  property double now: Date.now()
  // Every comment at full length.
  property bool showAll: false
  // What was unread when the ticket opened: opening marks it read, but the
  // timeline keeps showing those comments as new until it closes.
  property int openedSince: 0
  property int openedUpdates: 0
  onExpandedChanged: {
    if (expanded) { openedSince = ticket.since; openedUpdates = ticket.updates; }
    else showAll = false;
  }
  readonly property int historyCount: ticket.history ? ticket.history.count : 0
  readonly property int shownCount: showAll ? historyCount : Math.min(historyCount, Math.max(openedUpdates + 1, 2))
  property int clippedCount: 0
  function recountClipped() {
    var clipped = 0;
    for (var i = 0; i < history.count; i++) {
      var item = history.itemAt(i);
      if (item && item.visible && item.textItem.truncated) clipped++;
    }
    clippedCount = clipped;
  }
  onShownCountChanged: Qt.callLater(recountClipped)
  readonly property bool read: ticket.read === true
  // Read tickets are dimmed, except the one being read.
  readonly property bool muted: read && !expanded
  readonly property bool oneLine: compact && !expanded
  // The pointer is over the ticket (its actions included).
  readonly property bool pointerOver: rowHover.hovered || readButton.hovered || openButton.hovered
  // "Mark as unread" is an undo: it shows only on hover or under the keyboard
  // cursor, and keeps its place so nothing shifts when it appears.
  readonly property bool readActionShown: !read || pointerOver || cursorPart === 1
  readonly property int pad: oneLine ? FoamyStyle.gapSmall + 2 : FoamyStyle.rowPadding
  readonly property int unread: read ? 0 : ticket.updates
  readonly property color priorityTone: ticket.priority === "Urgent" ? FoamyPalette.onSurface(FoamyPalette.error)
    : ticket.priority === "High" ? FoamyPalette.onSurface(FoamyPalette.warning) : FoamyPalette.mutedText
  // On-hold waits like Pending (on a third party instead of the requester).
  readonly property color statusTone: FoamyPalette.onSurface(ticket.status === "Solved" ? FoamyPalette.success
    : ticket.status === "Pending" || ticket.status === "On-hold" ? FoamyPalette.warning : FoamyPalette.info)
  function format(ms, fmt) { return new Date(ms).toLocaleString(Qt.locale(FoamyI18n.formatLocale), fmt) }
  // A row's time: 10:40 today, then Yesterday, a weekday, 28 Oct, 28 Oct 2025.
  function when(ms) {
    var days = Model.daysAgo(ms, now);
    if (days <= 0) return format(ms, "HH:mm");
    if (days === 1) return FoamyI18n.t("Yesterday");
    if (days < 7) return format(ms, "ddd");
    return format(ms, new Date(ms).getFullYear() === new Date(now).getFullYear() ? "d MMM" : "d MMM yyyy");
  }
  // A comment's time: the row's day (today is left out) and the time.
  function stamp(ms) {
    var days = Model.daysAgo(ms, now);
    return days <= 0 ? format(ms, "HH:mm") : when(ms) + ", " + format(ms, "HH:mm");
  }
  function author(name, mine) { return mine ? FoamyI18n.t("You") : name }
  implicitHeight: column.implicitHeight
  height: implicitHeight

  component StatusLabel: Rectangle {
    required property string text
    property color tone: FoamyPalette.secondaryText
    implicitWidth: label.implicitWidth + FoamyStyle.gap * 2
    implicitHeight: label.implicitHeight + FoamyStyle.gapSmall * 2
    radius: FoamyStyle.pillRadius(height)
    color: Qt.alpha(tone, 0.10)
    PlainText { id: label; anchors.centerIn: parent; text: parent.text; color: parent.tone; font.pixelSize: FoamyStyle.font.bodySmall }
  }
  // Unread rail beside the whole ticket.
  Rectangle {
    id: rail
    objectName: "rail"
    x: 0; y: bodySurface.y + ticketRow.pad
    width: 3; height: bodySurface.height - ticketRow.pad * 2
    radius: 1.5
    color: ticketRow.read ? FoamyPalette.divider : FoamyPalette.accent
  }

  Column {
    id: column
    width: parent.width
    Item {
      id: sectionHeader
      visible: ticketRow.sectionTitle.length > 0
      width: parent.width
      height: FoamyStyle.rowHeight - FoamyStyle.gapSmall
      PlainText {
        id: sectionLabel
        x: FoamyStyle.rowPadding - 2
        anchors.verticalCenter: parent.verticalCenter
        text: ticketRow.sectionTitle.toUpperCase() + "  " + FoamyI18n.number(ticketRow.sectionCount)
        color: FoamyPalette.mutedText
        font.pixelSize: FoamyStyle.font.caption
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
        wrapMode: Text.NoWrap
        Accessible.role: Accessible.Heading
      }
      Rectangle {
        anchors.left: sectionLabel.right
        anchors.leftMargin: FoamyStyle.gap
        anchors.right: parent.right
        anchors.rightMargin: FoamyStyle.gap
        anchors.verticalCenter: parent.verticalCenter
        height: FoamyStyle.borderWidth
        color: FoamyPalette.divider
      }
    }
    FoamyCursorSurface {
      id: bodySurface
      width: parent.width
      height: body.implicitHeight + ticketRow.pad * 2
      foreground: FoamyPalette.text
      hasCursor: ticketRow.cursorPart === 0
      onHovered: ticketRow.hovered(0)
      onClicked: ticketRow.toggleRequested()
      HoverHandler { id: rowHover }
      Accessible.role: Accessible.Button
      Accessible.name: ticketRow.ticket.subject + (ticketRow.read ? "" : ", " + FoamyI18n.t("unread"))
      Accessible.description: ticketRow.expanded ? FoamyI18n.t("Collapse ticket") : FoamyI18n.t("Expand ticket")
      Accessible.onPressAction: ticketRow.toggleRequested()

      Column {
        id: body
        x: FoamyStyle.rowPadding + 6
        y: ticketRow.pad
        width: parent.width - x - FoamyStyle.rowPadding + 4
        spacing: FoamyStyle.gapSmall + 2
        Item {
          width: parent.width
          height: Math.max(subject.implicitHeight, FoamyStyle.actionSize - (ticketRow.oneLine ? 2 : 6))
          PlainText {
            id: subject
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - actions.width - FoamyStyle.gap
              - (inlineMeta.visible ? inlineMeta.implicitWidth + FoamyStyle.gap : 0))
            text: ticketRow.ticket.subject
            font.pixelSize: ticketRow.oneLine ? FoamyStyle.font.body : FoamyStyle.font.subtitle
            font.weight: ticketRow.read ? Font.Normal : Font.DemiBold
            color: ticketRow.muted ? FoamyPalette.secondaryText : FoamyPalette.text
            maximumLineCount: ticketRow.oneLine ? 1 : 2
            wrapMode: ticketRow.oneLine ? Text.NoWrap : Text.Wrap
            elide: Text.ElideRight
          }
          PlainText {
            id: inlineMeta
            visible: ticketRow.oneLine
            anchors.right: actions.left
            anchors.rightMargin: FoamyStyle.gapSmall
            anchors.verticalCenter: parent.verticalCenter
            text: ticketRow.author(ticketRow.ticket.sender, ticketRow.ticket.senderMine) + " · " + ticketRow.when(ticketRow.ticket.received)
            color: FoamyPalette.mutedText
            font.pixelSize: FoamyStyle.font.bodySmall
            wrapMode: Text.NoWrap
          }
          // Separate targets keep the actions from toggling the ticket history.
          Row {
            id: actions
            anchors.right: parent.right
            anchors.rightMargin: -FoamyStyle.gapSmall
            anchors.verticalCenter: parent.verticalCenter
            FoamyAction {
              id: readButton
              iconName: ticketRow.read ? "undo-dot" : "check"
              tooltipText: ticketRow.read ? FoamyI18n.t("Mark as unread") : FoamyI18n.t("Mark as read")
              foreground: FoamyPalette.secondaryText
              opacity: ticketRow.readActionShown ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: FoamyMotion.hover } }
              hasCursor: ticketRow.cursorPart === 1
              onHoveredChanged: if (hovered) ticketRow.hovered(1)
              onClicked: ticketRow.readToggleRequested()
            }
            FoamyAction {
              id: openButton
              iconName: "external-link"
              tooltipText: FoamyI18n.t("View in Zendesk")
              foreground: ticketRow.muted ? FoamyPalette.secondaryText : FoamyPalette.text
              hasCursor: ticketRow.cursorPart === 2
              onHoveredChanged: if (hovered) ticketRow.hovered(2)
              onClicked: ticketRow.openRequested()
            }
          }
        }
        Flow {
          visible: !ticketRow.oneLine
          width: parent.width
          spacing: FoamyStyle.gapSmall
          opacity: ticketRow.muted ? 0.6 : 1
          // Most tickets are Open and Normal: only the exceptions get a label.
          StatusLabel { id: statusPill; visible: ticketRow.ticket.status !== "Open"; text: FoamyI18n.t(ticketRow.ticket.status); tone: ticketRow.statusTone }
          StatusLabel { id: priorityPill; visible: ticketRow.ticket.priority !== "Normal"; text: FoamyI18n.t(ticketRow.ticket.priority); tone: ticketRow.priorityTone }
          PlainText {
            id: meta
            objectName: "meta"
            height: statusPill.height
            width: Math.min(implicitWidth, parent.width)
            verticalAlignment: Text.AlignVCenter
            leftPadding: statusPill.visible || priorityPill.visible ? FoamyStyle.gapSmall : 0
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            text: "#" + ticketRow.ticket.id + " · " + ticketRow.author(ticketRow.ticket.sender, ticketRow.ticket.senderMine)
            color: FoamyPalette.secondaryText
            font.pixelSize: FoamyStyle.font.bodySmall
          }
        }
        PlainText {
          id: comment
          visible: !ticketRow.expanded && !ticketRow.oneLine
          width: parent.width
          text: ticketRow.ticket.body
          color: ticketRow.muted ? FoamyPalette.mutedText : FoamyPalette.text
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Column {
          id: timeline
          visible: ticketRow.expanded
          width: parent.width
          topPadding: FoamyStyle.gapSmall
          Repeater {
            id: history
            // Build comment delegates only while the ticket is being read.
            model: ticketRow.expanded ? ticketRow.ticket.history : null
            Item {
              required property var model
              required property int index
              readonly property alias textItem: entryBody
              readonly property bool fresh: !model.mine && model.revision > ticketRow.openedSince
              visible: index < ticketRow.shownCount
              width: timeline.width
              height: visible ? entry.implicitHeight + FoamyStyle.gapLarge : 0
              Rectangle { x: 3; y: 12; width: 1; height: parent.height - 6; color: FoamyPalette.divider; visible: index < ticketRow.shownCount - 1 }
              Rectangle {
                x: 0; y: 4; width: 7; height: 7; radius: 3.5
                color: parent.fresh ? FoamyPalette.accent : FoamyPalette.background
                border.width: 1; border.color: parent.fresh ? FoamyPalette.accent : FoamyPalette.mutedText
              }
              Column {
                id: entry
                x: FoamyStyle.gapLarge + 4
                width: parent.width - x
                spacing: 2
                PlainText {
                  text: ticketRow.author(model.sender, model.mine) + "  ·  " + ticketRow.stamp(model.received)
                    + (model.internal ? "  ·  " + FoamyI18n.t("internal note") : "") + (parent.parent.fresh ? "  ·  " + FoamyI18n.t("new") : "")
                  font.pixelSize: FoamyStyle.font.bodySmall; font.weight: Font.DemiBold; color: FoamyPalette.secondaryText
                }
                PlainText {
                  id: entryBody
                  width: parent.width
                  text: model.body
                  color: ticketRow.muted ? FoamyPalette.secondaryText : FoamyPalette.text
                  maximumLineCount: ticketRow.showAll ? 100000 : 6
                  elide: Text.ElideRight
                  onTruncatedChanged: Qt.callLater(ticketRow.recountClipped)
                }
              }
              Component.onCompleted: Qt.callLater(ticketRow.recountClipped)
            }
          }
          // Earlier comments and the rest of long ones: `m` from the keyboard.
          FoamyCursorSurface {
            id: moreButton
            objectName: "moreButton"
            readonly property int hidden: ticketRow.historyCount - ticketRow.shownCount
            visible: ticketRow.expanded && !ticketRow.showAll && (hidden > 0 || ticketRow.clippedCount > 0)
            x: FoamyStyle.gapLarge + 4 - FoamyStyle.gap
            width: moreLabel.implicitWidth + FoamyStyle.gap * 2
            height: visible ? FoamyStyle.actionSize - 4 : 0
            foreground: FoamyPalette.accent
            onClicked: ticketRow.showAll = true
            Accessible.role: Accessible.Button
            Accessible.name: moreLabel.text
            Accessible.onPressAction: ticketRow.showAll = true
            PlainText {
              id: moreLabel
              anchors.centerIn: parent
              text: moreButton.hidden > 0 ? FoamyI18n.tn("Show %1 earlier comments", moreButton.hidden) : FoamyI18n.t("Show full comments")
              color: FoamyPalette.onSurface(FoamyPalette.accent)
              font.pixelSize: FoamyStyle.font.bodySmall
              font.weight: Font.DemiBold
            }
          }
        }
        // When the latest comment came, and whose ticket it is.
        PlainText {
          id: cardFooter
          objectName: "cardFooter"
          visible: !ticketRow.oneLine
          width: parent.width
          text: ticketRow.when(ticketRow.ticket.received) + "  ·  "
            + (ticketRow.ticket.mine ? FoamyI18n.t("Assigned to you")
              : ticketRow.ticket.assignee === "Unassigned" ? FoamyI18n.t("Unassigned") : FoamyI18n.t("Assigned to %1", ticketRow.ticket.assignee))
            + (ticketRow.ticket.group ? "  ·  " + ticketRow.ticket.group : "")
          color: FoamyPalette.mutedText
          font.pixelSize: FoamyStyle.font.bodySmall
          elide: Text.ElideRight
        }
      }
    }
    Item { width: 1; height: ticketRow.oneLine ? 0 : FoamyStyle.gap }
  }
}
