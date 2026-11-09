import QtQuick
import "kit"
import "Model.js" as Model

// One ticket. Closed: a disclosure triangle, the subject, an unread dot and
// the time, status pills, the latest comment and the assignment; the whole
// card opens it. Open: a framed card whose tinted header band is the only
// part that closes it, with the comments newest first: those unread when it
// was opened (opening marks it read) and the one before them, the rest behind
// "Show earlier". Long comments are clipped and fade out, each with its own
// "Show more" / "Show less"; nothing expands them all.
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
  readonly property alias frameItem: frame
  readonly property alias unreadDot: unreadDot
  readonly property alias commentItem: comment
  readonly property alias detailsItem: timeline
  readonly property alias historyRepeater: history
  readonly property alias openButton: openButton
  readonly property alias readButton: readButton
  readonly property alias sectionHeader: sectionHeader
  readonly property alias moreButton: moreButton
  // The clock for "Yesterday", weekdays and dates.
  property double now: Date.now()
  // The earlier comments are listed too (each still clipped).
  property bool showEarlier: false
  // What was unread when the ticket opened: opening marks it read, but the
  // timeline keeps showing those comments as new until it closes.
  property int openedSince: 0
  property int openedUpdates: 0
  onExpandedChanged: {
    if (expanded) { openedSince = ticket.since; openedUpdates = ticket.updates; }
    else showEarlier = false;
  }
  readonly property int historyCount: ticket.history ? ticket.history.count : 0
  readonly property int shownCount: showEarlier ? historyCount : Math.min(historyCount, Math.max(openedUpdates + 1, 2))
  // One step more of the open ticket (`m`): the newest clipped comment shown in
  // full, else the earlier comments. False when there's nothing more.
  function showMore() {
    for (var i = 0; i < shownCount; i++) {
      var item = history.itemAt(i);
      if (item && item.clipped) { item.full = true; return true; }
    }
    if (shownCount < historyCount) { showEarlier = true; return true; }
    return false;
  }
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
  // Where the subject, meta, comments and footer start: right of the
  // disclosure triangle.
  readonly property int indent: FoamyStyle.gapLarge + 8
  // A comment longer than this is clipped, with its own "Show more".
  readonly property int clipLines: 6
  // The open card, opaque so clipped comments can fade into it.
  readonly property color cardColor: Qt.tint(FoamyPalette.background, FoamyPalette.noteFill)
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
  // A text link in the open ticket ("Show full comment", "Show earlier").
  component MoreLink: FoamyCursorSurface {
    id: link
    required property string text
    width: linkLabel.implicitWidth + FoamyStyle.gap * 2
    height: visible ? FoamyStyle.actionSize - 4 : 0
    foreground: FoamyPalette.accent
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: link.clicked()
    // The card's own tap would also fire (and collapse the ticket): this
    // takes the click for itself, like the card's actions.
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: link.clicked()
    }
    PlainText {
      id: linkLabel
      anchors.centerIn: parent
      text: link.text
      color: FoamyPalette.onSurface(FoamyPalette.accent)
      font.pixelSize: FoamyStyle.font.bodySmall
      font.weight: Font.DemiBold
    }
  }
  Column {
    id: column
    width: parent.width
    Item {
      id: sectionHeader
      visible: ticketRow.sectionTitle.length > 0
      width: parent.width
      height: FoamyStyle.rowHeight - FoamyStyle.gapSmall
      // The count is its own text a full gap after the title, so it never
      // runs into the title, whatever the font or language.
      Row {
        id: sectionLabel
        x: FoamyStyle.rowPadding - 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: FoamyStyle.gap
        Accessible.role: Accessible.Heading
        Accessible.name: ticketRow.sectionTitle + " " + FoamyI18n.number(ticketRow.sectionCount)
        PlainText {
          text: ticketRow.sectionTitle.toUpperCase()
          color: FoamyPalette.mutedText
          font.pixelSize: FoamyStyle.font.caption
          font.weight: Font.DemiBold
          font.letterSpacing: 0.8
          wrapMode: Text.NoWrap
        }
        PlainText {
          objectName: "sectionCount"
          text: FoamyI18n.number(ticketRow.sectionCount)
          color: FoamyPalette.text
          font.pixelSize: FoamyStyle.font.caption
          font.weight: Font.DemiBold
          wrapMode: Text.NoWrap
        }
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
    // Closed, the whole card opens the ticket. Open, the card gets a frame and
    // only its tinted header band closes it: clicks on the comments, their
    // links and the footer never collapse it.
    Item {
      id: card
      width: parent.width
      height: rest.y + rest.implicitHeight + ticketRow.pad
      Rectangle {
        id: frame
        anchors.fill: parent
        visible: ticketRow.expanded
        radius: FoamyStyle.radius
        color: ticketRow.cardColor
        border.width: FoamyStyle.borderWidth
        border.color: FoamyPalette.border
      }
      FoamyCursorSurface {
        id: bodySurface
        readonly property real inset: ticketRow.expanded ? FoamyStyle.borderWidth : 0
        x: inset; y: inset
        width: card.width - inset * 2
        height: ticketRow.expanded ? head.height + ticketRow.pad * 2 - inset : card.height
        radius: ticketRow.expanded ? FoamyStyle.bandRadius : FoamyStyle.radius
        bottomLeftRadius: ticketRow.expanded ? 0 : radius
        bottomRightRadius: ticketRow.expanded ? 0 : radius
        color: ticketRow.expanded ? (hasCursor ? Qt.tint(FoamyPalette.bandFill, fill) : FoamyPalette.bandFill)
          : (hasCursor ? fill : "transparent")
        foreground: FoamyPalette.text
        hasCursor: ticketRow.cursorPart === 0
        onHovered: ticketRow.hovered(0)
        onClicked: ticketRow.toggleRequested()
        HoverHandler { id: rowHover }
        Accessible.role: Accessible.Button
        Accessible.name: ticketRow.ticket.subject + (ticketRow.read ? "" : ", " + FoamyI18n.t("unread"))
        Accessible.description: ticketRow.expanded ? FoamyI18n.t("Collapse ticket") : FoamyI18n.t("Expand ticket")
        Accessible.onPressAction: ticketRow.toggleRequested()
      }

      // The header: what the band covers once the ticket is open.
      Column {
        id: head
        x: FoamyStyle.rowPadding
        y: ticketRow.pad
        width: parent.width - x - FoamyStyle.rowPadding + 4
        spacing: FoamyStyle.gapSmall
        Item {
          width: parent.width
          height: Math.max(subject.implicitHeight, FoamyStyle.actionSize - (ticketRow.oneLine ? 2 : 6))
          // Points right while closed, down while open.
          FoamyIcon {
            id: disclosure
            objectName: "disclosure"
            anchors.verticalCenter: parent.verticalCenter
            name: ticketRow.expanded ? "chevron-down" : "chevron-right"
            color: ticketRow.expanded ? FoamyPalette.secondaryText : FoamyPalette.mutedText
            width: 14; height: width
          }
          PlainText {
            id: subject
            x: ticketRow.indent
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, (whenLabel.visible ? unreadDot.x - (unreadDot.visible ? FoamyStyle.gapSmall : 0) : actions.x) - x - FoamyStyle.gap)
            text: ticketRow.ticket.subject
            font.pixelSize: ticketRow.oneLine ? FoamyStyle.font.body : FoamyStyle.font.subtitle
            font.weight: ticketRow.read ? Font.Normal : Font.DemiBold
            color: ticketRow.muted ? FoamyPalette.secondaryText : FoamyPalette.text
            maximumLineCount: ticketRow.oneLine ? 1 : 2
            wrapMode: ticketRow.oneLine ? Text.NoWrap : Text.Wrap
            elide: Text.ElideRight
          }
          // Unread, without a rail: a dot by the time.
          Rectangle {
            id: unreadDot
            objectName: "unreadDot"
            visible: !ticketRow.read && !ticketRow.expanded
            x: whenLabel.x - (visible ? width + FoamyStyle.gapSmall : 0)
            anchors.verticalCenter: parent.verticalCenter
            width: 7; height: 7; radius: 3.5
            color: FoamyPalette.accent
          }
          // Closed, the time sits on the subject line (with the sender on a
          // one-line read ticket); open, it's in the footer.
          PlainText {
            id: whenLabel
            objectName: "when"
            visible: !ticketRow.expanded
            anchors.right: actions.left
            anchors.rightMargin: FoamyStyle.gapSmall
            anchors.verticalCenter: parent.verticalCenter
            text: (ticketRow.oneLine ? ticketRow.author(ticketRow.ticket.sender, ticketRow.ticket.senderMine) + " · " : "")
              + ticketRow.when(ticketRow.ticket.received)
            color: FoamyPalette.mutedText
            font.pixelSize: FoamyStyle.font.bodySmall
            wrapMode: Text.NoWrap
          }
          // Separate targets keep the actions from toggling the ticket.
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
          x: ticketRow.indent
          width: parent.width - x
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
      }

      // Below the header: the latest comment (closed) or the timeline (open),
      // then the footer.
      Column {
        id: rest
        x: head.x
        y: head.y + head.height + (ticketRow.expanded ? ticketRow.pad * 2 : (ticketRow.oneLine ? 0 : head.spacing + 2))
        width: head.width
        spacing: FoamyStyle.gapSmall + 2
        PlainText {
          id: comment
          visible: !ticketRow.expanded && !ticketRow.oneLine
          x: ticketRow.indent
          width: parent.width - x
          text: ticketRow.ticket.body
          color: ticketRow.muted ? FoamyPalette.mutedText : FoamyPalette.text
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Column {
          id: timeline
          visible: ticketRow.expanded
          // The comment dots line up under the disclosure triangle.
          x: 4
          width: parent.width - x
          Repeater {
            id: history
            // Build comment delegates only while the ticket is being read.
            model: ticketRow.expanded ? ticketRow.ticket.history : null
            Item {
              id: entryItem
              required property var model
              required property int index
              readonly property alias textItem: entryBody
              readonly property alias lengthButton: lengthButton
              readonly property bool fresh: !model.mine && model.revision > ticketRow.openedSince
              // This comment at full length; the others stay clipped.
              property bool full: false
              readonly property bool clipped: !full && entryBody.truncated
              // Long enough to fold back once shown in full.
              readonly property bool foldable: clipped || (full && entryBody.lineCount > ticketRow.clipLines)
              visible: index < ticketRow.shownCount
              width: timeline.width
              height: visible ? entry.implicitHeight + FoamyStyle.gapLarge : 0
              Rectangle { x: 3; y: 12; width: 1; height: parent.height - 6; color: FoamyPalette.divider; visible: index < ticketRow.shownCount - 1 }
              Rectangle {
                x: 0; y: 4; width: 7; height: 7; radius: 3.5
                color: entryItem.fresh ? FoamyPalette.accent : ticketRow.cardColor
                border.width: 1; border.color: entryItem.fresh ? FoamyPalette.accent : FoamyPalette.mutedText
              }
              Column {
                id: entry
                x: ticketRow.indent - timeline.x
                width: parent.width - x
                spacing: 2
                PlainText {
                  text: ticketRow.author(model.sender, model.mine) + "  ·  " + ticketRow.stamp(model.received)
                    + (model.internal ? "  ·  " + FoamyI18n.t("internal note") : "") + (entryItem.fresh ? "  ·  " + FoamyI18n.t("new") : "")
                  font.pixelSize: FoamyStyle.font.bodySmall; font.weight: Font.DemiBold; color: FoamyPalette.secondaryText
                }
                PlainText {
                  id: entryBody
                  width: parent.width
                  text: model.body
                  color: FoamyPalette.text
                  maximumLineCount: entryItem.full ? 100000 : ticketRow.clipLines
                  // Clipped text fades out instead of ending in "…".
                  Rectangle {
                    objectName: "fade"
                    visible: entryItem.clipped
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.min(parent.height, parent.font.pixelSize * 3)
                    gradient: Gradient {
                      GradientStop { position: 0; color: Qt.alpha(ticketRow.cardColor, 0) }
                      GradientStop { position: 1; color: ticketRow.cardColor }
                    }
                  }
                }
                MoreLink {
                  id: lengthButton
                  objectName: "lengthButton"
                  visible: entryItem.foldable
                  x: -FoamyStyle.gap
                  text: entryItem.full ? FoamyI18n.t("Show less") : FoamyI18n.t("Show more")
                  onClicked: entryItem.full = !entryItem.full
                }
              }
            }
          }
          // The earlier comments (still clipped): `m` from the keyboard.
          MoreLink {
            id: moreButton
            objectName: "moreButton"
            readonly property int hidden: ticketRow.historyCount - ticketRow.shownCount
            visible: ticketRow.expanded && hidden > 0
            x: ticketRow.indent - timeline.x - FoamyStyle.gap
            text: FoamyI18n.tn("Show %1 earlier comments", hidden)
            onClicked: ticketRow.showEarlier = true
          }
        }
        // Whose ticket it is, and (open) when the latest comment came.
        PlainText {
          id: cardFooter
          objectName: "cardFooter"
          visible: !ticketRow.oneLine
          x: ticketRow.indent
          width: parent.width - x
          text: (ticketRow.expanded ? ticketRow.when(ticketRow.ticket.received) + "  ·  " : "")
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
