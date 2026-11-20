import QtQuick
import "kit"
import "Status.js" as Status

// A soft pill in `tone` (the priority), or with `status` a solid tag in
// Zendesk's colour for that status, lettered in whichever of the popup's
// text and background colours reads better on it.
Rectangle {
  id: label
  required property string text
  property string status: ""
  property color tone: status !== "" ? Status.color(status, FoamyPalette.lightTheme) : FoamyPalette.secondaryText
  readonly property bool solid: status !== ""
  readonly property color ink: solid ? Status.inkOn(tone, FoamyPalette.text, FoamyPalette.background) : tone
  implicitWidth: caption.implicitWidth + FoamyStyle.gap * 2
  implicitHeight: caption.implicitHeight + FoamyStyle.gapSmall * 2
  radius: solid ? FoamyStyle.radiusSmall : FoamyStyle.pillRadius(height)
  color: solid ? tone : Qt.alpha(tone, 0.10)
  PlainText {
    id: caption
    anchors.centerIn: parent
    text: label.text
    color: label.ink
    font.pixelSize: FoamyStyle.font.bodySmall
    font.weight: label.solid ? Font.DemiBold : Font.Normal
    wrapMode: Text.NoWrap
  }
}
