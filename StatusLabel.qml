import QtQuick
import "kit"
import "Status.js" as Status

// A soft pill in `tone` (the priority), or with `status` a tag in Zendesk's
// colour for that status: solid in a ticket's own header, lettered in
// whichever of the popup's text and background colours reads better on it,
// or `soft` in a list (a tint with the word in a readable shade of the same
// colour), where a column of solid tags would outshout the subjects.
// `strong` makes the pill solid in `tone` (the Urgent priority).
Rectangle {
  id: label
  required property string text
  property string status: ""
  property bool soft: false
  property bool strong: false
  // What a soft tag lies on (a row's tint, a filled row): its ink is chosen against it.
  property color surface: FoamyPalette.background
  property color tone: status !== "" ? Status.color(status, FoamyPalette.lightTheme) : FoamyPalette.secondaryText
  readonly property bool tag: status !== ""
  readonly property bool solid: (tag && !soft) || strong
  readonly property real softAlpha: 0.16
  readonly property color ink: solid ? Status.inkOn(tone, FoamyPalette.text, FoamyPalette.background) : tag ? Status.softInk(tone, FoamyPalette.text, surface, softAlpha) : tone
  implicitWidth: caption.implicitWidth + FoamyStyle.gap * 2
  implicitHeight: caption.implicitHeight + FoamyStyle.gapSmall * 2
  // A tag has corners, a priority pill is round: the two never look alike.
  radius: tag ? FoamyStyle.radiusSmall : FoamyStyle.pillRadius(height)
  color: solid ? tone : Qt.alpha(tone, tag ? softAlpha : 0.10)
  PlainText {
    id: caption
    anchors.centerIn: parent
    text: label.text
    color: label.ink
    font.pixelSize: FoamyStyle.font.bodySmall
    font.weight: label.tag || label.strong ? Font.DemiBold : Font.Normal
    wrapMode: Text.NoWrap
  }
}
