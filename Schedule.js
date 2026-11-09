// Copied from foamy-train/Schedule.js; keep the two in step until it moves into foamy-kit.
var dayKeys = ["scheduleMonday", "scheduleTuesday", "scheduleWednesday",
  "scheduleThursday", "scheduleFriday", "scheduleSaturday", "scheduleSunday"]

function minutes(time, allowMidnightEnd) {
  if (allowMidnightEnd && time === "24:00") return 1440
  if (typeof time !== "string" || !/^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/.test(time)) return -1
  return Number(time.slice(0, 2)) * 60 + Number(time.slice(3))
}

function validRange(value) {
  if (typeof value !== "string") return false
  if (value === "") return true
  var parts = value.split("-")
  return parts.length === 2 && minutes(parts[0], false) >= 0 && minutes(parts[1], true) >= 0
}

function dayRange(settings,index) { var value=settings[dayKeys[index]];return validRange(value)?value:"" }

function week(settings) {
  return dayKeys.map(function(key, index) { return dayRange(settings, index) })
}

function withinWeek(date, enabled, ranges) {
  if (!enabled) return true
  var day = (date.getDay() + 6) % 7
  var now = date.getHours() * 60 + date.getMinutes()
  var today = ranges[day]
  if (validRange(today) && today !== "") {
    var parts = today.split("-")
    var start = minutes(parts[0], false), stop = minutes(parts[1], true)
    if (start === stop || (start < stop ? now >= start && now < stop : now >= start)) return true
  }
  // The previous day's overnight period can continue into an otherwise off day.
  var previous = ranges[(day + 6) % 7]
  if (!validRange(previous) || previous === "") return false
  var previousParts = previous.split("-")
  var previousStart = minutes(previousParts[0], false), previousStop = minutes(previousParts[1], true)
  return previousStart > previousStop && now < previousStop
}

// A snooze, or a resume outside the schedule, set from the popup: { on, until }
// (until in ms). It overrides the schedule until `until` and lives in a state
// file, never in shell.json.
function validOverride(value) {
  return !!value && typeof value.on === "boolean" && typeof value.until === "number" && isFinite(value.until)
}

function effective(date, enabled, ranges, override) {
  if (validOverride(override) && date.getTime() < override.until) return override.on
  return withinWeek(date, enabled, ranges)
}

function nextMidnight(date) {
  var next = new Date(date.getTime())
  next.setHours(24, 0, 0, 0)
  return next.getTime()
}

// The first whole minute within 24 hours at which the schedule itself reads
// `on`, or -1.
function nextScheduled(date, enabled, ranges, on) {
  var start = Math.floor(date.getTime() / 60000) * 60000
  for (var minute = 1; minute <= 1440; minute++) {
    var at = new Date(start + minute * 60000)
    if (withinWeek(at, enabled, ranges) === on) return at.getTime()
  }
  return -1
}

// The override after pressing the snooze button: it flips what is in force
// now. Back to what the schedule says, there is none. A snooze lasts until the
// scheduled hours end (an overnight range runs on past midnight), else until
// midnight; resuming lasts until midnight, or until the schedule starts if
// that comes first.
function toggled(date, enabled, ranges, override) {
  var on = !effective(date, enabled, ranges, override)
  if (on === withinWeek(date, enabled, ranges)) return null
  var midnight = nextMidnight(date)
  var agrees = nextScheduled(date, enabled, ranges, on)
  if (agrees < 0) return { on: on, until: midnight }
  return { on: on, until: on ? Math.min(agrees, midnight) : agrees }
}

// The state file: {"version":1,"override":{…}|null}. Expired or invalid: none.
function parseOverride(text, now) {
  try {
    var value = JSON.parse(text).override
    return validOverride(value) && now < value.until ? { on: value.on, until: value.until } : null
  } catch (error) {
    return null
  }
}

function serializeOverride(override) {
  return JSON.stringify({ version: 1, override: validOverride(override) ? override : null }) + "\n"
}

if(typeof module!=="undefined")module.exports={validRange:validRange,week:week,withinWeek:withinWeek,effective:effective,toggled:toggled,parseOverride:parseOverride,serializeOverride:serializeOverride}
