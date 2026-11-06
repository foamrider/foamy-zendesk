import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "kit"
import "Schedule.js" as Schedule

// Copied from foamy-train/ScheduleDay.qml (TrainText -> PlainText); keep in step.
// One weekday of the schedule: on/off switch plus from/to times (local time;
// "24:00" ends at midnight, overnight ranges carry into the next day).
RowLayout {
  id: root
  property string label: ""
  property string fromLabel: "From"
  property string toLabel: "To"
  property string value: ""
  property string lastRange: "06:00-18:00"
  readonly property bool dayEnabled: value !== ""
  signal changed(string value)
  signal invalid()
  spacing: FoamyStyle.gap
  function restoreInputs(force) {
    if (value !== "" && Schedule.validRange(value)) lastRange = value
    var parts = lastRange.split("-")
    if (force || !fromInput.inputActiveFocus) fromInput.text = parts[0]
    if (force || !toInput.inputActiveFocus) toInput.text = parts[1]
  }
  function saveInputs() {
    if (!dayEnabled) return
    var range = fromInput.text.trim() + "-" + toInput.text.trim()
    if (!Schedule.validRange(range)) { invalid(); return }
    if (range !== value) changed(range)
  }
  onValueChanged: restoreInputs()
  Component.onCompleted: restoreInputs()
  PlainText {
    Layout.fillWidth: true
    text: root.label
  }
  ToggleSwitch {
    id: daySwitch
    objectName: "daySwitch"
    checked: root.dayEnabled
    trackHeight: Style.space(17)
    foreground: Commons.Color.popups.text
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.checked: checked
    Accessible.onToggleAction: toggled()
    Keys.onSpacePressed: toggled()
    Keys.onReturnPressed: toggled()
    Keys.onEnterPressed: toggled()
    onToggled: root.changed(checked ? "" : root.lastRange)
    Rectangle {
      anchors.fill: parent
      color: "transparent"
      radius: FoamyStyle.radius
      border.width: daySwitch.activeFocus ? 1 : 0
      border.color: Commons.Color.accent
    }
  }
  SafeTextField {
    id: fromInput
    objectName: "fromTime"
    Layout.preferredWidth: Style.space(64)
    enabled: root.dayEnabled
    opacity: enabled ? 1 : FoamyStyle.disabledOpacity
    horizontalAlignment: Text.AlignHCenter
    maximumLength: 5
    translate: FoamyI18n.t
    Accessible.name: root.label + " · " + root.fromLabel
    onEditingFinished: root.saveInputs()
    onKeyPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.restoreInputs(true)
        event.accepted = true
      }
    }
  }
  SafeTextField {
    id: toInput
    objectName: "toTime"
    Layout.preferredWidth: Style.space(64)
    enabled: root.dayEnabled
    opacity: enabled ? 1 : FoamyStyle.disabledOpacity
    horizontalAlignment: Text.AlignHCenter
    maximumLength: 5
    translate: FoamyI18n.t
    Accessible.name: root.label + " · " + root.toLabel
    onEditingFinished: root.saveInputs()
    onKeyPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.restoreInputs(true)
        event.accepted = true
      }
    }
  }
}
