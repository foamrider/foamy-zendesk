pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "kit"
import "Model.js" as Model

// The Wide panel's reading pane while no ticket is selected: today's date,
// the counts the list's sections show, the tickets that need a reply (the
// most urgent first; a click selects one) and the tickets per group. All of
// it is TicketStore.overview, from the inbox the helper already fetched: the
// whole inbox, also while the list hides read tickets.
Item {
  id: overview
  // TicketStore.overview (Model.overview).
  property var summary: ({
      unread: 0,
      mine: 0,
      unassigned: 0,
      waiting: 0,
      awaiting: [],
      awaitingTotal: 0,
      awaitingMore: 0,
      awaitingAll: false,
      unknown: 0,
      groups: [],
      groupsMore: 0
    })
  property double now: Date.now()
  // Whether the list groups the tickets that wait on others (then their
  // count shows too).
  property bool showWaiting: true
  // The keyboard cursor on a ticket that needs a reply (its index), or -1.
  // One past the last ticket is the link under them.
  property int cursorRow: -1
  signal hovered(int row)
  signal selectRequested(string id)
  readonly property alias awaitingRows: awaitingRepeater
  readonly property alias scroll: overviewScroll
  // Tickets that need a reply are New or Open: their subjects start after the wider tag.
  readonly property real tagSlot: Math.max(newTag.width, openTag.width)
  StatusLabel {
    id: newTag
    visible: false
    text: FoamyI18n.t("New")
    status: "New"
  }
  StatusLabel {
    id: openTag
    visible: false
    text: FoamyI18n.t("Open")
    status: "Open"
  }
  // The link under the rows: "7 more need a reply", or "Show less" once they all show.
  readonly property bool moreShown: summary.awaitingMore > 0 || summary.awaitingAll === true
  // The waits end together in one column as wide as the longest of them, so
  // every subject has the same room.
  FontMetrics {
    id: ageMetrics
    font.family: FoamyStyle.fontFamily
    font.pixelSize: FoamyStyle.font.bodySmall
    font.weight: Font.DemiBold
  }
  readonly property real ageSlot: Math.ceil(summary.awaiting.reduce(function (widest, item) {
    return Math.max(widest, ageMetrics.advanceWidth(overview.waited(item.received)))
  }, 0))
  readonly property real largestGroup: summary.groups.reduce(function (largest, group) {
    return Math.max(largest, group.mine + group.unassigned)
  }, 1)
  // A group's track, and the legend's dots, are this thick.
  readonly property int trackHeight: FoamyStyle.gap

  // Scrolls so the ticket under the keyboard cursor (or the link under the
  // tickets) is in view.
  function revealRow(index) {
    var row = moreShown && index === awaitingRepeater.count ? moreLink : awaitingRepeater.itemAt(index)
    if (!row)
      return
    var y = row.mapToItem(overviewScroll.contentItem, 0, 0).y
    if (y < overviewScroll.contentY)
      overviewScroll.contentY = Math.max(0, y - FoamyStyle.gap)
    else if (y + row.height > overviewScroll.contentY + overviewScroll.height)
      overviewScroll.contentY = Math.min(overviewScroll.contentHeight - overviewScroll.height, y + row.height + FoamyStyle.gap - overviewScroll.height)
  }

  // The "N more need a reply" / "Show less" link (pointer and keyboard).
  // The store holds what shows: its `awaiting` is also the keyboard cursor's
  // stops (InboxView). Folding takes rows away: a cursor on one of them
  // moves to the last row that stays.
  function toggleMore() {
    if (summary.awaitingAll && cursorRow >= Model.MAX_AWAITING)
      hovered(Model.MAX_AWAITING - 1)
    TicketStore.expandOverview(!summary.awaitingAll)
  }

  // How long a ticket has waited for its reply.
  function waited(received) {
    var minutes = Math.max(1, Math.floor((now - received) / 60000))
    if (minutes < 60)
      return FoamyI18n.tn("%1 minutes", minutes)
    var hours = Math.floor(minutes / 60)
    return hours < 48 ? FoamyI18n.tn("%1 hours", hours) : FoamyI18n.tn("%1 days", Math.floor(hours / 24))
  }
  // Late: an Urgent or High ticket that has waited an hour. Only those waits
  // are red; an old ticket of normal priority is not an alarm.
  function overdue(item) {
    return (item.priority === "Urgent" || item.priority === "High") && now - item.received >= 3600000
  }
  function groupName(group) {
    return group.name || FoamyI18n.t("No group")
  }

  component Caption: PlainText {
    font.pixelSize: FoamyStyle.font.bodySmall
    font.weight: Font.DemiBold
    color: FoamyPalette.secondaryText
    wrapMode: Text.NoWrap
  }
  component Stat: Column {
    id: stat
    required property int value
    required property string label
    property color tone: FoamyPalette.text
    spacing: FoamyStyle.gapSmall
    PlainText {
      text: FoamyI18n.number(stat.value)
      color: stat.tone
      font.pixelSize: FoamyStyle.font.display
      font.weight: Font.DemiBold
      wrapMode: Text.NoWrap
    }
    PlainText {
      text: stat.label
      color: FoamyPalette.secondaryText
      font.pixelSize: FoamyStyle.font.bodySmall
      wrapMode: Text.NoWrap
    }
  }
  // A text link, as an open ticket's "Show more": the label in the accent.
  component TextLink: FoamyCursorSurface {
    id: link
    required property string text
    readonly property alias labelHeight: linkLabel.implicitHeight
    width: linkLabel.implicitWidth + FoamyStyle.gap * 2
    height: FoamyStyle.actionSize - 4
    foreground: FoamyPalette.accent
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: link.clicked()
    PlainText {
      id: linkLabel
      anchors.centerIn: parent
      text: link.text
      color: FoamyPalette.onSurface(FoamyPalette.accent)
      font.pixelSize: FoamyStyle.font.bodySmall
      font.weight: Font.DemiBold
      wrapMode: Text.NoWrap
    }
  }

  Flickable {
    id: overviewScroll
    objectName: "overviewScroll"
    anchors.fill: parent
    contentWidth: width
    // Under the last block: the full padding, or what is left of it (at
    // least `gap`) where everything but the padding fits, so an overview
    // that fits never scrolls just to show its own margin.
    readonly property real bottomInset: {
      var spare = height - column.implicitHeight
      return spare >= FoamyStyle.gap && spare < FoamyStyle.padding ? spare : FoamyStyle.padding
    }
    contentHeight: column.implicitHeight + bottomInset
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      policy: Controls.ScrollBar.AsNeeded
    }
    FoamyWheelScroll {
      target: overviewScroll
    }
    Column {
      id: column
      x: FoamyStyle.padding
      width: overviewScroll.width - FoamyStyle.padding * 2
      topPadding: FoamyStyle.padding - 2
      spacing: FoamyStyle.sectionGap

      Column {
        width: parent.width
        spacing: FoamyStyle.gap
        Caption {
          objectName: "overviewDate"
          width: parent.width
          elide: Text.ElideRight
          // The pattern is the catalog's (Norwegian writes "6. november");
          // the weekday starts the line, so it gets a capital letter.
          text: Model.capitalized(new Date(overview.now).toLocaleDateString(Qt.locale(FoamyI18n.formatLocale), FoamyI18n.t("dddd d MMMM")))
        }
        Flow {
          objectName: "overviewStats"
          width: parent.width
          spacing: FoamyStyle.padding + 2
          Stat {
            value: overview.summary.unread
            label: FoamyI18n.t("Unread")
            tone: overview.summary.unread > 0 ? FoamyPalette.onSurface(FoamyPalette.accent) : FoamyPalette.text
          }
          Stat {
            value: overview.summary.mine
            label: FoamyI18n.t("Assigned to you")
          }
          Stat {
            value: overview.summary.unassigned
            label: FoamyI18n.t("Unassigned")
          }
          Stat {
            // Also while the list hides read tickets (it then has no such
            // section): the overview counts the whole inbox.
            visible: overview.showWaiting || overview.summary.waiting > 0
            value: overview.summary.waiting
            label: FoamyI18n.t("Waiting on others")
          }
        }
      }

      Column {
        width: parent.width
        spacing: FoamyStyle.gapSmall + 2
        Row {
          width: parent.width
          spacing: FoamyStyle.gap
          Accessible.role: Accessible.Heading
          Accessible.name: awaitingCaption.text + (awaitingCount.visible ? " " + awaitingCount.text : "")
          Caption {
            id: awaitingCaption
            text: FoamyI18n.t("Needs a reply")
          }
          // Every ticket that needs a reply, the ones under the link too.
          PlainText {
            id: awaitingCount
            objectName: "awaitingCount"
            visible: overview.summary.awaitingTotal > 0
            anchors.baseline: awaitingCaption.baseline
            text: FoamyI18n.number(overview.summary.awaitingTotal)
            color: FoamyPalette.mutedText
            font.family: FoamyStyle.monoFamily
            font.pixelSize: FoamyStyle.font.caption
            wrapMode: Text.NoWrap
          }
        }
        PlainText {
          objectName: "nobodyWaiting"
          // Only when every ticket's comments are in: else nothing is known to need one.
          visible: overview.summary.awaiting.length === 0 && overview.summary.unknown === 0
          width: parent.width
          text: FoamyI18n.t("Nothing needs a reply")
          color: FoamyPalette.mutedText
          font.pixelSize: FoamyStyle.font.bodySmall
        }
        Column {
          width: parent.width
          spacing: FoamyStyle.gapSmall
          visible: overview.summary.awaiting.length > 0
          Repeater {
            id: awaitingRepeater
            model: overview.summary.awaiting
            // The status tag in its slot, the subject over the priority and
            // who wrote last, the wait at the end.
            FoamyCursorSurface {
              id: row
              required property var modelData
              required property int index
              readonly property bool flagged: modelData.priority === "Urgent" || modelData.priority === "High"
              objectName: "awaiting-" + modelData.id
              width: parent.width
              height: Math.max(FoamyStyle.rowHeight + FoamyStyle.gap, lines.implicitHeight + (FoamyStyle.gapSmall + 1) * 2)
              // At rest a field, not a hovered row: the cursor tints it.
              color: hasCursor ? Qt.tint(FoamyPalette.fieldFill, fill) : FoamyPalette.fieldFill
              foreground: FoamyPalette.text
              hasCursor: overview.cursorRow === index
              onHovered: overview.hovered(index)
              onClicked: overview.selectRequested(modelData.id)
              Accessible.role: Accessible.Button
              Accessible.name: (modelData.subject || FoamyI18n.t("(no subject)")) + ", " + FoamyI18n.t(modelData.status) + (flagged ? ", " + FoamyI18n.t(modelData.priority) : "") + (modelData.read ? "" : ", " + FoamyI18n.t("unread")) + ", " + age.text
              // The newest comment, which the row has no line for.
              Accessible.description: modelData.body
              Accessible.onPressAction: overview.selectRequested(modelData.id)
              StatusLabel {
                id: tag
                anchors.left: parent.left
                anchors.leftMargin: FoamyStyle.rowPadding
                anchors.verticalCenter: parent.verticalCenter
                text: FoamyI18n.t(row.modelData.status)
                status: row.modelData.status
                soft: true
                // Its ink is chosen against the filled row, not the pane.
                surface: Qt.tint(FoamyPalette.background, row.color)
              }
              PlainText {
                id: age
                objectName: "age"
                anchors.right: parent.right
                anchors.rightMargin: FoamyStyle.rowPadding
                anchors.verticalCenter: parent.verticalCenter
                text: overview.waited(row.modelData.received)
                color: overview.overdue(row.modelData) ? FoamyPalette.onSurface(FoamyPalette.error) : FoamyPalette.secondaryText
                font.pixelSize: FoamyStyle.font.bodySmall
                font.weight: Font.DemiBold
                wrapMode: Text.NoWrap
              }
              Column {
                id: lines
                anchors.left: parent.left
                anchors.leftMargin: FoamyStyle.rowPadding + overview.tagSlot + FoamyStyle.gap + 2
                anchors.right: parent.right
                anchors.rightMargin: FoamyStyle.rowPadding + overview.ageSlot + FoamyStyle.gapLarge
                anchors.verticalCenter: parent.verticalCenter
                spacing: FoamyStyle.gapTiny
                PlainText {
                  objectName: "subject"
                  width: parent.width
                  text: row.modelData.subject || FoamyI18n.t("(no subject)")
                  font.weight: row.modelData.read ? Font.Normal : Font.DemiBold
                  wrapMode: Text.NoWrap
                  elide: Text.ElideRight
                }
                // As tall as a pill in every row, so the rows are one height.
                Row {
                  id: metaLine
                  width: parent.width
                  height: newTag.height
                  spacing: FoamyStyle.gap
                  StatusLabel {
                    id: priorityPill
                    objectName: "priorityPill"
                    visible: row.flagged
                    anchors.verticalCenter: parent.verticalCenter
                    text: FoamyI18n.t(row.modelData.priority)
                    strong: row.modelData.priority === "Urgent"
                    tone: strong ? FoamyPalette.error : FoamyPalette.onSurface(FoamyPalette.warning)
                  }
                  PlainText {
                    objectName: "meta"
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, metaLine.width - (row.flagged ? priorityPill.width + metaLine.spacing : 0))
                    text: "#" + row.modelData.id + (row.modelData.requester ? " · " + row.modelData.requester : "") + (row.modelData.unassigned ? " · " + FoamyI18n.t("Unassigned") : "")
                    color: FoamyPalette.secondaryText
                    font.pixelSize: FoamyStyle.font.bodySmall
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }
        }
        // Under the rows: the link that shows the rest in place (or folds
        // them again), then what can't be known yet.
        Flow {
          id: moreLine
          visible: overview.moreShown || overview.summary.unknown > 0
          width: parent.width
          spacing: FoamyStyle.gapSmall
          // One text line tall: the link's padding hangs outside its slot, so
          // its label starts where the rows do.
          Item {
            visible: overview.moreShown
            width: moreLink.width - FoamyStyle.gap
            height: moreLink.labelHeight
            TextLink {
              id: moreLink
              objectName: "awaitingMore"
              anchors.left: parent.left
              anchors.leftMargin: -FoamyStyle.gap
              anchors.verticalCenter: parent.verticalCenter
              text: overview.summary.awaitingAll ? FoamyI18n.t("Show less") : FoamyI18n.tn("%1 more need a reply", overview.summary.awaitingMore)
              hasCursor: overview.cursorRow === overview.summary.awaiting.length
              // The store holds what shows: its `awaiting` is also the
              // keyboard cursor's stops (InboxView). Folding takes rows away:
              // a cursor on one of them moves to the last row that stays.
              onClicked: overview.toggleMore()
            }
          }
          // Tickets whose comments haven't come may need a reply too.
          PlainText {
            id: unknownNote
            objectName: "awaitingUnknown"
            visible: overview.summary.unknown > 0
            width: Math.min(implicitWidth, moreLine.width)
            text: FoamyI18n.tn("%1 more may need a reply: their comments haven't loaded yet", overview.summary.unknown)
            color: FoamyPalette.mutedText
            font.pixelSize: FoamyStyle.font.bodySmall
          }
        }
      }

      Column {
        id: groups
        objectName: "overviewGroups"
        visible: overview.summary.groups.length > 0
        width: parent.width
        spacing: FoamyStyle.gapSmall + 2
        // The name column is as wide as the widest name, at most half the
        // block, so the tracks start together and a long name isn't cut short.
        readonly property real nameWidth: Math.min(nameProbe.implicitWidth, width * 0.5)
        Column {
          id: nameProbe
          visible: false
          Repeater {
            model: overview.summary.groups
            PlainText {
              required property var modelData
              text: overview.groupName(modelData)
              wrapMode: Text.NoWrap
            }
          }
        }
        Item {
          width: parent.width
          height: Math.max(groupsCaption.implicitHeight, legend.implicitHeight)
          Caption {
            id: groupsCaption
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: FoamyI18n.t("By group")
          }
          // The two tones of a track, said where the block starts.
          Row {
            id: legend
            objectName: "groupLegend"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: FoamyStyle.gapLarge
            Repeater {
              model: [
                {
                  label: FoamyI18n.t("Assigned to you"),
                  tone: FoamyPalette.accent
                },
                {
                  label: FoamyI18n.t("Unassigned"),
                  tone: Qt.alpha(FoamyPalette.accent, 0.4)
                }
              ]
              Row {
                id: legendEntry
                required property var modelData
                spacing: FoamyStyle.gapSmall + 1
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: overview.trackHeight
                  height: overview.trackHeight
                  radius: FoamyStyle.pillRadius(height)
                  color: legendEntry.modelData.tone
                }
                PlainText {
                  text: legendEntry.modelData.label
                  color: FoamyPalette.secondaryText
                  font.pixelSize: FoamyStyle.font.bodySmall
                  wrapMode: Text.NoWrap
                }
              }
            }
          }
        }
        Repeater {
          model: overview.summary.groups
          Item {
            id: group
            required property var modelData
            readonly property int total: modelData.mine + modelData.unassigned
            // A part of the track: `count` of the largest group's tickets. One
            // ticket among many still shows as a dot.
            function part(count) {
              return count > 0 ? Math.max(track.height, track.width * count / overview.largestGroup) : 0
            }
            width: parent.width
            height: groupLabel.implicitHeight
            PlainText {
              id: groupLabel
              anchors.left: parent.left
              width: groups.nameWidth
              text: overview.groupName(group.modelData)
              wrapMode: Text.NoWrap
              elide: Text.ElideRight
            }
            PlainText {
              id: groupCount
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(implicitWidth, FoamyStyle.padding + FoamyStyle.gap)
              horizontalAlignment: Text.AlignRight
              text: FoamyI18n.number(group.total)
              color: FoamyPalette.secondaryText
              font.pixelSize: FoamyStyle.font.bodySmall
              wrapMode: Text.NoWrap
            }
            // Yours over the group's whole count (yours and the unassigned).
            Rectangle {
              id: track
              anchors.left: groupLabel.right
              anchors.leftMargin: FoamyStyle.gapLarge
              anchors.right: groupCount.left
              anchors.rightMargin: FoamyStyle.gap
              anchors.verticalCenter: parent.verticalCenter
              height: overview.trackHeight
              radius: FoamyStyle.pillRadius(height)
              color: FoamyPalette.hoverFill
              Rectangle {
                anchors.left: parent.left
                width: group.part(group.total)
                height: parent.height
                radius: parent.radius
                color: Qt.alpha(FoamyPalette.accent, 0.4)
              }
              Rectangle {
                anchors.left: parent.left
                width: group.part(group.modelData.mine)
                height: parent.height
                radius: parent.radius
                color: FoamyPalette.accent
              }
            }
          }
        }
        // The list is cut at five groups: say how many more there are.
        PlainText {
          objectName: "groupsMore"
          visible: overview.summary.groupsMore > 0
          width: parent.width
          text: FoamyI18n.tn("%1 more groups", overview.summary.groupsMore)
          color: FoamyPalette.mutedText
          font.pixelSize: FoamyStyle.font.bodySmall
        }
      }
    }
  }
}
