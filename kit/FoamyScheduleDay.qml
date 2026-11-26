// foamy-kit 0.14.1 6d51889ba3b2b54bbdab1a435aa0bec22ab9a71c7dc664e4b6ded9bc9b850c40 — do not edit; change foamy-kit and run sync
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
// When a save fails without changing `value`, call saveFailed(): the time
// fields show `value` again (a field edited since keeps its draft) and the
// same range can be sent again. With FoamyPrefsQueue, link the row to the
// queue and its key instead (`queue: prefs; queueKey: modelData`): a
// refusal of that key calls saveFailed(), at once when save() refuses the
// range, and later when a refusal or failure of the key names the range
// the row last sent (a queued save refused as it runs). It matches that
// later refusal by its value, so save the range as the row emits it; it
// reads no queue state, unlike FoamyDropdown's link.
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
      _sending = true
      changed(range)
      _sending = false
    }
  }
  // Tell the row its last range was not saved, as FoamyNumberField's
  // saveFailed(): the time fields show `value` again and the same range can
  // be sent again. A time field edited since that range was sent keeps its
  // newer draft.
  function saveFailed() {
    var sent = _lastCommitted !== ""
    _lastCommitted = ""
    if (sent)
      restoreInputs(true)
  }
  // True while changed() for a time range runs.
  property bool _sending: false

  // Optional link to the FoamyPrefsQueue the caller saves through (or any
  // object with its failed(key, value, error) signal) and the key it saves:
  // a refusal of that key for the range the row sent calls saveFailed()
  // itself (see the header).
  property QtObject queue: null
  property string queueKey: ""
  Connections {
    target: root.queue
    ignoreUnknownSignals: true
    function onFailed(key, failedValue) {
      if (root.queueKey === "" || key !== root.queueKey)
        return
      // During changed() it is the range just sent (save() refused it);
      // later, only a refusal of the range this row last sent.
      if (root._sending || String(failedValue) === root._lastCommitted)
        root.saveFailed()
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
