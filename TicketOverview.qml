pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "kit"

// The Wide panel's reading pane while no ticket is selected: today's date,
// the counts the list's sections show, the tickets waiting for a reply (the
// longest wait first; a click selects one) and the tickets per group. All of
// it is TicketStore.overview, from the inbox the helper already fetched.
Item {
  id: overview
  // TicketStore.overview (Model.overview).
  property var summary: ({
      unread: 0,
      mine: 0,
      unassigned: 0,
      waiting: 0,
      awaiting: [],
      awaitingMore: 0,
      groups: [],
      groupsMore: 0
    })
  property double now: Date.now()
  // Whether the list groups waiting tickets (then their count shows too).
  property bool showWaiting: true
  // The keyboard cursor on a waiting ticket (its index), or -1.
  property int cursorRow: -1
  signal hovered(int row)
  signal selectRequested(string id)
  readonly property alias awaitingRows: awaitingRepeater
  // Waiting tickets are New or Open: their subjects start after the wider tag.
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
  readonly property real largestGroup: summary.groups.reduce(function (largest, group) {
    return Math.max(largest, group.mine + group.unassigned)
  }, 1)

  // Scrolls so the waiting ticket under the keyboard cursor is in view.
  function revealRow(index) {
    var row = awaitingRepeater.itemAt(index)
    if (!row)
      return
    var y = row.mapToItem(scroll.contentItem, 0, 0).y
    if (y < scroll.contentY)
      scroll.contentY = Math.max(0, y - FoamyStyle.gap)
    else if (y + row.height > scroll.contentY + scroll.height)
      scroll.contentY = Math.min(scroll.contentHeight - scroll.height, y + row.height + FoamyStyle.gap - scroll.height)
  }

  // How long a ticket has waited, and its tone: amber after an hour, red after four.
  function waited(received) {
    var minutes = Math.max(1, Math.floor((now - received) / 60000))
    if (minutes < 60)
      return FoamyI18n.tn("%1 minutes", minutes)
    var hours = Math.floor(minutes / 60)
    return hours < 48 ? FoamyI18n.tn("%1 hours", hours) : FoamyI18n.tn("%1 days", Math.floor(hours / 24))
  }
  function waitTone(received) {
    var hours = (now - received) / 3600000
    return hours >= 4 ? FoamyPalette.onSurface(FoamyPalette.error) : hours >= 1 ? FoamyPalette.onSurface(FoamyPalette.warning) : FoamyPalette.secondaryText
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

  Flickable {
    id: scroll
    objectName: "overviewScroll"
    anchors.fill: parent
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      policy: Controls.ScrollBar.AsNeeded
    }
    FoamyWheelScroll {
      target: scroll
    }
    Column {
      id: column
      x: FoamyStyle.padding
      width: scroll.width - FoamyStyle.padding * 2
      topPadding: FoamyStyle.padding - 2
      bottomPadding: FoamyStyle.padding
      spacing: FoamyStyle.padding

      Column {
        width: parent.width
        spacing: FoamyStyle.gap
        Caption {
          objectName: "overviewDate"
          text: new Date(overview.now).toLocaleDateString(Qt.locale(FoamyI18n.formatLocale), "dddd d MMMM")
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
            visible: overview.showWaiting
            value: overview.summary.waiting
            label: FoamyI18n.t("Waiting on others")
          }
        }
      }

      Column {
        width: parent.width
        spacing: FoamyStyle.gapSmall + 2
        Caption {
          text: FoamyI18n.t("Waiting for a reply")
        }
        PlainText {
          objectName: "nobodyWaiting"
          visible: overview.summary.awaiting.length === 0
          width: parent.width
          text: FoamyI18n.t("Nobody is waiting for a reply")
          color: FoamyPalette.mutedText
          font.pixelSize: FoamyStyle.font.bodySmall
        }
        Repeater {
          id: awaitingRepeater
          model: overview.summary.awaiting
          FoamyCursorSurface {
            id: row
            required property var modelData
            required property int index
            objectName: "awaiting-" + modelData.id
            width: parent.width
            height: Math.max(FoamyStyle.rowHeight + FoamyStyle.gap, lines.implicitHeight + FoamyStyle.gap * 2)
            color: hasCursor ? Qt.tint(FoamyPalette.hoverFill, fill) : FoamyPalette.hoverFill
            foreground: FoamyPalette.text
            hasCursor: overview.cursorRow === index
            onHovered: overview.hovered(index)
            onClicked: overview.selectRequested(modelData.id)
            Accessible.role: Accessible.Button
            Accessible.name: modelData.subject + ", " + FoamyI18n.t(modelData.status) + ", " + age.text
            Accessible.onPressAction: overview.selectRequested(modelData.id)
            StatusLabel {
              id: tag
              anchors.left: parent.left
              anchors.leftMargin: FoamyStyle.rowPadding
              anchors.verticalCenter: parent.verticalCenter
              text: FoamyI18n.t(row.modelData.status)
              status: row.modelData.status
            }
            Column {
              id: lines
              anchors.left: parent.left
              anchors.leftMargin: FoamyStyle.rowPadding + overview.tagSlot + FoamyStyle.gap + 2
              anchors.right: age.left
              anchors.rightMargin: FoamyStyle.gap
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              PlainText {
                width: parent.width
                text: row.modelData.subject
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
              }
              PlainText {
                width: parent.width
                text: "#" + row.modelData.id + " · " + row.modelData.sender + (row.modelData.unassigned ? " · " + FoamyI18n.t("Unassigned") : "")
                color: FoamyPalette.secondaryText
                font.pixelSize: FoamyStyle.font.bodySmall
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
              }
            }
            PlainText {
              id: age
              objectName: "age"
              anchors.right: parent.right
              anchors.rightMargin: FoamyStyle.rowPadding
              anchors.verticalCenter: parent.verticalCenter
              text: overview.waited(row.modelData.received)
              color: overview.waitTone(row.modelData.received)
              font.pixelSize: FoamyStyle.font.bodySmall
              font.weight: Font.DemiBold
              wrapMode: Text.NoWrap
            }
          }
        }
        // The list is cut at five: say how many more wait.
        PlainText {
          objectName: "awaitingMore"
          visible: overview.summary.awaitingMore > 0
          width: parent.width
          text: FoamyI18n.tn("%1 more waiting", overview.summary.awaitingMore)
          color: FoamyPalette.mutedText
          font.pixelSize: FoamyStyle.font.bodySmall
        }
      }

      Column {
        objectName: "overviewGroups"
        visible: overview.summary.groups.length > 0
        width: parent.width
        spacing: FoamyStyle.gap
        Caption {
          text: FoamyI18n.t("By group")
        }
        Repeater {
          model: overview.summary.groups
          Item {
            id: group
            required property var modelData
            readonly property int total: modelData.mine + modelData.unassigned
            width: parent.width
            height: groupName.implicitHeight
            PlainText {
              id: groupName
              anchors.left: parent.left
              width: Math.min(implicitWidth, parent.width * 0.3)
              text: group.modelData.name || FoamyI18n.t("No group")
              wrapMode: Text.NoWrap
              elide: Text.ElideRight
            }
            // Yours, then unassigned, as parts of the largest group's width.
            Rectangle {
              id: track
              anchors.left: parent.left
              anchors.leftMargin: parent.width * 0.3 + FoamyStyle.gap
              anchors.right: groupCount.left
              anchors.rightMargin: FoamyStyle.gap
              anchors.verticalCenter: parent.verticalCenter
              height: 8
              radius: 4
              color: FoamyPalette.hoverFill
              clip: true
              Row {
                anchors.left: parent.left
                height: parent.height
                Rectangle {
                  width: track.width * group.modelData.mine / overview.largestGroup
                  height: parent.height
                  color: FoamyPalette.accent
                }
                Rectangle {
                  width: track.width * group.modelData.unassigned / overview.largestGroup
                  height: parent.height
                  color: Qt.alpha(FoamyPalette.accent, 0.4)
                }
              }
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
        Row {
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
              required property var modelData
              spacing: FoamyStyle.gapSmall + 1
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 2
                color: parent.modelData.tone
              }
              PlainText {
                text: parent.modelData.label
                color: FoamyPalette.secondaryText
                font.pixelSize: FoamyStyle.font.bodySmall
                wrapMode: Text.NoWrap
              }
            }
          }
        }
      }
    }
  }
}
