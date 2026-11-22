// foamy-kit 0.13.1 c458ce7c07bb3ef9ced7a178cc8d33e421c68faba6c3d972fb3b7f10aa738689 — do not edit; change foamy-kit and run sync
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "FoamySchedule.js" as Schedule

// One weekday of a FoamySchedule week in a settings page: label, on/off
// switch, from/to times (local time; "24:00" ends at midnight, an overnight
// range carries into the next day).
//
//   Repeater {
//     model: Schedule.dayKeys
//     FoamyScheduleDay {
//       required property string modelData
//       required property int index
//       width: parent.width
//       label: FoamyI18n.t(dayLabels[index])
//       fromLabel: FoamyI18n.t("From"); toLabel: FoamyI18n.t("To")
//       value: prefs.value(modelData)                   // "" = day off
//       labelComponent: Component { TrainText { } }     // optional: the plugin's own text type
//       onChanged: function(range) { prefs.save(modelData, range) }
//       onInvalid: root.showTimeError()
//     }
//   }
//
// `value` follows the setting; the row never assigns it. The switch emits
// changed("") to turn a day off and changed(lastRange) to turn it back on
// with its last range. A time field commits on editing finished: a valid
// range that differs from `value` emits changed(range), once until the next
// edit or `value` change (Enter and the focus loss after it are one
// commit); an invalid one emits invalid(). Escape restores the field. A
// refused paste into a time field (too large, timed out, not plain text)
// says why in an error line under the row, through FoamyI18n.t, until that
// field's next edit, as FoamyNumberField does.
// `labelComponent` is any Component whose root has a `text` property
// (default: a plain-text body label); `labelItem` is it.
ColumnLayout {
  id: root
  property string label: ""
  property string fromLabel: "From"
  property string toLabel: "To"
  property string value: ""
  property string lastRange: "06:00-18:00"
  property Component labelComponent: defaultLabel
  readonly property Item labelItem: labelLoader.item
  readonly property bool dayEnabled: value !== ""
  // The range this row last emitted, until an edit or a new `value`: a
  // caller's value may catch up later, and the same commit must not repeat.
  property string _lastCommitted: ""
  // The time field of the last refused paste: its pasteError is the error
  // line (cleared by its next edit), so the newest paste always shows.
  property SafeTextField _pasteField: null
  readonly property string _pasteMessage: dayEnabled && _pasteField !== null && _pasteField.pasteError !== "" ? FoamyI18n.t(_pasteField.pasteError) : ""
  signal changed(string value)
  signal invalid
  spacing: FoamyStyle.gapSmall

  function restoreInputs(force) {
    if (value !== "" && Schedule.validRange(value))
      lastRange = value
    var parts = lastRange.split("-")
    if (force || !fromInput.inputActiveFocus)
      fromInput.text = parts[0]
    if (force || !toInput.inputActiveFocus)
      toInput.text = parts[1]
  }
  function saveInputs() {
    if (!dayEnabled)
      return
    var range = fromInput.text.trim() + "-" + toInput.text.trim()
    if (!Schedule.validRange(range)) {
      invalid()
      return
    }
    if (range !== value && range !== _lastCommitted) {
      _lastCommitted = range
      changed(range)
    }
  }
  onValueChanged: {
    _lastCommitted = ""
    restoreInputs()
  }
  Component.onCompleted: restoreInputs()

  Component {
    id: defaultLabel
    Text {
      color: FoamyPalette.text
      font.family: FoamyStyle.fontFamily
      font.pixelSize: FoamyStyle.font.body
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignLeft
    }
  }
  RowLayout {
    Layout.fillWidth: true
    spacing: FoamyStyle.gap
    Loader {
      id: labelLoader
      Layout.fillWidth: true
      sourceComponent: root.labelComponent
      onLoaded: item.text = Qt.binding(function () {
        return root.label
      })
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
      onTextEdited: root._lastCommitted = ""
      onEditingFinished: root.saveInputs()
      onPasteErrorChanged: if (pasteError !== "")
        root._pasteField = fromInput
      onKeyPressed: function (event) {
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
      onTextEdited: root._lastCommitted = ""
      onEditingFinished: root.saveInputs()
      onPasteErrorChanged: if (pasteError !== "")
        root._pasteField = toInput
      onKeyPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          root.restoreInputs(true)
          event.accepted = true
        }
      }
    }
  }
  Text {
    objectName: "schedulePasteError"
    visible: root._pasteMessage !== ""
    Layout.fillWidth: true
    text: root._pasteMessage
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignLeft
    wrapMode: Text.WordWrap
    color: FoamyPalette.onSurface(FoamyPalette.error)
    font.family: FoamyStyle.fontFamily
    font.pixelSize: FoamyStyle.font.caption
    Accessible.role: Accessible.AlertMessage
    Accessible.name: text
  }
}
