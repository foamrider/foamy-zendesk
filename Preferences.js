// Inline settings schema for foamy.zendesk (mirrors manifest.json barWidget.schema).
// Validation and saving live in kit/FoamyPrefs.js; the schedule keys are kit/FoamySchedule.js's.
var schedulePattern = "^$|^(?:[01][0-9]|2[0-3]):[0-5][0-9]-(?:(?:[01][0-9]|2[0-3]):[0-5][0-9]|24:00)$"
var dayKeys = ["scheduleMonday", "scheduleTuesday", "scheduleWednesday", "scheduleThursday", "scheduleFriday", "scheduleSaturday", "scheduleSunday"]
// `acme`, `acme.zendesk.com` or `https://acme.zendesk.com/`; the helper normalizes it.
var addressPattern = "^$|^(https://)?[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?([.]zendesk[.]com)?/?$"
var defaultPort = 47823
var refreshChoices = [60, 120, 300, 600, 900]
var dayLabels = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

var fields = [
  { key: "hideRead", type: "boolean", defaultValue: false },
  { key: "unreadFirst", type: "boolean", defaultValue: false },
  { key: "groupWaiting", type: "boolean", defaultValue: true },
  // Desktop notifications for new replies and tickets: off, "mine" (assigned
  // to you) or "all" (also unassigned in your groups).
  { key: "notify", type: "enum", options: ["off", "mine", "all"], defaultValue: "off" },
  { key: "scheduleEnabled", type: "boolean", defaultValue: false },
  { key: "scheduleOutsideMode", type: "enum", options: ["mute", "hide"], defaultValue: "mute" }
].concat(dayKeys.map(function(key) {
  return { key: key, type: "string", defaultValue: "", maxLength: 11, pattern: schedulePattern }
})).concat([
  // Zendesk connection. Nothing secret: the OAuth tokens live in the keyring.
  { key: "zendeskAddress", type: "string", defaultValue: "", maxLength: 100, pattern: addressPattern },
  { key: "oauthClientId", type: "string", defaultValue: "", maxLength: 128, pattern: "^$|^[A-Za-z0-9_.-]{1,128}$" },
  // Empty: the default port. It must match the OAuth client's redirect URL.
  { key: "oauthPort", type: "string", defaultValue: "", maxLength: 5, pattern: "^$|^[0-9]{4,5}$" },
  { key: "refreshSeconds", type: "integer", defaultValue: 60, min: 60, max: 900, step: 60 }
])

if (typeof module !== "undefined") module.exports = { fields: fields, dayKeys: dayKeys, dayLabels: dayLabels, schedulePattern: schedulePattern, addressPattern: addressPattern, defaultPort: defaultPort, refreshChoices: refreshChoices }
