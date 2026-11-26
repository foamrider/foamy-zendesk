// Extra sample data for the shell prototype states (the helper's `fetch` reply format,
// as preview/Stress.js). READ: read markers, { ticket id: comment id read up to }.
var READ = {}

function tickets() {
  return []
}

function iso(ms) {
  return new Date(ms).toISOString().replace(/\.000Z$/, "Z")
}

// The realistic inbox (Stress.tickets()) one fetch later: a new reply on
// #5102 and a new unassigned ticket. `base` is Stress.BASE.
function updated(list, base) {
  var out = list.slice()
  for (var i = 0; i < out.length; i++) {
    if (out[i].id !== "5102")
      continue
    out[i].updated_at = iso(base + 60000)
    out[i].comments.unshift({ id: 51023, author: "Anna Lindqvist-Johansen", mine: false, public: true, created: base + 60000,
      body: "It just happened again, this time on the guest network." })
  }
  out.unshift({ id: "5105", subject: "Badge reader at the main entrance is offline", status: "New", priority: "Urgent",
    assignee: "", unassigned: true, mine: false, group: "Facilities", requester: "Reception", updated_at: iso(base + 120000),
    comments: [{ id: 51051, author: "Reception", mine: false, public: true, created: base + 120000,
      body: "Nobody can badge in at the main entrance. The reader shows a red light." }] })
  return out
}

// Catalog keys of the error texts the states show. KEYRING_SAVE is the
// helper's longest sign-in error (its %1 is the keyring's own message).
var KEYRING_SAVE = "The renewed Zendesk sign-in couldn't be saved in the keyring (%1). Sign in again."
var KEYRING_REASON = "No space left on device"
var NO_READ_ACCESS = "Zendesk didn't allow this request. The OAuth client needs read access."
var OFFLINE = "Can't reach Zendesk. Check your connection."
