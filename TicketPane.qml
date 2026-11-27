pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "kit"
import "Model.js" as Model
import "Quote.js" as Quote
import "Status.js" as Status

// The Wide panel's reading pane: the selected ticket. On top its subject with
// three actions ("Mark as read"/"Mark as unread", "View in Zendesk" and "Hide
// ticket", which goes back to the overview), then the status and priority,
// the number and the requester, and at the line's end whose ticket it is;
// below, every comment the helper fetched, newest first. The comments that
// were unread when the ticket was selected sit under "New comments", the rest
// under "Earlier comments". A comment shows what its author wrote: the mail it
// quotes at its end (Quote.js) waits behind "Show quoted text", and a comment
// of more than `clipLines` lines is cut, with its own "Show more".
Item {
  id: pane
  // A row of TicketStore.tickets, or null.
  property var ticket: null
  // The ticket's read marker when it was selected (selecting marks it read):
  // a comment id, which exceeds an int.
  property double openedSince: 0
  property double now: Date.now()
  // The keyboard cursor, in on-screen order: 0 the read action, 1 View in
  // Zendesk, 2 Hide ticket, 3 the conversation (Up and Down scroll it:
  // scrollBy), -1 elsewhere.
  property int cursorPart: -1
  signal hovered(int part)
  signal readToggleRequested
  signal openRequested
  // "Hide ticket": back to the overview.
  signal closeRequested
  readonly property alias conversation: conversationList
  readonly property alias readButton: readButton
  readonly property alias wheel: conversationWheel
  readonly property alias openButton: openButton
  readonly property alias closeButton: closeButton
  readonly property alias comments: comments
  readonly property string ticketId: ticket ? ticket.id : ""
  readonly property bool read: !!ticket && ticket.read === true
  readonly property string readActionName: read ? FoamyI18n.t("Mark as unread") : FoamyI18n.t("Mark as read")
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
  readonly property bool urgent: !!ticket && ticket.priority === "Urgent"
  // The number and the requester, as a list row's line 2 starts.
  readonly property string factsLine: !ticket ? "" : ticket.requester ? "#" + ticket.id + " · " + ticket.requester : "#" + ticket.id
  // Whose ticket it is, at the end of the facts line.
  readonly property string assignmentText: !ticket ? "" : ticket.mine ? FoamyI18n.t("Assigned to you") : ticket.unassigned ? FoamyI18n.t("Unassigned") : FoamyI18n.t("Assigned to %1", [ticket.assignee || "?"])
  // A comment longer than this is cut and fades out, with "Show more".
  readonly property int clipLines: 40
  // What the reader unfolded in this ticket, by comment id: the comments shown
  // at full length and the quoted mails shown. Kept here, not in a comment's
  // delegate: the store gives a ticket a new comment list on every sync (a
  // read toggle is one), which builds the delegates again.
  property var fullComments: ({})
  property var shownQuotes: ({})
  function marked(map, revision, on) {
    var next = Object.assign({}, map)
    if (on)
      next[revision] = true
    else
      delete next[revision]
    return next
  }
  onTicketIdChanged: {
    conversationList.contentY = 0
    fullComments = ({})
    shownQuotes = ({})
  }
  // The columns lay out before the next frame; a scroll that follows a fold
  // needs the comment's new places and the new content height now.
  function settle(entry: CommentEntry) {
    entry.textColumn.forceLayout()
    entry.forceLayout()
    pane.comments.forceLayout()
  }
  // The comment `entry` (a delegate) at full length, or cut again. Cut, the
  // view moves with "Show more", so the link stays where it was pressed.
  function showFull(entry: CommentEntry, on: bool) {
    var link = entry.lengthLinkItem
    var before = link.mapToItem(conversationList.contentItem, 0, 0).y
    fullComments = marked(fullComments, entry.model.revision, on)
    if (on)
      return
    settle(entry)
    conversationWheel.scrollBy(link.mapToItem(conversationList.contentItem, 0, 0).y - before, false)
  }
  // The comment's quoted mail shown or folded away. Shown, it scrolls into view.
  function showQuote(entry: CommentEntry, on: bool) {
    shownQuotes = marked(shownQuotes, entry.model.revision, on)
    if (!on)
      return
    settle(entry)
    reveal(entry.quoteItem)
  }
  // Scrolls once so `item` shows (its top when it is taller than the view).
  // Not the wheel's ensureVisible(): that keeps following the item for a
  // moment, and a second m in that time would be pulled back to it. The
  // columns are laid out (settle) before this, so one place is enough.
  function reveal(item: Item) {
    const top = item.mapToItem(conversationList.contentItem, 0, 0).y
    const margin = conversationWheel.margin
    const view = conversationList.contentY
    if (top - margin < view || item.height + margin * 2 > conversationList.height)
      conversationWheel.scrollTo(top - margin, true)
    else if (top + item.height + margin > view + conversationList.height)
      conversationWheel.scrollTo(top + item.height + margin - conversationList.height, true)
  }
  // One step more of the conversation (`m`): the first comment from the top
  // of the view that holds something back shows it (else the first above
  // the view), first its full length, then its quoted mail. The view goes
  // to what shows. False when nothing is folded.
  function showMore() {
    var found = null
    for (let i = 0; i < history.count; i++) {
      const item = history.itemAt(i) as CommentEntry
      if (!item || !(item.clipped || (item.parts.tail !== "" && !item.quoteShown)))
        continue
      if (item.mapToItem(conversationList.contentItem, 0, item.height).y > conversationList.contentY) {
        found = item
        break
      }
      if (!found)
        found = item
    }
    if (!found)
      return false
    if (found.clipped) {
      // To where the comment is cut: the rest shows from there (a follow
      // would go with the link down to the comment's new end).
      reveal(found.lengthLinkItem)
      showFull(found, true)
    } else
      showQuote(found, true)
    return true
  }
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
  // A word's first letter or digit, whole even outside the BMP ("(Acme": A).
  // A word without one gives its first character.
  function letter(word) {
    for (const ch of word)
      if (ch.toLowerCase() !== ch.toUpperCase() || (ch >= "0" && ch <= "9"))
        return ch.toUpperCase()
    return String.fromCodePoint(word.codePointAt(0))
  }
  // A sender's initials for the avatar: the first letters of the first and the
  // last word ("Anna Lindqvist-Johansen": AL), one letter for a single word
  // or a mail address.
  function initials(name) {
    var words = String(name || "").split(/\s+/).filter(function (word) {
      return word !== ""
    })
    if (words.length === 0)
      return "?"
    if (words.length === 1 || String(name).indexOf("@") >= 0)
      return letter(words[0])
    return letter(words[0]) + letter(words[words.length - 1])
  }
  readonly property int avatarSize: FoamyStyle.actionSize - FoamyStyle.gapTiny

  // "New comments" and "Earlier comments" above the comments they head.
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
      text: divider.text
      color: divider.tone
      font.pixelSize: FoamyStyle.font.bodySmall
      font.weight: Font.DemiBold
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

  // A text link under a comment ("Show quoted text", "Show more").
  component TextLink: FoamyCursorSurface {
    id: link
    required property string text
    width: linkLabel.implicitWidth + FoamyStyle.gap * 2
    height: FoamyStyle.actionSize - FoamyStyle.gapSmall
    foreground: FoamyPalette.accent
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: link.clicked()
    // Takes the click for itself: the conversation's click-away lies under it.
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
        text: pane.ticket ? pane.ticket.subject || FoamyI18n.t("(no subject)") : ""
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
        // The action as an envelope: open for Mark as read, closed for Mark
        // as unread.
        FoamyAction {
          id: readButton
          objectName: "paneRead"
          iconName: pane.read ? "mail" : "mail-open"
          tooltipText: pane.readActionName
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
        FoamyAction {
          id: closeButton
          objectName: "paneClose"
          iconName: "x"
          tooltipText: FoamyI18n.t("Hide ticket")
          foreground: FoamyPalette.secondaryText
          hasCursor: pane.cursorPart === 2
          onHoveredChanged: if (hovered)
            pane.hovered(2)
          onClicked: pane.closeRequested()
        }
      }
    }
    // The status and the priority, the number and the requester, and whose
    // ticket it is at the line's end. The requester gives way first ("…");
    // the assignment keeps up to 40 % of the line.
    Item {
      id: facts
      objectName: "paneFacts"
      width: parent.width
      height: Math.max(tags.height, factsText.y + factsText.height)
      Row {
        id: tags
        anchors.left: parent.left
        spacing: FoamyStyle.gap
        StatusLabel {
          id: paneStatus
          objectName: "paneStatus"
          text: pane.ticket ? FoamyI18n.t(pane.ticket.status) : ""
          status: pane.ticket ? pane.ticket.status : "Open"
        }
        StatusLabel {
          objectName: "panePriority"
          visible: pane.flagged
          text: pane.ticket ? FoamyI18n.t(pane.ticket.priority) : ""
          strong: pane.urgent
          tone: pane.urgent ? FoamyPalette.error : FoamyPalette.onSurface(FoamyPalette.warning)
        }
      }
      PlainText {
        id: factsText
        objectName: "paneFactsText"
        anchors.left: tags.right
        anchors.leftMargin: FoamyStyle.gap
        anchors.right: assignment.left
        anchors.rightMargin: FoamyStyle.gap
        // On the tags' line.
        y: Math.max(0, Math.round((paneStatus.height - contentHeight) / 2))
        text: pane.factsLine
        color: FoamyPalette.secondaryText
        font.pixelSize: FoamyStyle.font.bodySmall
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
      }
      PlainText {
        id: assignment
        objectName: "paneAssignment"
        anchors.right: parent.right
        // The header's end margin is the actions' (their icons end on the
        // comments' edge); the text ends on that edge itself.
        anchors.rightMargin: FoamyStyle.padding - FoamyStyle.gapLarge
        y: factsText.y
        width: Math.min(implicitWidth, parent.width * 0.4)
        text: pane.assignmentText
        color: FoamyPalette.secondaryText
        font.pixelSize: FoamyStyle.font.bodySmall
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
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
    // The keyboard cursor on the conversation: an accent ring inside its
    // edge, in the accent's shade for the surface (it reads in a light theme too).
    Rectangle {
      objectName: "conversationCursor"
      parent: conversationList
      anchors.fill: parent
      anchors.margins: FoamyStyle.gapSmall
      visible: pane.cursorPart === 3
      color: "transparent"
      radius: FoamyStyle.radius
      border.width: 2
      border.color: FoamyPalette.onSurface(FoamyPalette.accent)
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
        delegate: CommentEntry {}
      }
      // What is left to say about the comments. Under them: newer ones that
      // haven't come yet, or earlier ones the helper left in Zendesk (it sends
      // the newest only). Without any comment this line is the pane's empty
      // state, at about 40 % of the conversation's height. The area takes that
      // height itself, so nothing here depends on the column's own size.
      Item {
        id: noteArea
        readonly property bool blank: pane.historyCount === 0
        visible: paneNote.text !== ""
        width: parent.width
        height: blank ? Math.max(paneNote.implicitHeight, conversationList.height - comments.topPadding - comments.bottomPadding) : paneNote.implicitHeight
        PlainText {
          id: paneNote
          objectName: "paneNote"
          visible: text !== ""
          width: parent.width
          y: noteArea.blank ? Math.max(0, Math.round((conversationList.height - height) * 0.4) - comments.topPadding) : 0
          horizontalAlignment: Text.AlignHCenter
          // A ticket whose comments the helper deferred isn't empty: they
          // come with the next update.
          text: pane.ticket && !pane.ticket.loaded ? (pane.historyCount === 0 ? FoamyI18n.t("Comments haven't loaded yet. They come with the next update.") : FoamyI18n.t("Newer comments haven't loaded yet. They come with the next update.")) : pane.historyCount === 0 ? FoamyI18n.t("No comments to show") : pane.historyCount >= Model.MAX_HISTORY ? FoamyI18n.t("Earlier comments are in Zendesk") : ""
          color: FoamyPalette.mutedText
          font.pixelSize: FoamyStyle.font.bodySmall
        }
      }
    }
  }
  // One comment of the conversation (the history Repeater's delegate),
  // a named type so the pane's functions can read its state.
  component CommentEntry: Column {
    id: entry
    required property var model
    required property int index
    readonly property bool fresh: index <= pane.lastFresh
    // An own reply is tinted with the accent, enough to tell it from
    // the requester's grey in a dark theme too.
    readonly property color fill: model.internal ? Qt.alpha(FoamyPalette.warning, 0.12) : model.mine ? Qt.alpha(FoamyPalette.accent, 0.18) : FoamyPalette.hoverFill
    // The fill on the popup's surface, opaque: a cut comment fades into it.
    readonly property color surface: Qt.tint(FoamyPalette.background, fill)
    // { text, tail }: what the author wrote, and the mail quoted at its end.
    readonly property var parts: Quote.split(model.body)
    readonly property bool quoteShown: pane.shownQuotes[model.revision] === true
    readonly property bool full: pane.fullComments[model.revision] === true
    readonly property bool clipped: !full && commentBody.truncated
    // Long enough to fold back once shown in full.
    readonly property bool foldable: clipped || (full && commentBody.lineCount > pane.clipLines)
    readonly property alias textColumn: bubbleText
    readonly property alias lengthLinkItem: lengthLink
    readonly property alias quoteItem: commentQuote
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
        // Anchored, so it changes sides with the bubble in a right-to-left language.
        anchors.left: parent.left
        width: pane.avatarSize
        height: width
        radius: width / 2
        color: entry.model.mine ? FoamyPalette.accent : Qt.alpha(FoamyPalette.text, 0.22)
        PlainText {
          anchors.centerIn: parent
          text: pane.initials(entry.model.sender)
          color: entry.model.mine ? Status.inkOn(FoamyPalette.accent, FoamyPalette.text, FoamyPalette.background) : FoamyPalette.text
          font.pixelSize: FoamyStyle.font.caption
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
              color: FoamyPalette.onSurface(FoamyPalette.warning, entry.surface)
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
            id: commentBody
            objectName: "commentBody"
            width: parent.width
            text: entry.parts.text
            maximumLineCount: entry.full ? 100000 : pane.clipLines
            // A cut comment fades out instead of ending in "…".
            Rectangle {
              objectName: "fade"
              visible: entry.clipped
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: Math.min(parent.height, parent.font.pixelSize * 3)
              gradient: Gradient {
                GradientStop {
                  position: 0
                  color: Qt.alpha(entry.surface, 0)
                }
                GradientStop {
                  position: 1
                  color: entry.surface
                }
              }
            }
          }
          // The links' labels start on the text's edge; their surfaces
          // reach a gap past it, and under the row's own height, so the
          // label has the same air above and below.
          Row {
            // From what the links show for, not from their `visible`: a
            // link in a hidden row reads as hidden, and the row would stay so.
            visible: entry.foldable || entry.parts.tail !== ""
            anchors.left: parent.left
            anchors.leftMargin: -FoamyStyle.gap
            bottomPadding: -FoamyStyle.gapSmall
            TextLink {
              id: lengthLink
              objectName: "lengthLink"
              visible: entry.foldable
              text: entry.full ? FoamyI18n.t("Show less") : FoamyI18n.t("Show more")
              onClicked: pane.showFull(entry, !entry.full)
            }
            // Never hidden while the quoted mail is: it is the only way to it.
            TextLink {
              id: quoteLink
              objectName: "quoteLink"
              visible: entry.parts.tail !== ""
              text: entry.quoteShown ? FoamyI18n.t("Hide quoted text") : FoamyI18n.t("Show quoted text")
              onClicked: pane.showQuote(entry, !entry.quoteShown)
            }
          }
          PlainText {
            id: commentQuote
            objectName: "commentQuote"
            visible: entry.quoteShown
            width: parent.width
            text: entry.parts.tail
            color: FoamyPalette.secondaryText
          }
        }
      }
    }
  }
}
