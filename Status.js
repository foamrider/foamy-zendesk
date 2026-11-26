// Zendesk's own status colours, as its agent workspace shows them in a dark
// and a light UI, so a status reads the same here as in Zendesk. They are
// brand colours, not theme colours. Closed is grey like Solved.
var NAMES = ["New", "Open", "Pending", "On-hold", "Solved", "Closed"]
var DARK = ["#e38215", "#eb5c69", "#2694d6", "#f8f9f9", "#b0b8be", "#b0b8be"] // foamy-lint: allow hex-colour — Zendesk status colours (dark UI)
var LIGHT = ["#ffa142", "#cc3340", "#1f73b7", "#23272b", "#87929d", "#87929d"] // foamy-lint: allow hex-colour — Zendesk status colours (light UI)

// The helper maps an unknown status to Open; this does the same for a
// stored one.
function color(status, lightTheme) {
  var index = NAMES.indexOf(status)
  return (lightTheme ? LIGHT : DARK)[index < 0 ? 1 : index]
}

// WCAG relative luminance on linearised sRGB: FoamyPalette.luminance()
// weighs gamma-encoded channels, which picks dark text on Open and Pending
// in light themes where light text reads better.
function linear(channel) {
  return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
}
function luminance(c) {
  return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
}
function contrast(a, b) {
  var la = luminance(a) + 0.05
  var lb = luminance(b) + 0.05
  return Math.max(la, lb) / Math.min(la, lb)
}
// `a` moved toward `b` by `share` (0 to 1), as plain { r, g, b }.
function mix(a, b, share) {
  return { r: a.r + (b.r - a.r) * share, g: a.g + (b.g - a.g) * share, b: a.b + (b.b - a.b) * share }
}

// Text on a solid status tag: of the two candidates (the popup's text and
// background colours), the one that contrasts more with the fill.
function inkOn(fill, first, second) {
  return contrast(fill, first) >= contrast(fill, second) ? first : second
}

// Text on a soft status tag (the status colour at `alpha` over the popup
// background): the status colour itself, lightened in a dark theme or darkened
// in a light one, in steps, until it reads on the tag (WCAG 4.5:1). Moving
// toward white or black keeps the hue, so Open stays red and New orange.
function softInk(fill, text, background, alpha) {
  var surface = mix(background, fill, alpha)
  var end = luminance(text) > luminance(background) ? { r: 1, g: 1, b: 1 } : { r: 0, g: 0, b: 0 }
  for (var step = 0; step <= 10; step++) {
    var ink = mix(fill, end, step / 10)
    if (contrast(ink, surface) >= 4.5) return Qt.rgba(ink.r, ink.g, ink.b, 1)
  }
  return text
}
