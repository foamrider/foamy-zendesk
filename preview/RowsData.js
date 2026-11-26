// Extra sample tickets for the rows prototype states (the helper's `fetch` reply format,
// as preview/Stress.js). READ: read markers, { ticket id: comment id read up to }.
// They are what the realistic inbox has none of: a newest comment that is not
// the requester's, a parked Urgent ticket, and a read ticket whose comments
// haven't loaded. Fictional people.
var BASE = 1793958000000 // as preview/Stress.js: 06 Nov 2026, 10:40 (Europe/Oslo)
var MIN = 60000
var HOUR = 3600000

function iso(ms) {
  return new Date(ms).toISOString().replace(/\.000Z$/, "Z")
}

function comment(id, author, agoMs, body, extra) {
  return Object.assign({ id: id, author: author, mine: author === "Alex", public: true, created: BASE - agoMs, body: body }, extra || {})
}

var READ = {
  "5112": 51121, // the requester's comment is read; the agent answered after it
  "5113": 51130 // read before; its newer comments haven't loaded
}

function tickets() {
  return [
    {
      // The agent answered in Zendesk; the requester's comment before it was never read here.
      id: "5111",
      subject: "Scanner sends no e-mail after the mail server change",
      status: "Open", priority: "Normal", assignee: "Alex", mine: true, group: "IT support",
      requester: "Maria Olsen", updated_at: iso(BASE - 2 * MIN),
      comments: [
        comment(51112, "Alex", 2 * MIN, "Hi Maria,\n\nI have changed the SMTP relay on the scanner to the new server. Could you scan one page to yourself and tell me if it arrives?\n\nBest regards,\nAlex"),
        comment(51111, "Maria Olsen", 2 * HOUR, "The scanner on the 2nd floor says “Send failed” since Monday.")
      ]
    },
    {
      // A colleague's internal note is the newest comment.
      id: "5110",
      subject: "Payroll export fails for October",
      status: "Open", priority: "High", assignee: "Alex", mine: true, group: "Finance systems and payroll",
      requester: "Ingrid Moe", updated_at: iso(BASE - 3 * MIN),
      comments: [
        comment(51102, "Kari Nordmann", 3 * MIN, "Not our system. Ask the vendor before you answer: the customer has an open escalation with them (see https://vendor.example/cases/88213).", { public: false }),
        comment(51101, "Ingrid Moe", HOUR, "Hi,\n\nThe export to the bank stops with “Format error in line 214”. Can you look at it before the pay run on Thursday?")
      ]
    },
    {
      // Read, Urgent, and the agent wrote last: parked.
      id: "5112",
      subject: "Card terminal in the canteen is offline",
      status: "Open", priority: "Urgent", assignee: "Alex", mine: true, group: "IT support",
      requester: "Tore Lund", updated_at: iso(BASE - 20 * MIN),
      comments: [
        comment(51122, "Alex", 20 * MIN, "The supplier sends a technician at 12:00. I will confirm when it works again."),
        comment(51121, "Tore Lund", 40 * MIN, "The terminal shows “No connection” since 09:30.")
      ]
    },
    {
      // Read earlier; changed since, and the helper has not sent its comments yet.
      id: "5113",
      subject: "Projector in room 2 flickers",
      status: "Open", priority: "Normal", assignee: "Alex", mine: true, group: "Facilities",
      requester: "Liv", updated_at: iso(BASE - 25 * MIN)
    }
  ]
}

// A ticket the helper never sends today (it asks for the agent's own and the
// unassigned ones): assigned to a colleague. The row names the assignee.
function assignedElsewhere() {
  return [
    {
      id: "5114",
      subject: "Badge printer needs a new ribbon",
      status: "Open", priority: "Normal", assignee: "Kari Nordmann", mine: false, unassigned: false, group: "Facilities",
      requester: "Jon Vik", updated_at: iso(BASE - 8 * MIN),
      comments: [comment(51141, "Jon Vik", 8 * MIN, "The print is faint on every badge since yesterday.")]
    }
  ]
}

// ---- Stage 2: the open card ---------------------------------------------------
// Tickets the realistic inbox has none of: long author names (26 and 45
// characters) with both byline labels, an own reply above a long unread
// comment and a long internal note, a ticket whose newer comments haven't
// loaded (`deferred`), and one without comments.
var DAY = 24 * HOUR
var LONG_NAME = "Alexandra Wilhelmina Bjørnstad-Christoffersen" // 45 characters
var NOTE_NAME = "Henrik Dahl-Christoffersen" // 26 characters

var OPEN_READ = {
  "5120": 51202, // an internal note and a reply are unread
  "5121": 51211, // a long comment and a long internal note are unread; the agent wrote last
  "5122": 51222
}

function openCard() {
  return [
    {
      id: "5120",
      subject: "Access for the external auditors to the shared finance folder (read-only, until 31 January)",
      status: "Open", priority: "High", assignee: "Alex", mine: true, group: "Finance systems and payroll",
      requester: LONG_NAME, updated_at: iso(BASE - 3 * MIN),
      comments: [
        comment(51205, LONG_NAME, 3 * MIN, "Thank you. Three people need access from Monday 9 November: two from our team and one from the audit firm. I have attached the list with their e-mail addresses.\n\nCould you confirm today? The auditors plan their week on Friday afternoon."),
        comment(51204, NOTE_NAME, 17 * HOUR + 55 * MIN, "The CFO approved this in #5088. Read-only is enough: do not add them to the Finance group, use the guest group with the expiry date.", { public: false }),
        comment(51203, "Alex", 18 * HOUR + 38 * MIN, "Hi Alexandra,\n\nI can set that up. Who needs access, and from which date?"),
        comment(51202, NOTE_NAME, 19 * HOUR + 20 * MIN, "External accounts need the CFO's approval first. I have asked for it.", { public: false }),
        comment(51201, LONG_NAME, 19 * HOUR + 35 * MIN, "Hello,\n\nThe external auditors start on Monday. They need to read the 2026 folders on the finance share. Can you arrange that?")
      ]
    },
    {
      id: "5121",
      subject: "Wi-Fi drops in meeting rooms 3 and 4 during video calls",
      status: "Open", priority: "Normal", assignee: "Alex", mine: true, group: "IT support",
      requester: "Silje Nygård", updated_at: iso(BASE - MIN),
      comments: [
        comment(51214, "Alex", MIN, "I have asked the network team to look at the access points on the 2nd floor. I will come back to you before 12:00."),
        comment(51213, "Silje Nygård", 30 * MIN, "Hi Alex,\n\nIt happened again in the board meeting this morning. Here is what we saw:\n\n09:02 The call starts in room 4, everything is fine\n09:10 Picture freezes for the people in the room, sound continues\n09:11 Two laptops lose the Wi-Fi completely and connect again after about 30 seconds\n09:25 The same thing again, this time also the room system\n09:40 We moved to room 2 and had no more problems\n\nThe laptops are on “Acme-Office”, the room system is on the cable. Nobody was downloading anything large as far as I know.\n\nIt has now happened in four meetings this week, always in room 3 or 4 and always between 09:00 and 10:00. The board meets again on Thursday at 09:00, so it would be good to have it fixed, or at least to know which room we should use.\n\nBest regards,\nSilje"),
        comment(51212, "Kari Nordmann", 50 * MIN, "Checked the controller. Both rooms hang on AP-2F-07, which also serves the open office and has 60 to 70 clients every morning.\nChannel utilisation on 5 GHz is above 80 % between 09:00 and 10:00.\nAP-2F-08 next to room 4 has been down since the power work on Monday: nobody turned its switch port on again.\nI can enable the port, but the change window is tonight.\nUntil then they should use room 2, which is on AP-2F-03.\nDo not promise a fix before Thursday: the vendor has to confirm the firmware first.\nThe case with the vendor is 00481927.", { public: false }),
        comment(51211, "Silje Nygård", 2 * HOUR, "The Wi-Fi in meeting room 4 dropped twice during a video call today.")
      ]
    },
    {
      // Its newer comments haven't loaded: see `deferred`.
      id: "5122",
      subject: "Label printer in the warehouse prints offset labels",
      status: "Open", priority: "Normal", assignee: "Alex", mine: true, group: "IT support",
      requester: "Geir Hansen", updated_at: iso(BASE - DAY - 2 * HOUR),
      comments: [
        comment(51222, "Geir Hansen", DAY + 2 * HOUR, "The labels are printed about 5 mm too far to the left since we changed the roll."),
        comment(51221, "Alex", DAY + 3 * HOUR, "Which label size is on the new roll?")
      ]
    },
    {
      // The helper sent it with an empty comment list.
      id: "5123",
      subject: "Old intranet link on the start page",
      status: "Open", priority: "Low", assignee: "Alex", mine: true, group: "IT support",
      requester: "Trine Lie", updated_at: iso(BASE - 3 * DAY),
      comments: []
    }
  ]
}

// The same ticket as the next fetch sends it when it changed and the helper
// put its comments off: no comment list, a new `updated_at`.
function deferred(ticket) {
  var copy = Object.assign({}, ticket)
  delete copy.comments
  copy.updated_at = iso(BASE - 4 * MIN)
  return copy
}

if (typeof module !== "undefined") module.exports = { READ, OPEN_READ, tickets, assignedElsewhere, openCard, deferred }
