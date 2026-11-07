// Sample inboxes in foamy-zendesk-helper's `fetch` reply format, for the
// preview and the tests only. Fictional people and tickets; the plugin itself
// never shows these.
var BASE = 1793958000000 // 06 Nov 2026, 10:40 (Europe/Oslo)
// The preview's clock (InboxView.fixedNow): when #4821's latest reply came in,
// so #4821 reads "10:40" and #4824 "Yesterday" on any day.
var NOW = BASE

function comment(id, author, minutesAgo, body, extra) {
  return Object.assign({ id: id, author: author, mine: author === "Alex", public: true, created: BASE - minutesAgo * 60000, body: body }, extra || {})
}

function iso(ms) {
  return new Date(ms).toISOString().replace(/\.000Z$/, "Z")
}

function tickets() {
  return [
    { id: "4821", subject: "VPN disconnects after sign-in", status: "Open", priority: "High", assignee: "Alex", mine: true,
      group: "IT support", requester: "Anna", updated_at: iso(BASE),
      comments: [
        comment(48213, "Anna", 0, "The VPN connects successfully, but drops as soon as I open the shared project drive. It happens on both the office Wi-Fi and my phone hotspot.\n\nI have restarted the laptop and signed in again. Other websites work normally while the VPN is disconnected.\n\nThe message is “Your connection was interrupted.” Can you check whether anything has changed for my account?"),
        comment(48212, "Alex", 10, "Could you restart the client and try another network? Please also send the exact error message if it disconnects again."),
        comment(48211, "Anna", 20, "The VPN disconnects when I open the project drive. It started this morning. Could you take a look?"),
        comment(48210, "Alex", 25, "Thanks for reporting it. I'm looking into it now.", { public: false })
      ] },
    { id: "4818", subject: "Access to the project folder", status: "Pending", priority: "Normal", assignee: "Alex", mine: true,
      group: "IT support", requester: "Erik", updated_at: iso(BASE - 6 * 60000),
      comments: [comment(48181, "Erik", 6, "The group membership is correct now. Waiting for the requester to sign out and try again.")] },
    // From yesterday, unassigned in another of the agent's groups.
    { id: "4824", subject: "Meeting room display is blank", status: "New", priority: "Normal", assignee: "Unassigned", mine: false,
      group: "Facilities", requester: "Maria", updated_at: iso(BASE - 26 * 3600000),
      comments: [comment(48241, "Maria", 26 * 60, "The screen stays black when connecting the laptop. We have tried a second cable.")] }
  ]
}

// A new reply from Anna on #4821 (sequence 1, 2, …), or a new unassigned ticket.
function update(sequence, newTicket) {
  var list = tickets()
  if (newTicket) {
    list.unshift({ id: String(4900 + sequence), subject: "Print job stays in the queue", status: "Open", priority: "Normal",
      assignee: "Unassigned", mine: false, group: "IT support", requester: "Jonas", updated_at: iso(BASE + sequence * 60000),
      comments: [comment(49000 + sequence, "Jonas", -sequence, "The printer is available, but the print job stays in the queue. Could you check it?")] })
  } else {
    var vpn = list[0]
    vpn.updated_at = iso(BASE + sequence * 60000)
    vpn.comments.unshift(comment(48213 + sequence, "Anna", -sequence, "Follow-up " + sequence + ": the VPN still disconnects when opening the project drive.\n\nI have tried another network and restarted the client. The problem is unchanged."))
  }
  return list
}

if (typeof module !== "undefined") module.exports = { BASE, NOW, tickets, update }
