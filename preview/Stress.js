// A realistic, untidy inbox in foamy-zendesk-helper's `fetch` reply format,
// for the UI review only: long subjects and names, every status and priority,
// a long conversation with quoted mail and a signature, internal notes, a
// ticket without comments, Norwegian text and old dates. Fictional people.
var BASE = 1793958000000 // 06 Nov 2026, 10:40 (Europe/Oslo), a Friday
var NOW = BASE
var MIN = 60000
var HOUR = 3600000
var DAY = 86400000

function iso(ms) {
  return new Date(ms).toISOString().replace(/\.000Z$/, "Z")
}

function comment(id, author, agoMs, body, extra) {
  return Object.assign({ id: id, author: author, mine: author === "Alex", public: true, created: BASE - agoMs, body: body }, extra || {})
}

// Read markers the preview sets after loading: { ticket id: comment id read up to }.
// A ticket left out is unread from its first comment.
var READ = {
  "5102": 51020, // two newer comments from Anna are unread
  "5091": 50912,
  "5087": 50871,
  "5080": 50802,
  "5051": 50513,
  "5049": 50491,
  "5012": 50121,
  "4398": 43982,
  "5095": 50951,
  "5077": 50771
}

function tickets() {
  return [
    {
      id: "5102",
      subject: "VPN disconnects after sign-in when the shared project drive is opened from the office network",
      status: "Open", priority: "Urgent", assignee: "Alex", mine: true, group: "IT support",
      requester: "Anna Lindqvist-Johansen", updated_at: iso(BASE),
      comments: [
        comment(51022, "Anna Lindqvist-Johansen", 0, "Hi Alex,\n\nI tried what you suggested. The VPN connects, but it still drops as soon as I open the shared project drive (P:). It happens on the office Wi-Fi, on the cable in meeting room 4 and on my phone hotspot.\n\nWhat I did:\n1. Restarted the laptop\n2. Signed out of the VPN client and in again\n3. Removed the saved profile and added it again from the portal\n4. Tried Erik's laptop with my account: same problem\n\nThe message is “Your connection was interrupted (error 0x800704C9)”. The log file is attached.\n\nThis is blocking the delivery to the customer on Monday, so I would be very grateful if someone could look at it today.\n\nBest regards,\nAnna Lindqvist-Johansen\nSenior Project Manager | Acme Engineering AS\nMobile +47 400 00 000\n\nOn Thu, 5 Nov 2026 at 16:02, Alex <support@acme.example> wrote:\n> Could you restart the client and try another network? Please also send the\n> exact error message if it disconnects again.\n>\n> On Thu, 5 Nov 2026 at 15:40, Anna Lindqvist-Johansen wrote:\n>> The VPN disconnects when I open the project drive. It started this morning."),
        comment(51021, "Anna Lindqvist-Johansen", 4 * MIN, "One more thing: it works when I open the drive through the web portal, only the mapped drive fails."),
        comment(51020, "Alex", 18 * HOUR + 38 * MIN, "Could you restart the client and try another network? Please also send the exact error message if it disconnects again."),
        comment(51019, "Alex", 18 * HOUR + 50 * MIN, "Checked the gateway log: her session is dropped by the idle rule right after an SMB connect. Looks like the split-tunnel change from Tuesday. Asking network.", { public: false }),
        comment(51018, "Anna Lindqvist-Johansen", 19 * HOUR, "The VPN disconnects when I open the project drive. It started this morning. Could you take a look?"),
        comment(51017, "Henrik Dahl", 19 * HOUR + 20 * MIN, "FYI the split-tunnel policy was changed for the Engineering group on Tuesday evening (change CHG-2291).", { public: false }),
        comment(51016, "Alex", 2 * DAY, "Thanks for reporting it. I'm looking into it now."),
        comment(51015, "Anna Lindqvist-Johansen", 2 * DAY + 10 * MIN, "It also happened once last week, but then it worked again after a restart."),
        comment(51014, "Alex", 2 * DAY + 30 * MIN, "Which version of the VPN client do you have? You find it under Help › About."),
        comment(51013, "Anna Lindqvist-Johansen", 2 * DAY + 40 * MIN, "Version 6.4.2 (build 1187)."),
        comment(51012, "Alex", 2 * DAY + HOUR, "Thank you. That is the current version."),
        comment(51011, "Anna Lindqvist-Johansen", 2 * DAY + 2 * HOUR, "Hi, my VPN connection is unstable today.")
      ]
    },
    {
      id: "5098",
      subject: "Re: Fwd: Invoice 2026-1047 — wrong VAT number on the PDF (again)",
      status: "Open", priority: "High", assignee: "Alex", mine: true, group: "Finance systems and payroll",
      requester: "Bjørn-Erik Thorvaldsen", updated_at: iso(BASE - 35 * MIN),
      comments: [
        comment(50983, "Bjørn-Erik Thorvaldsen", 35 * MIN, "The PDF still shows NO 987 654 321 MVA. It must be NO 912 345 678 MVA. See https://erp.acme.example/invoices/2026-1047/preview?layout=standard&lang=nb and compare with invoice 2026-1046, which is correct."),
        comment(50982, "Alex", 3 * HOUR, "The template was updated yesterday. Could you create the PDF again and check?"),
        comment(50981, "Kari Nordmann", 3 * HOUR + 15 * MIN, "Template INV-STD-03 had the old number hard-coded in the footer. Fixed in the template, not yet in the archived layouts.", { public: false }),
        comment(50980, "Bjørn-Erik Thorvaldsen", DAY + 2 * HOUR, "The customer has rejected the invoice because of the VAT number. This is the second time this month.")
      ]
    },
    {
      id: "5075",
      subject: "Printer on the 3rd floor prints blank pages",
      status: "Open", priority: "Low", assignee: "Alex", mine: true, group: "IT support",
      requester: "Lars", updated_at: iso(BASE - 2 * HOUR),
      comments: [comment(50751, "Lars", 2 * HOUR, "Still blank after the new toner.")]
    },
    {
      id: "5066",
      subject: "Password reset",
      status: "Pending", priority: "Normal", assignee: "Alex", mine: true, group: "IT support",
      requester: "Sofie Aas", updated_at: iso(BASE - 50 * MIN),
      comments: [
        comment(50662, "Sofie Aas", 50 * MIN, "I did not get the e-mail with the link. Can you send it again?"),
        comment(50661, "Alex", 4 * HOUR, "I have sent you a reset link.")
      ]
    },
    {
      id: "5091",
      subject: "Laptop replacement",
      status: "Open", priority: "Normal", assignee: "Alex", mine: true, group: "IT support",
      requester: "Maria", updated_at: iso(BASE - 5 * HOUR),
      comments: [
        comment(50913, "Alex", 5 * HOUR, "The new laptop is ordered. I will tell you when it arrives."),
        comment(50912, "Maria", 6 * HOUR, "Yes, 16 inch please.")
      ]
    },
    {
      id: "5049",
      subject: "Shared mailbox faktura@ not receiving external mail",
      status: "Open", priority: "Normal", assignee: "Alex", mine: true, group: "IT support",
      requester: "Kari Nordmann", updated_at: iso(BASE - 3 * DAY),
      comments: [comment(50491, "Kari Nordmann", 3 * DAY, "External senders get a bounce: 550 5.7.1 recipient not authorized.")]
    },
    {
      id: "5012",
      subject: "Request: second monitor",
      status: "Open", priority: "Normal", assignee: "Alex", mine: true, group: "IT support",
      requester: "Erik", updated_at: iso(BASE - 9 * DAY),
      comments: [comment(50121, "Erik", 9 * DAY, "Could I get a second monitor for my desk?")]
    },
    {
      id: "4398",
      subject: "Licence renewal for the CAD software",
      status: "Open", priority: "Normal", assignee: "Alex", mine: true, group: "IT support",
      requester: "Thomas Haugen", updated_at: iso(BASE - 329 * DAY),
      comments: [comment(43982, "Thomas Haugen", 329 * DAY, "The licence expires in January. Who orders the renewal?")]
    },
    {
      id: "5087",
      subject: "Access to the project folder",
      status: "Pending", priority: "Normal", assignee: "Alex", mine: true, group: "IT support",
      requester: "Erik", updated_at: iso(BASE - 6 * MIN),
      comments: [comment(50871, "Erik", 6 * MIN, "The group membership is correct now. Waiting for the requester to sign out and try again.")]
    },
    {
      id: "5080",
      subject: "New starter 1 December: accounts, laptop, phone and door card for Ingrid",
      status: "On-hold", priority: "Normal", assignee: "Alex", mine: true, group: "IT support",
      requester: "Hanne Solberg", updated_at: iso(BASE - DAY - 3 * HOUR),
      comments: [
        comment(50802, "Hanne Solberg", DAY + 3 * HOUR, "The contract is signed. Her manager is Per."),
        comment(50801, "Alex", DAY + 5 * HOUR, "Waiting for the supplier to confirm the phone.")
      ]
    },
    {
      id: "5051",
      subject: "Teams calls drop when the docking station is connected (Dell WD22TB4)",
      status: "On-hold", priority: "High", assignee: "Alex", mine: true, group: "IT support",
      requester: "Per", updated_at: iso(BASE - 4 * DAY),
      comments: [comment(50513, "Per", 4 * DAY, "Dell support has the case. Reference 1789-223-A.")]
    },
    {
      id: "5103",
      subject: "Cannot log in to the time registration system — “Your account is locked”",
      status: "New", priority: "Urgent", assignee: "", unassigned: true, mine: false, group: "IT support",
      requester: "Jonas Bergström", updated_at: iso(BASE - 12 * MIN),
      comments: [comment(51031, "Jonas Bergström", 12 * MIN, "I must register my hours before 12:00 today. The page says my account is locked after too many attempts, but I only tried once.")]
    },
    {
      id: "5090",
      subject: "Guest Wi-Fi vouchers for Friday's customer event (approx. 40 people)",
      status: "New", priority: "High", assignee: "", unassigned: true, mine: false, group: "Customer success — Nordics",
      requester: "Camilla Berg", updated_at: iso(BASE - 30 * MIN)
      // No comments: the helper deferred them (the ticket is not `loaded`).
    },
    {
      id: "5101",
      subject: "Order: 3 × USB-C chargers",
      status: "New", priority: "Low", assignee: "", unassigned: true, mine: false, group: "Procurement",
      requester: "Nina", updated_at: iso(BASE - 3 * HOUR),
      comments: [comment(510101, "Nina", 3 * HOUR, "For the new meeting rooms.")]
    },
    {
      id: "5099",
      subject: "",
      status: "New", priority: "Normal", assignee: "", unassigned: true, mine: false, group: "IT support",
      requester: "noreply@monitoring.acme.example", updated_at: iso(BASE - 5 * HOUR),
      comments: [comment(50991, "noreply@monitoring.acme.example", 5 * HOUR, "ALERT https://monitoring.acme.example/alerts/2f7c9e1b-3d4a-4f6e-9b8c-0a1b2c3d4e5f?source=prometheus&severity=critical&instance=db-prod-03.internal.acme.example%3A9100 DiskSpaceLow /var/lib/postgresql 94% used")]
    },
    {
      id: "5104",
      subject: "Meeting room display is blank",
      status: "New", priority: "Normal", assignee: "", unassigned: true, mine: false, group: "Facilities",
      requester: "Maria", updated_at: iso(BASE - 26 * HOUR),
      comments: [comment(51041, "Maria", 26 * HOUR, "The screen stays black when connecting the laptop. We have tried a second cable.")]
    },
    {
      id: "5095",
      subject: "Kaffemaskinen i 4. etasje lekker vann — kan noen se på den? 🙏",
      status: "Open", priority: "Normal", assignee: "", unassigned: true, mine: false, group: "Facilities",
      requester: "Øyvind Sæther", updated_at: iso(BASE - 2 * DAY),
      comments: [comment(50951, "Øyvind Sæther", 2 * DAY, "Det ligger vann på gulvet hver morgen. Vi har satt en bøtte under.")]
    },
    {
      id: "5077",
      subject: "Door card stopped working",
      status: "Open", priority: "Normal", assignee: "", unassigned: true, mine: false, group: "Facilities",
      requester: "Ole", updated_at: iso(BASE - 6 * DAY),
      comments: [comment(50771, "Ole", 6 * DAY, "It works on the main door but not on the 2nd floor.")]
    }
  ]
}

if (typeof module !== "undefined") module.exports = { BASE, NOW, READ, tickets }
