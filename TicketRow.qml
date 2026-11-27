pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons
import "kit"
import "Model.js" as Model
import "Status.js" as Status
import "TicketText.js" as TicketText

// One ticket. A closed ticket has one of three looks:
//  - unread (also a ticket that was never seen and whose comments haven't
//    loaded): the full row. Line 1 is a disclosure triangle in the status
//    colour, the subject (two lines at most), the unread dot and the time,
//    then Mark as read and View in Zendesk. Line 2 is the status tag, the
//    priority (High and Urgent only) and "#number · requester". Then
//    the start of the newest comment (TicketText.previewText);
//  - read, and waiting for the agent (New or Open, the newest comment not the
//    agent's): one line in the normal text tones;
//  - read and parked (the agent wrote last, or Pending or On-hold): one line,
//    dimmed.
// A one-line row is the triangle, the subject, the status tag (unless Open),
// the priority, the requester and the time; Mark as unread shows in its slot
// on hover or under the keyboard cursor. When room runs out the requester
// goes first, then the status tag, then the subject is cut. The time ends at
// the same place on every row, and the two actions have fixed slots after it.
// The whole card opens the ticket. Open: a framed card. Its tinted header
// band has the subject in full (five lines at most, DemiBold: it is the
// ticket being read), line 2 with the solid status tag and whose ticket it
// is at its end, and both actions at rest; a click on the band closes the card. Under it the comments, newest
// first: those unread when it was opened (opening marks it read) and the one
// before them, the rest behind "Show earlier". Each starts with a byline (the
// writer, "Internal note", the time, "New"); an internal note lies on a
// tinted surface, so it is never taken for a reply the requester got. Long
// comments are clipped and fade out, each with its own "Show more" / "Show
// less" (the newest unread one shows twice as much); nothing expands them
// all. Where the comments would be, a line says when there are none to show
// or when the newest haven't loaded. The card ends with a footer row with
// "Collapse", so a long ticket closes where the reading ends. While the card is taller than
// the list's view, its band stays at the top of the view (`pin`).
// `compact` (read tickets) asks for the one-line row; expanding a compact
// ticket shows it in full.
// `wide` (the Wide panel's list): never expands and has no triangle, actions
// or comment. Line 1 is the subject (two lines at most while unread, else
// one) with the unread dot and the time; line 2 is as in the full row. The
// ticket being read is `selected` and shows in the reading pane (TicketPane).
Item {
  id: ticketRow
  property var ticket
  property bool expanded: false
  property bool compact: false
  property bool wide: false
  property bool selected: false
  // Shown above this ticket when it starts a section, e.g. "Waiting on others".
  property string sectionTitle: ""
  property int sectionCount: 0
  property int cursorPart: -1
  // The keys moved the cursor here: its accent border (FoamyCursor.byKeys).
  property bool byKeys: false
  signal hovered(int part)
  signal toggleRequested
  signal openRequested
  signal readToggleRequested
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
  // timeline keeps showing those comments as new until it closes. A comment
  // id: Zendesk's exceed an int.
  property double openedSince: 0
  property int openedUpdates: 0
  // The comments shown in full ({ comment id: true }), until the ticket
  // closes. Kept here, not in the comment's delegate: every change to the
  // list (marking the ticket unread, Mark all as read) builds the delegates
  // again, and what was unfolded would fold back under the reader. Read when
  // a delegate is built; changed in place, so nothing else is evaluated again.
  property var unfolded: ({})
  onExpandedChanged: {
    if (expanded) {
      openedSince = ticket.since
      openedUpdates = ticket.updates
    } else {
      showEarlier = false
      unfolded = ({})
    }
  }
  readonly property int historyCount: ticket.history ? ticket.history.count : 0
  readonly property int shownCount: showEarlier ? historyCount : Math.min(historyCount, Math.max(openedUpdates + 1, 2))
  // One step more of the open ticket (`m`): the newest clipped comment shown in
  // full, else the earlier comments. False when there's nothing more.
  function showMore() {
    for (var i = 0; i < shownCount; i++) {
      var item = history.itemAt(i)
      if (item && item.clipped) {
        item.full = true
        return true
      }
    }
    if (shownCount < historyCount) {
      showEarlier = true
      return true
    }
    return false
  }
  readonly property bool read: ticket.read === true
  // Never seen, and its comments haven't come (the helper loads 25 tickets'
  // comments per run): nothing in it counts as unread yet, but it is as new
  // to the agent as an unread ticket and is drawn like one.
  readonly property bool unseen: ticket.unseen === true
  readonly property bool showsUnread: !read || unseen
  // The next step is the agent's, as in Model.overview: New or Open, and the
  // newest comment is someone else's (unknown while the comments haven't
  // loaded: such a ticket may be waiting, so it isn't dimmed either).
  readonly property bool awaitingReply: Model.AWAITING_STATUSES.indexOf(ticket.status) >= 0 && (ticket.loaded === false || ticket.senderMine !== true)
  // Read and parked (the agent wrote last, or Pending, On-hold or solved):
  // these are dimmed, except the one being read.
  readonly property bool muted: !showsUnread && !awaitingReply && !expanded && !selected
  readonly property bool oneLine: compact && !unseen && !expanded && !wide
  // The pointer is over the ticket (its actions included).
  readonly property bool pointerOver: rowHover.hovered || readButton.hovered || openButton.hovered
  // A read ticket can be marked unread when someone else wrote in it, or
  // when its comments haven't loaded (Model.markUnread then drops its
  // marker, so it is unseen again). One sent without comments, or with the
  // agent's own only, has nothing to mark: no toggle. Worked out for read
  // tickets only; the first comment from someone else ends the search.
  readonly property bool othersWrote: {
    if (!read || ticket.loaded === false)
      return true
    for (let i = 0; i < historyCount; i++)
      if (ticket.history.get(i).mine !== true)
        return true
    return false
  }
  // "Mark as unread" is an undo: on a closed row it shows only on hover or
  // under the keyboard cursor, and keeps its slot so nothing shifts when it
  // appears. The open card shows it at rest: opening marked the ticket read,
  // and this is where that is taken back.
  readonly property bool readActionShown: othersWrote && (!read || expanded || pointerOver || cursorPart === 1)
  // Wide rows and one-line rows are tight; the full row has the kit's row padding.
  readonly property int pad: oneLine || wide ? FoamyStyle.gapSmall + FoamyStyle.gapTiny : FoamyStyle.rowPadding
  readonly property int unread: read ? 0 : ticket.updates
  // Where the subject, line 2, the comments and the footer start: right of
  // the disclosure triangle. Wide has no triangle.
  readonly property int indent: wide ? 0 : FoamyStyle.gapLarge + FoamyStyle.gap
  // A comment longer than this is clipped, with its own "Show more". The one
  // the ticket was opened for (the newest that was unread) shows twice as much.
  readonly property int clipLines: 6
  readonly property int clipLinesNewest: clipLines * 2
  // The newest comment that was unread when the ticket opened (-1: none).
  readonly property int newestUnreadIndex: {
    if (!expanded)
      return -1
    for (let i = 0; i < historyCount; i++) {
      const item = ticket.history.get(i)
      if (!item.mine && item.revision > openedSince)
        return i
    }
    return -1
  }
  // The open card, opaque so clipped comments can fade into it.
  readonly property color cardColor: Qt.tint(FoamyPalette.background, FoamyPalette.noteFill)
  // An internal note lies on this tint (on the card's colour), with this
  // much of it around the text.
  readonly property color noteTint: Qt.alpha(FoamyPalette.warning, 0.10)
  readonly property int notePad: FoamyStyle.gapSmall + FoamyStyle.gapTiny
  // What the open card says where its comments would be, or above comments
  // that may not be the newest ("" when the comments are all there).
  readonly property string timelineNotice: {
    if (!expanded)
      return ""
    if (ticket.loaded === false)
      return historyCount === 0 ? FoamyI18n.t("Comments haven't loaded yet. They come with the next update.") : FoamyI18n.t("Newer comments haven't loaded yet. They come with the next update.")
    return historyCount === 0 ? FoamyI18n.t("No comments to show") : ""
  }
  // Only High and Urgent get a priority label; Low and Normal get none.
  readonly property bool flagged: ticket.priority === "Urgent" || ticket.priority === "High"
  // The priority steps forward: Urgent is a solid pill on the rows that need
  // the agent and in the open card (as in the Wide pane's header). A dimmed
  // row keeps the soft one.
  readonly property bool urgentPill: ticket.priority === "Urgent" && !muted
  // The strongest fill the header shows (under the cursor), opaque: the
  // triangle, a soft tag and a priority pill on it are measured there, so
  // they keep one colour.
  readonly property color headSurface: expanded ? Qt.tint(FoamyPalette.bandFill, bodySurface.fill) : selected ? Qt.tint(FoamyPalette.background, Qt.tint(FoamyPalette.selectedFill, bodySurface.fill)) : Qt.tint(FoamyPalette.background, bodySurface.fill)
  readonly property color priorityTone: urgentPill ? FoamyPalette.error : FoamyPalette.onSurface(ticket.priority === "Urgent" ? FoamyPalette.error : FoamyPalette.warning)
  // Zendesk's colour for a status, in this theme's mode (Status.js).
  function statusColorOf(status) {
    return Status.color(status, FoamyPalette.lightTheme)
  }
  readonly property color statusColor: statusColorOf(ticket.status)
  // Who the ticket is from: always the requester, never whoever wrote last
  // (`sender`).
  readonly property string requester: ticket.requester || ""
  // Line 2's parts: the number and the requester. The section header says
  // whose ticket it is: a closed row names an assignee only when it is
  // neither the agent nor nobody; the open card says it at the line's end
  // (`assignmentText`), as the Wide pane does.
  readonly property var metaParts: {
    var parts = ["#" + ticket.id]
    if (requester !== "")
      parts.push(requester)
    if (!expanded && ticket.mine !== true && ticket.unassigned !== true && ticket.assignee)
      parts.push(FoamyI18n.t("Assigned to %1", ticket.assignee))
    return parts
  }
  readonly property string metaText: metaParts.join(" · ")
  readonly property string assignmentText: ticket.mine ? FoamyI18n.t("Assigned to you") : ticket.unassigned ? FoamyI18n.t("Unassigned") : FoamyI18n.t("Assigned to %1", ticket.assignee || "?")
  // Line 2's parts joined so that none ends in a stub: whole parts go from
  // the end; the name is cut ("…") only while 8 letters of it still show.
  function fittedMeta(parts, room, metrics) {
    for (let count = parts.length; count > 1; count--) {
      const text = parts.slice(0, count).join(" · ")
      if (metrics.advanceWidth(text) <= room + 1)
        return text
    }
    if (parts.length > 1 && metrics.advanceWidth(parts[0] + " · " + parts[1].slice(0, 8) + "…") <= room + 1)
      return parts[0] + " · " + parts[1]
    return parts[0]
  }
  // No comment to show yet: the full row says so in its place.
  readonly property bool previewIsNote: ticket.loaded === false && historyCount === 0
  // The newest comment as the full row shows it ("" on the rows that don't
  // show it: they don't work it out). It names its writer when that is the
  // agent, or a colleague in an internal note (the writer, then "Internal
  // note", as the open card's byline has them); else it is the requester's
  // or a public reply, as the row's name and time suggest.
  readonly property string previewLine: {
    if (oneLine || wide)
      return ""
    if (previewIsNote)
      return FoamyI18n.t("Comments haven't loaded yet")
    var text = TicketText.previewText(ticket.body)
    if (text === "")
      return ""
    var newest = historyCount > 0 ? ticket.history.get(0) : null
    var internal = newest !== null && newest.internal === true
    if (ticket.senderMine !== true && !internal)
      return text
    return author(ticket.sender, ticket.senderMine === true) + (internal ? " · " + FoamyI18n.t("Internal note") : "") + ": " + text
  }
  // A long open ticket keeps its header in view: while the card is taller
  // than the list's view, the band stays at the top of the view. `pin` is how
  // far down the card the band is moved for that (0: where it is laid out).
  // It stops on the footer row's hairline, so the band never leaves the card
  // or covers its end. Whole pixels, rounded down: the band's text stays
  // sharp and no sliver of a comment shows above it while the list glides.
  // Only the open row reads the list's position, so only it follows the scroll.
  readonly property real pin: {
    if (!expanded)
      return 0
    const list = scroller()
    if (!list || card.height <= list.height)
      return 0
    let top = bodySurface.inset
    for (let part = card; part && part !== list.contentItem; part = part.parent)
      top += part.y
    const room = rest.y + footerRow.y + FoamyStyle.borderWidth - bodySurface.inset - bodySurface.height
    return Math.max(0, Math.min(Math.floor(list.contentY - top), room))
  }
  readonly property bool pinned: pin > 0
  // The list the row scrolls in: the Flickable among its parents, or null.
  function scroller(): Flickable {
    for (let item = ticketRow.parent; item; item = item.parent) {
      const list = item as Flickable
      if (list)
        return list
    }
    return null
  }
  // The open card is the only place Small shows the subject in full: five
  // lines hold any real one. Closed, two at most.
  // Wide: the subject may take two lines while the ticket is unread, and
  // keeps them while it is being read, so selecting it moves no row.
  readonly property int subjectLines: oneLine ? 1 : expanded ? 5 : !wide || showsUnread || (selected && ticket.placedRead === false) ? 2 : 1
  function format(ms, fmt) {
    return new Date(ms).toLocaleString(Qt.locale(FoamyI18n.formatLocale), fmt)
  }
  // A row's time: 10:40 today, then Yesterday, a weekday, 28 Oct, 28 Oct 2025.
  function when(ms) {
    var days = Model.daysAgo(ms, now)
    if (days <= 0)
      return format(ms, "HH:mm")
    if (days === 1)
      return FoamyI18n.t("Yesterday")
    if (days < 7)
      return format(ms, "ddd")
    return format(ms, new Date(ms).getFullYear() === new Date(now).getFullYear() ? "d MMM" : "d MMM yyyy")
  }
  // A comment's time: the row's day (today is left out) and the time.
  function stamp(ms) {
    var days = Model.daysAgo(ms, now)
    return days <= 0 ? format(ms, "HH:mm") : when(ms) + ", " + format(ms, "HH:mm")
  }
  function author(name, mine) {
    return mine ? FoamyI18n.t("You") : name
  }
  implicitHeight: column.implicitHeight
  height: implicitHeight

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
    // The section's name as written, and how many tickets it has at the
    // trailing edge, as the sibling plugins' lists do.
    Item {
      id: sectionHeader
      visible: ticketRow.sectionTitle.length > 0
      width: parent.width
      height: FoamyStyle.rowHeight - FoamyStyle.gapSmall
      Accessible.role: Accessible.Heading
      Accessible.name: ticketRow.sectionTitle + " " + FoamyI18n.number(ticketRow.sectionCount)
      // Starts where a row's content does; the count ends where it ends.
      PlainText {
        id: sectionLabel
        objectName: "sectionTitle"
        anchors.left: parent.left
        anchors.leftMargin: FoamyStyle.rowPadding
        anchors.right: sectionTotal.left
        anchors.rightMargin: FoamyStyle.gap
        anchors.bottom: parent.bottom
        anchors.bottomMargin: FoamyStyle.gapSmall
        text: ticketRow.sectionTitle
        color: FoamyPalette.secondaryText
        font.pixelSize: FoamyStyle.font.bodySmall
        font.weight: Font.DemiBold
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
      }
      PlainText {
        id: sectionTotal
        objectName: "sectionCount"
        anchors.right: parent.right
        anchors.rightMargin: FoamyStyle.rowPadding
        anchors.baseline: sectionLabel.baseline
        text: FoamyI18n.number(ticketRow.sectionCount)
        color: FoamyPalette.mutedText
        font.family: FoamyStyle.monoFamily
        font.pixelSize: FoamyStyle.font.caption
        wrapMode: Text.NoWrap
      }
    }
    // Closed, the whole card opens the ticket. Open, the card gets a frame;
    // its tinted header band closes it, and so does "Collapse" in its footer
    // row. Clicks on the comments, their links and the footer's text never do.
    Item {
      id: card
      width: parent.width
      height: rest.y + rest.implicitHeight + ticketRow.pad
      Rectangle {
        id: frame
        objectName: "frame"
        anchors.fill: parent
        visible: ticketRow.expanded
        radius: FoamyStyle.radius
        color: ticketRow.cardColor
        border.width: FoamyStyle.borderWidth
        border.color: FoamyPalette.border
      }
      // Pinned, the band lies over the comments that pass under it: this
      // takes the press there, so a click on the band never also reaches a
      // link below it. (The band's own tap only watches the press.)
      MouseArea {
        objectName: "bandShield"
        anchors.fill: bodySurface
        z: bodySurface.z
        visible: ticketRow.pinned
      }
      FoamyCursorSurface {
        id: bodySurface
        readonly property real inset: ticketRow.expanded ? FoamyStyle.borderWidth : 0
        x: inset
        y: inset + ticketRow.pin
        // Open, the band and the header are above the comments (see `pin`).
        z: ticketRow.expanded ? 1 : 0
        width: card.width - inset * 2
        height: ticketRow.expanded ? head.height + ticketRow.pad * 2 - inset : card.height
        radius: ticketRow.expanded ? FoamyStyle.bandRadius : FoamyStyle.radius
        // Pinned, its top is the view's edge: square. On the way there the
        // corners shrink with the frame's, which are leaving the view.
        topLeftRadius: Math.max(0, radius - ticketRow.pin)
        topRightRadius: topLeftRadius
        bottomLeftRadius: ticketRow.expanded ? 0 : radius
        bottomRightRadius: ticketRow.expanded ? 0 : radius
        color: ticketRow.expanded ? (hasCursor ? Qt.tint(FoamyPalette.bandFill, fill) : FoamyPalette.bandFill) : ticketRow.selected ? (hasCursor ? Qt.tint(FoamyPalette.selectedFill, fill) : FoamyPalette.selectedFill) : (hasCursor ? fill : "transparent")
        foreground: FoamyPalette.text
        hasCursor: ticketRow.cursorPart === 0
        byKeys: ticketRow.byKeys
        onHovered: ticketRow.hovered(0)
        onClicked: ticketRow.toggleRequested()
        HoverHandler {
          id: rowHover
        }
        // Pinned: a hairline into the comments that pass under the band.
        Rectangle {
          visible: ticketRow.pinned
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: FoamyStyle.borderWidth
          color: FoamyPalette.divider
        }
        Accessible.role: Accessible.Button
        // A one-line Open ticket shows its status only by colour: name it here.
        Accessible.name: (ticketRow.ticket.subject || FoamyI18n.t("(no subject)")) + ", " + FoamyI18n.t(ticketRow.ticket.status) + (ticketRow.flagged ? ", " + FoamyI18n.t(ticketRow.ticket.priority) : "") + (ticketRow.showsUnread ? ", " + FoamyI18n.t("unread") : "")
        Accessible.description: ticketRow.wide ? (ticketRow.selected ? FoamyI18n.t("Hide ticket") : FoamyI18n.t("Show ticket")) : ticketRow.expanded ? FoamyI18n.t("Collapse ticket") : FoamyI18n.t("Expand ticket")
        Accessible.onPressAction: ticketRow.toggleRequested()
      }

      // The header: what the band covers once the ticket is open.
      Column {
        id: head
        anchors.left: parent.left
        anchors.leftMargin: FoamyStyle.rowPadding
        anchors.right: parent.right
        anchors.rightMargin: FoamyStyle.rowPadding
        y: ticketRow.pad + ticketRow.pin
        z: bodySurface.z
        spacing: FoamyStyle.gapSmall
        // Everything is placed with anchors and rows, so a right-to-left
        // language mirrors it. From the end: View in Zendesk and the read
        // toggle in fixed slots, the time (with the unread dot before it), and
        // on a one-line row the requester and the tags. The subject takes
        // what is left.
        Item {
          id: titleLine
          // One-line rows are as tall as their actions; else the line is the subject's.
          readonly property real strip: ticketRow.oneLine ? FoamyStyle.actionSize - FoamyStyle.gapTiny : 0
          // From this line's end to the time's: the two action slots, which
          // hang into the row's padding so their icons end where the text does.
          readonly property real endInset: ticketRow.wide ? 0 : openButton.width + readButton.width - FoamyStyle.gap + FoamyStyle.gapSmall
          // What the subject, the tags and the requester share on a one-line row.
          readonly property real shared: width - ticketRow.indent - endInset - trailing.width
          readonly property real subjectWant: Math.ceil(subject.implicitWidth)
          // The subject keeps this much (two fifths of what they share, and
          // room for some seventeen letters); the status tag gives way before
          // it gets less. The triangle still has the status colour.
          readonly property real subjectFloor: Math.min(subjectWant, Math.max(shared * 0.4, FoamyStyle.rowHeight * 3))
          readonly property real tagsWithStatus: lineStatus.implicitWidth + (ticketRow.flagged ? lead.spacing + linePriority.implicitWidth : 0)
          readonly property bool statusFits: shared - tagsWithStatus - FoamyStyle.gap * 2 >= subjectFloor
          // The requester gives way first: it gets what the subject and the
          // tags leave, and goes when that is less than `nameFloor` (a few
          // letters and "…" say nothing).
          readonly property real nameWant: Math.ceil(sender.implicitWidth)
          readonly property real nameRoom: shared - subjectWant - FoamyStyle.gap - (lead.width > 0 ? lead.width + FoamyStyle.gap : 0) - FoamyStyle.gapSmall
          readonly property real nameFloor: Math.min(nameWant, FoamyStyle.rowHeight)
          readonly property bool nameShown: ticketRow.oneLine && ticketRow.requester !== "" && nameRoom >= nameFloor
          width: parent.width
          height: Math.max(strip, subject.y + subject.implicitHeight)
          FontMetrics {
            id: subjectMetrics
            font: subject.font
          }
          // The subject's first line: the triangle, the tags and the actions
          // are centred on it, also when the subject takes two lines.
          Item {
            id: firstLine
            y: subject.y
            width: parent.width
            height: subjectMetrics.height
          }
          // Points right while closed, down while open; coloured by status.
          FoamyIcon {
            id: disclosure
            objectName: "disclosure"
            visible: !ticketRow.wide
            anchors.left: parent.left
            anchors.verticalCenter: firstLine.verticalCenter
            name: ticketRow.expanded ? "chevron-down" : "chevron-right"
            color: FoamyPalette.onSurface(ticketRow.statusColor, ticketRow.headSurface)
            width: Commons.Style.space(14)
            height: width
          }
          PlainText {
            id: subject
            objectName: "subject"
            anchors.left: parent.left
            anchors.leftMargin: ticketRow.indent
            anchors.right: lead.left
            anchors.rightMargin: FoamyStyle.gap
            y: Math.max(0, Math.round((titleLine.strip - subjectMetrics.height) / 2))
            text: ticketRow.ticket.subject || FoamyI18n.t("(no subject)")
            font.pixelSize: ticketRow.oneLine ? FoamyStyle.font.body : FoamyStyle.font.subtitle
            // Opening marks the ticket read: the one being read keeps the
            // weight of the unread rows around it.
            font.weight: ticketRow.showsUnread || ticketRow.expanded ? Font.DemiBold : Font.Normal
            color: ticketRow.muted ? FoamyPalette.secondaryText : FoamyPalette.text
            maximumLineCount: ticketRow.subjectLines
            wrapMode: ticketRow.subjectLines > 1 ? Text.Wrap : Text.NoWrap
            elide: Text.ElideRight
          }
          // A one-line ticket's status in words (unless it is Open, as most
          // are) and its priority, before the requester.
          Row {
            id: lead
            objectName: "lead"
            anchors.right: sender.left
            anchors.rightMargin: width > 0 ? FoamyStyle.gap : 0
            // The words in the tags sit on the subject's line, as the name
            // and the time do (a tag's text is centred in it, in their size).
            anchors.baseline: subject.baseline
            baselineOffset: (linePriority.implicitHeight - whenLabel.implicitHeight) / 2 + whenLabel.baselineOffset
            spacing: FoamyStyle.gapSmall
            StatusLabel {
              id: lineStatus
              objectName: "lineStatus"
              visible: ticketRow.oneLine && ticketRow.ticket.status !== "Open" && titleLine.statusFits
              text: FoamyI18n.t(ticketRow.ticket.status)
              status: ticketRow.ticket.status
              soft: true
              surface: ticketRow.headSurface
            }
            StatusLabel {
              id: linePriority
              objectName: "linePriority"
              visible: ticketRow.oneLine && ticketRow.flagged
              text: FoamyI18n.t(ticketRow.ticket.priority)
              tone: ticketRow.priorityTone
              strong: ticketRow.urgentPill
              surface: ticketRow.headSurface
            }
          }
          // A one-line ticket's requester, with the separator that goes
          // with it when it is cut or left out.
          PlainText {
            id: sender
            objectName: "sender"
            visible: titleLine.nameShown
            anchors.right: trailing.left
            anchors.rightMargin: titleLine.nameShown ? FoamyStyle.gapSmall : 0
            anchors.baseline: subject.baseline
            width: titleLine.nameShown ? Math.min(titleLine.nameWant, titleLine.nameRoom) : 0
            text: ticketRow.requester + " ·"
            color: whenLabel.color
            font: whenLabel.font
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
          }
          Row {
            id: trailing
            objectName: "trailing"
            anchors.right: ticketRow.wide ? parent.right : readButton.left
            anchors.rightMargin: ticketRow.wide ? 0 : FoamyStyle.gapSmall
            // On the subject's first line, as text of another size sits on a line.
            anchors.baseline: subject.baseline
            baselineOffset: whenLabel.baselineOffset
            spacing: FoamyStyle.gapSmall
            // Unread, without a rail: a dot by the time.
            Rectangle {
              id: unreadDot
              objectName: "unreadDot"
              visible: ticketRow.showsUnread && !ticketRow.expanded
              anchors.verticalCenter: parent.verticalCenter
              width: Commons.Style.space(7)
              height: width
              radius: width / 2
              color: FoamyPalette.accent
            }
            // Closed, the time of the newest comment ends every title line at
            // the same place; open, it's in the footer.
            PlainText {
              id: whenLabel
              objectName: "when"
              visible: !ticketRow.expanded
              text: ticketRow.when(ticketRow.ticket.received)
              color: ticketRow.muted ? FoamyPalette.mutedText : FoamyPalette.secondaryText
              font.pixelSize: FoamyStyle.font.bodySmall
              wrapMode: Text.NoWrap
            }
          }
          // The two actions keep their slots on every row, so the time before
          // them forms one column. Separate targets keep them from toggling
          // the ticket. Wide: the reading pane has the ticket's actions.
          FoamyAction {
            id: readButton
            visible: !ticketRow.wide
            anchors.right: openButton.left
            anchors.verticalCenter: firstLine.verticalCenter
            iconName: ticketRow.read ? "mail" : "mail-open"
            tooltipText: ticketRow.read ? FoamyI18n.t("Mark as unread") : FoamyI18n.t("Mark as read")
            foreground: FoamyPalette.secondaryText
            // Hidden, it takes no click: the click opens the ticket, like the
            // rest of the row.
            enabled: ticketRow.readActionShown
            opacity: ticketRow.readActionShown ? 1 : 0
            Behavior on opacity {
              NumberAnimation {
                duration: FoamyMotion.hover
              }
            }
            hasCursor: ticketRow.cursorPart === 1
            cursorByKeys: ticketRow.byKeys
            onHoveredChanged: if (hovered)
              ticketRow.hovered(1)
            onClicked: ticketRow.readToggleRequested()
          }
          FoamyAction {
            id: openButton
            visible: !ticketRow.wide
            anchors.right: parent.right
            anchors.rightMargin: -FoamyStyle.gap
            anchors.verticalCenter: firstLine.verticalCenter
            iconName: "external-link"
            tooltipText: FoamyI18n.t("View in Zendesk")
            foreground: ticketRow.muted ? FoamyPalette.secondaryText : FoamyPalette.text
            hasCursor: ticketRow.cursorPart === 2
            cursorByKeys: ticketRow.byKeys
            onHoveredChanged: if (hovered)
              ticketRow.hovered(2)
            onClicked: ticketRow.openRequested()
          }
        }
        // Line 2: the status and the priority as tags, then the number and the
        // requester in one text that takes the rest and elides.
        // A Row, so it never wraps to a third line.
        Row {
          id: metaLine
          objectName: "metaLine"
          visible: !ticketRow.oneLine
          anchors.left: parent.left
          anchors.leftMargin: ticketRow.indent
          anchors.right: parent.right
          spacing: FoamyStyle.gap
          Row {
            id: tags
            spacing: FoamyStyle.gapSmall
            // In a list the status steps back (a tint); the open ticket's own
            // header keeps the solid tag.
            StatusLabel {
              id: statusTag
              objectName: "statusTag"
              text: FoamyI18n.t(ticketRow.ticket.status)
              status: ticketRow.ticket.status
              soft: !ticketRow.expanded
              surface: ticketRow.headSurface
            }
            StatusLabel {
              id: priorityPill
              objectName: "priorityPill"
              visible: ticketRow.flagged
              text: FoamyI18n.t(ticketRow.ticket.priority)
              tone: ticketRow.priorityTone
              strong: ticketRow.urgentPill
              surface: ticketRow.headSurface
            }
          }
          PlainText {
            id: meta
            objectName: "meta"
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, metaLine.width - tags.width - metaLine.spacing - (cardAssignment.visible ? cardAssignment.width + metaLine.spacing : 0))
            text: ticketRow.fittedMeta(ticketRow.metaParts, width, metaMetrics)
            color: ticketRow.muted ? FoamyPalette.mutedText : FoamyPalette.secondaryText
            font.pixelSize: FoamyStyle.font.bodySmall
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            FontMetrics {
              id: metaMetrics
              font: meta.font
            }
          }
          // The open card says whose ticket it is at the line's end, as the
          // Wide pane's header does.
          PlainText {
            id: cardAssignment
            objectName: "cardAssignment"
            visible: ticketRow.expanded
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, metaLine.width * 0.4)
            text: ticketRow.assignmentText
            color: FoamyPalette.secondaryText
            font.pixelSize: FoamyStyle.font.bodySmall
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
          }
        }
      }

      // Below the header: the newest comment (closed) or the timeline (open)
      // and the open card's footer.
      Column {
        id: rest
        anchors.left: head.left
        anchors.right: head.right
        // From the header's own place, not from where it is pinned.
        y: ticketRow.pad + head.height + (ticketRow.expanded ? ticketRow.pad * 2 : comment.visible ? head.spacing : 0)
        spacing: FoamyStyle.gapSmall + FoamyStyle.gapTiny
        PlainText {
          id: comment
          objectName: "comment"
          visible: !ticketRow.expanded && !ticketRow.oneLine && !ticketRow.wide && text !== ""
          anchors.left: parent.left
          anchors.leftMargin: ticketRow.indent
          anchors.right: parent.right
          text: ticketRow.previewLine
          color: ticketRow.previewIsNote ? FoamyPalette.mutedText : FoamyPalette.text
          font.pixelSize: ticketRow.previewIsNote ? FoamyStyle.font.bodySmall : FoamyStyle.font.body
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Column {
          id: timeline
          visible: ticketRow.expanded
          anchors.left: parent.left
          anchors.right: parent.right
          // In the comments' place while there are none to show, or above
          // comments that may not be the newest.
          PlainText {
            id: notice
            objectName: "timelineNotice"
            visible: text !== ""
            anchors.left: parent.left
            anchors.leftMargin: ticketRow.indent
            anchors.right: parent.right
            bottomPadding: ticketRow.historyCount > 0 ? FoamyStyle.gapLarge : 0
            text: ticketRow.timelineNotice
            color: FoamyPalette.mutedText
            font.pixelSize: FoamyStyle.font.bodySmall
          }
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
              readonly property bool internal: model.internal === true
              // This comment at full length; the others stay clipped. The
              // row remembers it (`unfolded`) for a delegate built again.
              property bool full: ticketRow.unfolded[model.revision] === true
              onFullChanged: ticketRow.unfolded[model.revision] = full
              // Lines shown before it is clipped.
              readonly property int limit: index === ticketRow.newestUnreadIndex ? ticketRow.clipLinesNewest : ticketRow.clipLines
              readonly property bool clipped: !full && entryBody.truncated
              // Long enough to fold back once shown in full.
              readonly property bool foldable: clipped || (full && entryBody.lineCount > limit)
              // What the text lies on: clipped text fades into it.
              readonly property color surface: internal ? Qt.tint(ticketRow.cardColor, ticketRow.noteTint) : ticketRow.cardColor
              // A note's surface takes a little room above and below it.
              readonly property int inset: internal ? FoamyStyle.gapTiny : 0
              visible: index < ticketRow.shownCount
              width: timeline.width
              height: visible ? entry.implicitHeight + inset * 2 + FoamyStyle.gapLarge : 0
              // The rail: a dot per comment under the disclosure triangle,
              // filled for a comment that was unread, and a line to the next.
              Rectangle {
                id: dot
                anchors.left: parent.left
                anchors.leftMargin: Math.round((disclosure.width - width) / 2)
                y: entry.y + Math.round((byline.height - height) / 2)
                width: Commons.Style.space(7)
                height: width
                radius: width / 2
                color: entryItem.fresh ? FoamyPalette.accent : ticketRow.cardColor
                border.width: FoamyStyle.borderWidth
                border.color: entryItem.fresh ? FoamyPalette.accent : FoamyPalette.mutedText
              }
              Rectangle {
                visible: entryItem.index < ticketRow.shownCount - 1
                anchors.horizontalCenter: dot.horizontalCenter
                anchors.top: dot.bottom
                anchors.topMargin: FoamyStyle.borderWidth
                // It ends under the next comment's dot, which is drawn over it.
                height: Math.max(0, entryItem.height - entryItem.inset - dot.height / 2 - FoamyStyle.borderWidth)
                width: FoamyStyle.borderWidth
                color: FoamyPalette.divider
              }
              // An internal note is not what the requester was sent: it lies on
              // a tinted surface, clear of the rail.
              Rectangle {
                objectName: "noteSurface"
                visible: entryItem.internal
                anchors.left: entry.left
                anchors.leftMargin: -ticketRow.notePad
                anchors.right: parent.right
                anchors.top: entry.top
                anchors.topMargin: -ticketRow.notePad
                anchors.bottom: entry.bottom
                anchors.bottomMargin: -ticketRow.notePad
                radius: FoamyStyle.radiusSmall
                color: ticketRow.noteTint
              }
              Column {
                id: entry
                anchors.left: parent.left
                anchors.leftMargin: ticketRow.indent
                anchors.right: parent.right
                anchors.rightMargin: entryItem.internal ? ticketRow.notePad : 0
                y: entryItem.inset
                spacing: FoamyStyle.gapTiny
                // Who wrote it, whether it is an internal note, when, and
                // whether it was unread. A long name elides first, so the
                // line never leaves the card; then the time gives way; the
                // two labels stay whole.
                Row {
                  id: byline
                  objectName: "byline"
                  readonly property real labels: (noteLabel.visible ? noteLabel.width + spacing : 0) + (freshLabel.visible ? freshLabel.width + spacing : 0)
                  readonly property real nameWant: Math.ceil(authorLabel.implicitWidth)
                  // The name keeps this much before the time is cut.
                  readonly property real nameFloor: Math.min(nameWant, FoamyStyle.rowHeight)
                  width: parent.width
                  spacing: FoamyStyle.gap
                  // As wide as the name as it is drawn: when it is cut, what
                  // follows starts right after its "…".
                  Item {
                    width: Math.min(authorLabel.width, Math.ceil(authorLabel.contentWidth))
                    height: authorLabel.height
                    PlainText {
                      id: authorLabel
                      objectName: "author"
                      anchors.left: parent.left
                      width: Math.max(0, Math.min(byline.nameWant, byline.width - byline.labels - timeLabel.width - byline.spacing))
                      text: ticketRow.author(entryItem.model.sender, entryItem.model.mine)
                      color: FoamyPalette.text
                      font.pixelSize: FoamyStyle.font.bodySmall
                      font.weight: Font.DemiBold
                      wrapMode: Text.NoWrap
                      elide: Text.ElideRight
                    }
                  }
                  PlainText {
                    id: noteLabel
                    objectName: "noteLabel"
                    visible: entryItem.internal
                    // Whole pixels, so the texts after it stay sharp.
                    width: Math.ceil(implicitWidth)
                    text: FoamyI18n.t("Internal note")
                    color: FoamyPalette.onSurface(FoamyPalette.warning, entryItem.surface)
                    font.pixelSize: FoamyStyle.font.bodySmall
                    font.weight: Font.DemiBold
                    wrapMode: Text.NoWrap
                  }
                  PlainText {
                    id: timeLabel
                    objectName: "stamp"
                    width: Math.max(0, Math.min(Math.ceil(implicitWidth), byline.width - byline.labels - byline.nameFloor - byline.spacing))
                    text: ticketRow.stamp(entryItem.model.received)
                    color: FoamyPalette.secondaryText
                    font.pixelSize: FoamyStyle.font.bodySmall
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                  }
                  PlainText {
                    id: freshLabel
                    objectName: "freshLabel"
                    visible: entryItem.fresh
                    width: Math.ceil(implicitWidth)
                    text: FoamyI18n.t("New")
                    color: FoamyPalette.onSurface(FoamyPalette.accent)
                    font.pixelSize: FoamyStyle.font.bodySmall
                    font.weight: Font.DemiBold
                    wrapMode: Text.NoWrap
                  }
                }
                PlainText {
                  id: entryBody
                  width: parent.width
                  text: entryItem.model.body
                  color: FoamyPalette.text
                  maximumLineCount: entryItem.full ? 100000 : entryItem.limit
                  // Clipped text fades out instead of ending in "…": over a
                  // line and a bit, so the lines above it stay readable.
                  Rectangle {
                    objectName: "fade"
                    visible: entryItem.clipped
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.min(parent.height, FoamyStyle.font.body * 1.5)
                    gradient: Gradient {
                      GradientStop {
                        position: 0
                        color: Qt.alpha(entryItem.surface, 0)
                      }
                      GradientStop {
                        position: 1
                        color: entryItem.surface
                      }
                    }
                  }
                }
                MoreLink {
                  id: lengthButton
                  objectName: "lengthButton"
                  visible: entryItem.foldable
                  // Its label starts where the text does.
                  anchors.left: parent.left
                  anchors.leftMargin: -FoamyStyle.gap
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
            anchors.left: parent.left
            anchors.leftMargin: ticketRow.indent - FoamyStyle.gap
            text: FoamyI18n.tn("Show %1 earlier comments", hidden)
            onClicked: ticketRow.showEarlier = true
          }
        }
        // The open card ends here: a way to close it without scrolling back
        // to the band. Built only while the ticket is open, as the comments
        // are.
        Loader {
          id: footerRow
          active: ticketRow.expanded
          visible: active
          anchors.left: parent.left
          anchors.right: parent.right
          sourceComponent: Item {
            objectName: "cardFooterRow"
            implicitHeight: cardFooter.y + cardFooter.implicitHeight
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              height: FoamyStyle.borderWidth
              color: FoamyPalette.divider
            }
            PlainText {
              id: cardFooter
              objectName: "cardFooter"
              anchors.left: parent.left
              anchors.leftMargin: ticketRow.indent
              anchors.right: collapseButton.left
              anchors.rightMargin: FoamyStyle.gapSmall
              y: FoamyStyle.gap
              // Empty (the header says whose ticket it is, each byline when
              // its comment came): it keeps the row one line high.
              text: ""
              color: FoamyPalette.secondaryText
              font.pixelSize: FoamyStyle.font.bodySmall
              wrapMode: Text.NoWrap
              elide: Text.ElideRight
            }
            // Its label ends where the card's content does.
            MoreLink {
              id: collapseButton
              objectName: "collapseButton"
              anchors.right: parent.right
              anchors.rightMargin: -FoamyStyle.gap
              anchors.verticalCenter: cardFooter.verticalCenter
              text: FoamyI18n.t("Collapse")
              Accessible.description: FoamyI18n.t("Collapse ticket")
              onClicked: ticketRow.toggleRequested()
            }
          }
        }
      }
    }
    // Between two rows: little, the rows' own padding does the rest.
    Item {
      width: 1
      height: ticketRow.expanded ? FoamyStyle.gap : ticketRow.oneLine ? 0 : ticketRow.wide ? FoamyStyle.gapTiny : FoamyStyle.gapSmall
    }
  }
}
