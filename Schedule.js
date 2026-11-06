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

if(typeof module!=="undefined")module.exports={validRange:validRange,week:week,withinWeek:withinWeek}
