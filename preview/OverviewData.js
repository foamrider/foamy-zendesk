// Extra sample tickets for the overview prototype states (the helper's `fetch` reply format,
// as preview/Stress.js). READ: read markers, { ticket id: comment id read up to }.
var BASE = 1793958000000 // 06 Nov 2026, 10:40 (Europe/Oslo), as Stress.js and Fixtures.js
var MIN = 60000
var HOUR = 3600000
var DAY = 86400000

function iso(ms) {
  return new Date(ms).toISOString().replace(/\.000Z$/, "Z")
}

function comment(id, author, agoMs, body, extra) {
  return Object.assign({ id: id, author: author, mine: author === "Alex", public: true, created: BASE - agoMs, body: body }, extra || {})
}

// #5110 was read yesterday and #5112 is answered; the others are unread.
var READ = {
  "5110": 51101,
  "5112": 51121
}

// A group name far longer than half the overview's width.
var LONG_GROUP = "People operations, onboarding and workplace services for the Nordic and Baltic offices"

// Added to the realistic inbox: tickets that are late (Urgent or High, an
// hour or more without a reply), one that is Urgent but read, groups with a
// very long name, and enough groups to pass the five the overview shows.
function tickets() {
  return [
    {
      id: "5108",
      subject: "Payroll run failed for 214 employees — “Bank file rejected (ISO 20022 pain.001, line 3)”",
      status: "Open", priority: "Urgent", assignee: "Alex", mine: true, group: "Finance systems and payroll",
      requester: "Ingeborg Kristoffersen-Aamodt", updated_at: iso(BASE - 3 * HOUR - 10 * MIN),
      comments: [
        comment(51082, "Ingeborg Kristoffersen-Aamodt", 3 * HOUR + 10 * MIN, "The bank rejected the file again.\n\nSalaries must be paid tomorrow. Can someone look at this before 14:00?"),
        comment(51081, "Alex", 4 * HOUR, "I have asked the bank what line 3 refers to.")
      ]
    },
    {
      id: "5110",
      subject: "Reception phone has no dial tone",
      status: "Open", priority: "Urgent", assignee: "Alex", mine: true, group: "IT support",
      requester: "Hanne Solberg", updated_at: iso(BASE - DAY - 2 * HOUR),
      comments: [comment(51101, "Hanne Solberg", DAY + 2 * HOUR, "Still dead this morning. We forward the calls to a mobile for now.")]
    },
    {
      id: "5106",
      subject: "Badge printer offline before Monday's onboarding",
      status: "New", priority: "High", assignee: "", unassigned: true, mine: false, group: LONG_GROUP,
      requester: "Marte", updated_at: iso(BASE - 2 * DAY - 4 * HOUR),
      comments: [comment(51061, "Marte", 2 * DAY + 4 * HOUR, "Twelve new colleagues start on Monday and need badges.")]
    },
    {
      id: "5111",
      subject: "Welcome packs: 12 laptop bags and headsets",
      status: "New", priority: "Normal", assignee: "", unassigned: true, mine: false, group: LONG_GROUP,
      requester: "Marte", updated_at: iso(BASE - 90 * MIN),
      comments: [comment(51111, "Marte", 90 * MIN, "Could you order these for Monday?")]
    },
    {
      id: "5112",
      subject: "Desk move for the Riga team",
      status: "Open", priority: "Normal", assignee: "Alex", mine: true, group: LONG_GROUP,
      requester: "Ilze Kalniņa-Bērziņa", updated_at: iso(BASE - 3 * DAY),
      comments: [
        comment(51122, "Alex", 3 * DAY, "The movers are booked for week 47."),
        comment(51121, "Ilze Kalniņa-Bērziņa", 3 * DAY + HOUR, "When can we move?")
      ]
    },
    {
      id: "5107",
      subject: "Forklift charger error E-17",
      status: "New", priority: "High", assignee: "", unassigned: true, mine: false, group: "Warehouse",
      requester: "Stian", updated_at: iso(BASE - 48 * MIN),
      comments: [comment(51071, "Stian", 48 * MIN, "The charger in bay 2 shows E-17 and will not start.")]
    },
    {
      id: "5109",
      subject: "Label printer prints half the barcode",
      status: "Open", priority: "Normal", assignee: "", unassigned: true, mine: false, group: "Warehouse",
      requester: "Stian", updated_at: iso(BASE - 7 * HOUR),
      comments: [comment(51091, "Stian", 7 * HOUR, "Only the left half of the barcode is printed.")]
    },
    {
      id: "5105",
      subject: "Projector lamp in the auditorium",
      status: "New", priority: "Low", assignee: "", unassigned: true, mine: false, group: "Audio and video",
      requester: "Nina", updated_at: iso(BASE - 4 * DAY),
      comments: [comment(51051, "Nina", 4 * DAY, "The picture is very dim.")]
    }
  ]
}

// The tidy inbox, answered: the agent wrote last on the open ticket, the
// others wait on someone else. Nothing needs a reply.
function answered() {
  return [
    { id: "4821", subject: "VPN disconnects after sign-in", status: "Open", priority: "High", assignee: "Alex", mine: true,
      group: "IT support", requester: "Anna", updated_at: iso(BASE - 10 * MIN),
      comments: [
        comment(48212, "Alex", 10 * MIN, "Could you restart the client and try another network?"),
        comment(48211, "Anna", 20 * MIN, "The VPN disconnects when I open the project drive.")
      ] },
    { id: "4818", subject: "Access to the project folder", status: "Pending", priority: "Normal", assignee: "Alex", mine: true,
      group: "IT support", requester: "Erik", updated_at: iso(BASE - 6 * MIN),
      comments: [comment(48181, "Erik", 6 * MIN, "The group membership is correct now.")] }
  ]
}

// One open ticket whose comments the helper deferred: it may need a reply.
function unknown() {
  return [
    { id: "4830", subject: "Guest Wi-Fi vouchers for Friday's customer event", status: "New", priority: "High", assignee: "",
      unassigned: true, mine: false, group: "Facilities", requester: "Camilla Berg", updated_at: iso(BASE - 30 * MIN) },
    { id: "4818", subject: "Access to the project folder", status: "Pending", priority: "Normal", assignee: "Alex", mine: true,
      group: "IT support", requester: "Erik", updated_at: iso(BASE - 6 * MIN),
      comments: [comment(48181, "Erik", 6 * MIN, "The group membership is correct now.")] }
  ]
}

if (typeof module !== "undefined") module.exports = { READ, tickets, answered, unknown }
