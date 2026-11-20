pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "kit"
import "Model.js" as Model
import "Status.js" as Status

// The Wide panel's reading pane: the selected ticket. On top its subject,
// "Mark as read"/"Mark as unread" and "View in Zendesk", and what the list
// row leaves out (requester, assignment, group); below, every comment the
// helper fetched, newest first and in full. The comments that were unread
// when the ticket was selected sit under "New", the rest under "Earlier".
Item {
  id: pane
  // A row of TicketStore.tickets, or null.
  property var ticket: null
  // The ticket's read marker when it was selected (selecting marks it read):
  // a comment id, which exceeds an int.
  property double openedSince: 0
  property double now: Date.now()
  // The keyboard cursor: 0 the read action, 1 View in Zendesk, 2 the
  // conversation (Up and Down scroll it: scrollBy), -1 elsewhere.
  property int cursorPart: -1
  signal hovered(int part)
  signal readToggleRequested
  signal openRequested
  readonly property alias conversation: conversationList
  readonly property alias readButton: readButton
  readonly property alias wheel: conversationWheel
  readonly property alias openButton: openButton
  readonly property alias comments: comments
  readonly property string ticketId: ticket ? ticket.id : ""
  readonly property bool read: !!ticket && ticket.read === true
  readonly property int historyCount: ticket && ticket.history ? ticket.history.count : 0
  // The comments unread at selection run from the top (newest) to the last
  // of them; own replies in between stay in that run.
  readonly property int lastFresh: {
    let last = -1
    for (let i = 0; i < historyCount; i++) {
      const item = ticket.history.get(i)
      if (!item.mine && item.revision > openedSince)
        last = i
    }
    return last
  }
  readonly property bool flagged: !!ticket && (ticket.priority === "Urgent" || ticket.priority === "High")
  onTicketIdChanged: conversationList.contentY = 0
  // One keyboard step (a wheel notch) up or down the conversation. False at
  // its end, so the cursor moves on instead.
  // Through the wheel helper, so a running wheel animation can't undo the step.
  function scrollBy(direction) {
    return conversationWheel.scrollBy(direction * conversationWheel.notch, false)
  }

  function format(ms, fmt) {
    return new Date(ms).toLocaleString(Qt.locale(FoamyI18n.formatLocale), fmt)
  }
  // A comment's time: 10:40 today, else the day and the time.
  function stamp(ms) {
    var days = Model.daysAgo(ms, now)
    if (days <= 0)
      return format(ms, "HH:mm")
    var day = days === 1 ? FoamyI18n.t("Yesterday") : days < 7 ? format(ms, "ddd") : format(ms, new Date(ms).getFullYear() === new Date(now).getFullYear() ? "d MMM" : "d MMM yyyy")
    return day + ", " + format(ms, "HH:mm")
  }
  // The first letter of a name, whole even outside the BMP.
  function initial(name) {
    var first = String(name || "?").codePointAt(0)
    return String.fromCodePoint(first).toUpperCase()
  }

  // "New" and "Earlier" above the comments they head.
  component Divider: Item {
    id: divider
    required property string text
    property color tone: FoamyPalette.secondaryText
    width: parent ? parent.width : 0
    height: dividerLabel.implicitHeight + FoamyStyle.gapSmall
    Rectangle {
      anchors.left: parent.left
      anchors.right: dividerLabel.left
      anchors.rightMargin: FoamyStyle.gap
      anchors.verticalCenter: parent.verticalCenter
      height: FoamyStyle.borderWidth
      color: FoamyPalette.divider
    }
    PlainText {
      id: dividerLabel
      anchors.centerIn: parent
      text: divider.text.toUpperCase()
      color: divider.tone
      font.pixelSize: FoamyStyle.font.caption
      font.weight: Font.DemiBold
      font.letterSpacing: 0.8
      wrapMode: Text.NoWrap
    }
    Rectangle {
      anchors.left: dividerLabel.right
      anchors.leftMargin: FoamyStyle.gap
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: FoamyStyle.borderWidth
      color: FoamyPalette.divider
    }
  }

  Column {
    id: header
    objectName: "paneHeader"
    visible: pane.ticket !== null
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: FoamyStyle.padding
    anchors.rightMargin: FoamyStyle.gapLarge
    topPadding: FoamyStyle.gapLarge + 2
    bottomPadding: FoamyStyle.gapLarge
    spacing: FoamyStyle.gap
    Item {
      width: parent.width
      height: Math.max(subject.implicitHeight, actions.height)
      PlainText {
        id: subject
        objectName: "paneSubject"
        anchors.left: parent.left
        anchors.right: actions.left
        anchors.rightMargin: FoamyStyle.gap
        anchors.top: parent.top
        anchors.topMargin: Math.max(0, (actions.height - font.pixelSize * 1.4) / 2)
        text: pane.ticket ? pane.ticket.subject : ""
        font.pixelSize: FoamyStyle.font.heading
        font.weight: Font.DemiBold
        maximumLineCount: 3
        elide: Text.ElideRight
        Accessible.role: Accessible.Heading
      }
      Row {
        id: actions
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: FoamyStyle.gapSmall
        FoamyAction {
          id: readButton
          objectName: "paneRead"
          iconName: pane.read ? "undo-dot" : "check"
          tooltipText: pane.read ? FoamyI18n.t("Mark as unread") : FoamyI18n.t("Mark as read")
          foreground: FoamyPalette.secondaryText
          hasCursor: pane.cursorPart === 0
          onHoveredChanged: if (hovered)
            pane.hovered(0)
          onClicked: pane.readToggleRequested()
        }
        FoamyAction {
          id: openButton
          objectName: "paneOpen"
          iconName: "external-link"
          tooltipText: FoamyI18n.t("View in Zendesk")
          hasCursor: pane.cursorPart === 1
          onHoveredChanged: if (hovered)
            pane.hovered(1)
          onClicked: pane.openRequested()
        }
      }
    }
    // What the list row leaves out.
    Flow {
      id: facts
      objectName: "paneFacts"
      width: parent.width
      spacing: FoamyStyle.gap
      StatusLabel {
        id: paneStatus
        objectName: "paneStatus"
        text: pane.ticket ? FoamyI18n.t(pane.ticket.status) : ""
        status: pane.ticket ? pane.ticket.status : "Open"
      }
      StatusLabel {
        visible: pane.flagged
        text: pane.ticket ? FoamyI18n.t(pane.ticket.priority) : ""
        tone: FoamyPalette.onSurface(pane.ticket && pane.ticket.priority === "Urgent" ? FoamyPalette.error : FoamyPalette.warning)
      }
      Repeater {
        model: pane.ticket ? ["#" + pane.ticket.id, pane.ticket.requester ? FoamyI18n.t("From %1", [pane.ticket.requester]) : "", pane.ticket.mine ? FoamyI18n.t("Assigned to you") : pane.ticket.unassigned ? FoamyI18n.t("Unassigned") : FoamyI18n.t("Assigned to %1", pane.ticket.assignee || "?"), pane.ticket.group].filter(function (part) {
          return part !== ""
        }) : []
        PlainText {
          required property string modelData
          // Names are up to 256 characters: a long one elides at the pane's width.
          width: Math.min(implicitWidth, facts.width)
          // As tall as the status tag, so the line reads as one row.
          height: paneStatus.height
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
          text: modelData
          color: FoamyPalette.secondaryText
          font.pixelSize: FoamyStyle.font.bodySmall
          wrapMode: Text.NoWrap
        }
      }
    }
  }
  Rectangle {
    id: headerEdge
    visible: header.visible
    anchors.top: header.bottom
    width: parent.width
    height: FoamyStyle.borderWidth
    color: FoamyPalette.divider
  }

  Flickable {
    id: conversationList
    objectName: "paneConversation"
    visible: header.visible
    anchors.top: headerEdge.bottom
    anchors.bottom: parent.bottom
    width: parent.width
    contentWidth: width
    contentHeight: comments.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      policy: Controls.ScrollBar.AsNeeded
    }
    FoamyWheelScroll {
      id: conversationWheel
      target: conversationList
    }
    // The keyboard cursor on the conversation: an accent ring inside its edge.
    Rectangle {
      objectName: "conversationCursor"
      parent: conversationList
      anchors.fill: parent
      anchors.margins: FoamyStyle.gapSmall
      visible: pane.cursorPart === 2
      color: "transparent"
      radius: FoamyStyle.radius
      border.width: 2
      border.color: Qt.alpha(FoamyPalette.accent, 0.6)
    }
    Column {
      id: comments
      x: FoamyStyle.padding
      width: conversationList.width - FoamyStyle.padding * 2
      topPadding: FoamyStyle.gapLarge
      bottomPadding: FoamyStyle.gapLarge
      spacing: FoamyStyle.gap + 2
      Repeater {
        id: history
        model: pane.ticket ? pane.ticket.history : null
        Column {
          id: entry
          required property var model
          required property int index
          readonly property bool fresh: index <= pane.lastFresh
          readonly property color fill: model.internal ? Qt.alpha(FoamyPalette.warning, 0.12) : model.mine ? Qt.alpha(FoamyPalette.accent, 0.10) : FoamyPalette.hoverFill
          objectName: "comment-" + model.revision
          width: comments.width
          spacing: FoamyStyle.gap + 2
          Divider {
            objectName: "newDivider"
            visible: entry.index === 0 && pane.lastFresh >= 0
            text: FoamyI18n.t("New comments")
            tone: FoamyPalette.onSurface(FoamyPalette.accent)
          }
          Divider {
            objectName: "earlierDivider"
            visible: pane.lastFresh >= 0 && entry.index === pane.lastFresh + 1
            text: FoamyI18n.t("Earlier comments")
          }
          Item {
            width: parent.width
            height: Math.max(avatar.height, bubble.height)
            Rectangle {
              id: avatar
              width: 26
              height: 26
              radius: 13
              color: entry.model.mine ? FoamyPalette.accent : Qt.alpha(FoamyPalette.text, 0.22)
              PlainText {
                anchors.centerIn: parent
                text: pane.initial(entry.model.sender)
                color: entry.model.mine ? Status.inkOn(FoamyPalette.accent, FoamyPalette.text, FoamyPalette.background) : FoamyPalette.text
                font.pixelSize: FoamyStyle.font.bodySmall
                font.weight: Font.DemiBold
                wrapMode: Text.NoWrap
              }
            }
            Rectangle {
              id: bubble
              anchors.left: avatar.right
              anchors.leftMargin: FoamyStyle.gap + 2
              anchors.right: parent.right
              height: bubbleText.implicitHeight + FoamyStyle.gap * 2
              radius: FoamyStyle.radius
              color: entry.fill
              border.width: entry.model.internal ? FoamyStyle.borderWidth : 0
              border.color: Qt.alpha(FoamyPalette.warning, 0.45)
              Column {
                id: bubbleText
                x: FoamyStyle.rowPadding
                y: FoamyStyle.gap
                width: parent.width - FoamyStyle.rowPadding * 2
                spacing: FoamyStyle.gapSmall
                Row {
                  id: byline
                  width: parent.width
                  spacing: FoamyStyle.gap
                  // A long name elides first; the label and the time stay whole.
                  PlainText {
                    width: Math.min(implicitWidth, byline.width - (noteLabel.visible ? noteLabel.width + byline.spacing : 0) - timeLabel.width - byline.spacing)
                    elide: Text.ElideRight
                    text: entry.model.mine ? FoamyI18n.t("You") : entry.model.sender
                    font.pixelSize: FoamyStyle.font.bodySmall
                    font.weight: Font.DemiBold
                    wrapMode: Text.NoWrap
                  }
                  PlainText {
                    id: noteLabel
                    visible: entry.model.internal
                    text: FoamyI18n.t("Internal note")
                    color: FoamyPalette.onSurface(FoamyPalette.warning)
                    font.pixelSize: FoamyStyle.font.bodySmall
                    font.weight: Font.DemiBold
                    wrapMode: Text.NoWrap
                  }
                  PlainText {
                    id: timeLabel
                    text: pane.stamp(entry.model.received)
                    color: FoamyPalette.secondaryText
                    font.pixelSize: FoamyStyle.font.bodySmall
                    wrapMode: Text.NoWrap
                  }
                }
                PlainText {
                  objectName: "commentBody"
                  width: parent.width
                  text: entry.model.body
                }
              }
            }
          }
        }
      }
      // The helper sends the newest comments only; older ones are in Zendesk.
      PlainText {
        objectName: "paneNote"
        visible: text !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        // A ticket whose comments the helper deferred isn't empty: they come
        // with an update, which waits while a ticket is shown.
        text: pane.ticket && !pane.ticket.loaded ? (pane.historyCount === 0 ? FoamyI18n.t("Comments haven't loaded yet. Close the ticket to get them with the next update.") : FoamyI18n.t("Newer comments haven't loaded yet. Close the ticket to get them with the next update.")) : pane.historyCount === 0 ? FoamyI18n.t("No comments to show") : pane.historyCount >= Model.MAX_HISTORY ? FoamyI18n.t("Earlier comments are in Zendesk") : ""
        color: FoamyPalette.mutedText
        font.pixelSize: FoamyStyle.font.bodySmall
      }
    }
  }
}
