// The inbox: the latest snapshot from Zendesk plus read markers kept on this
// computer (Zendesk has no per-agent read state). A ticket is unread while it
// has comments from someone else newer than its marker.

// Tickets waiting on someone else (Pending: the requester; On-hold: a third
// party), with nothing new to read.
var WAITING_STATUSES = ["Pending", "On-hold"]
// Markers of tickets that left the inbox are kept this long (they may return).
var MARKER_DAYS = 30
var MAX_HISTORY = 20

function empty() {
  return { tickets: {}, read: {} };
}

function text(value, limit) {
  return typeof value === "string" ? value.slice(0, limit) : "";
}

// Text the panel shows, at most `limit` UTF-16 units: cut short, it ends in
// "…" (never half a surrogate pair), so a clipped value never looks complete.
function shown(value, limit) {
  if (typeof value !== "string") return "";
  if (value.length <= limit) return value;
  var cut = value.slice(0, limit - 1);
  if (/[\uD800-\uDBFF]$/.test(cut)) cut = cut.slice(0, -1);
  return cut + "\u2026";
}
// The helper clips a comment at 16384 characters (code points, up to two
// UTF-16 units each) plus its own "…": such a body fits whole.
var MAX_BODY = 2 * 16384 + 1

// One ticket from the helper's `fetch` reply, merged with what we had:
// "unchanged"/"deferred" tickets keep their earlier comments.
function ticketFrom(raw, previous) {
  if (!raw || typeof raw !== "object" || !/^[0-9]{1,15}$/.test(String(raw.id))) throw new Error("Invalid ticket");
  var history = previous ? previous.history : [];
  if (Array.isArray(raw.comments)) {
    history = raw.comments.filter(function(comment) {
      return comment && Number.isSafeInteger(comment.id) && Number.isSafeInteger(comment.created);
    }).slice(0, MAX_HISTORY).map(function(comment) {
      return { eventId: raw.id + ":" + comment.id, revision: comment.id, received: comment.created,
               sender: shown(comment.author, 256) || "?", body: shown(comment.body, MAX_BODY),
               mine: comment.mine === true, internal: comment.public === false };
    });
  }
  var latest = history.length ? history[0] : null;
  var updated = Date.parse(raw.updated_at);
  return {
    id: String(raw.id),
    subject: shown(raw.subject, 512) || "(no subject)",
    status: text(raw.status, 32) || "Open",
    priority: text(raw.priority, 32) || "Normal",
    // `unassigned` from the helper, not a name: an agent may be called "Unassigned".
    assignee: shown(raw.assignee, 256),
    unassigned: raw.unassigned === true,
    mine: raw.mine === true,
    group: shown(raw.group, 256),
    requester: shown(raw.requester, 256),
    updatedAt: text(raw.updated_at, 64),
    // Whether `history` holds the comments of this `updatedAt`. A "deferred"
    // ticket keeps its earlier comments but is not loaded, so `known` leaves it
    // out and the next fetch asks for its comments again.
    loaded: Array.isArray(raw.comments) || (raw.unchanged === true && !!previous && previous.loaded),
    history: history,
    revision: latest ? latest.revision : 0,
    received: latest ? latest.received : (isNaN(updated) ? 0 : updated),
    sender: latest ? latest.sender : shown(raw.requester, 256),
    // The latest comment is the agent's own reply.
    senderMine: latest ? latest.mine : false,
    body: latest ? latest.body : ""
  };
}

// Replaces the inbox with a fetch reply's tickets. Read markers of tickets that
// left are kept for MARKER_DAYS, so a ticket that comes back stays read.
function applySnapshot(state, rawTickets, now) {
  if (!Array.isArray(rawTickets)) throw new Error("Invalid inbox");
  var next = {};
  for (var raw of rawTickets.slice(0, 200)) {
    var ticket = ticketFrom(raw, state.tickets[String(raw && raw.id)]);
    next[ticket.id] = ticket;
  }
  state.tickets = next;
  var cutoff = (now || Date.now()) - MARKER_DAYS * 86400000;
  for (var id of Object.keys(state.read)) {
    if (!next[id] && !(state.read[id].at > cutoff)) delete state.read[id];
  }
  return state;
}

// `fetch`'s `known`: tickets whose comments we have at this updated_at.
function known(state) {
  var out = {};
  for (var id of Object.keys(state.tickets)) {
    var ticket = state.tickets[id];
    if (ticket.loaded && ticket.updatedAt) out[id] = ticket.updatedAt;
  }
  return out;
}

function marker(state, id) {
  var entry = state.read[id];
  return entry && Number.isSafeInteger(entry.revision) ? entry.revision : 0;
}

// Comments from someone else that the agent hasn't read.
function unread(state, ticket) {
  var since = marker(state, ticket.id);
  return ticket.history.filter(function(item) { return !item.mine && item.revision > since; }).length;
}

// `placedRead` (see `visible`) keeps a ticket being read where it was.
function waiting(ticket) {
  var read = ticket.placedRead !== undefined ? ticket.placedRead : ticket.read;
  return WAITING_STATUSES.indexOf(ticket.status) >= 0 && read === true;
}

// The inbox's sections, in order: assigned to the agent, unassigned in their
// groups, then (with `groupWaiting`) read tickets waiting on someone else.
var SECTIONS = ["mine", "unassigned", "waiting"]

function section(ticket, groupWaiting) {
  if (groupWaiting && waiting(ticket)) return "waiting";
  return ticket.mine ? "mine" : "unassigned";
}

// Read tickets stay listed unless `hideRead`; `unreadFirst` floats unread ones
// up within their section. `held` ({ id: wasRead }) places tickets being read
// as they were when opened, so reading one never moves or hides it. Each ticket carries its `section`, and the first of
// a section its `sectionHead` (the section, or "" when no header is needed: a
// list of only your own tickets has none) and `sectionSize`.
function visible(state, options) {
  var hideRead = options && options.hideRead, unreadFirst = options && options.unreadFirst;
  var groupWaiting = options && options.groupWaiting;
  var held = options && options.held || {};
  var list = Object.keys(state.tickets).map(function(id) {
    var ticket = state.tickets[id];
    var count = unread(state, ticket);
    var since = marker(state, id);
    var history = ticket.history.map(function(item) {
      return Object.assign({}, item, { fresh: !item.mine && item.revision > since });
    });
    var read = count === 0;
    return Object.assign({}, ticket, { read: read, updates: count, since: since, history: history,
                                       placedRead: Object.prototype.hasOwnProperty.call(held, id) ? held[id] === true : read });
  })
    .filter(function(ticket) { return !hideRead || !ticket.placedRead; });
  for (var ticket of list) ticket.section = section(ticket, groupWaiting);
  list.sort(function(a, b) {
    return SECTIONS.indexOf(a.section) - SECTIONS.indexOf(b.section) || (unreadFirst ? a.placedRead - b.placedRead : 0)
      || b.received - a.received || a.id.localeCompare(b.id);
  });
  var sizes = {};
  for (var item of list) sizes[item.section] = (sizes[item.section] || 0) + 1;
  var several = Object.keys(sizes).length > 1;
  list.forEach(function(item, index) {
    var first = index === 0 || list[index - 1].section !== item.section;
    item.sectionHead = first && (several || item.section !== "mine") ? item.section : "";
    item.sectionSize = sizes[item.section];
  });
  return list;
}

// Desktop notifications: the newest comment from someone else that has been
// seen on each ticket (0: none yet).
function newestFromOthers(ticket) {
  var item = ticket.history.find(function(entry) { return !entry.mine; });
  return item ? item.revision : 0;
}

// What `arrivals` has seen, for one account: `revisions`, the newest comment
// from someone else seen on each ticket, grows across fetches, so a ticket
// that drops out of the search and comes back isn't announced again.
// `pending`: tickets of the first inbox whose comments hadn't come yet (the
// helper fetches at most 25 per run), id → when that inbox came. Their
// comments up to then are old, taken in quietly once they arrive.
function notices() {
  return { started: false, revisions: {}, pending: {} };
}

// What a fetch brings that is worth a notification: unread tickets with a
// comment from someone else newer than any seen before (a ticket new to the
// inbox counts from 0), newest first. The first inbox (`seen.started` false)
// only sets what counts as new. `scope` "mine" keeps only tickets assigned to
// the agent. Updates `seen` (from `notices`); `now`: this inbox's time.
function arrivals(state, seen, scope, now) {
  var first = !seen.started;
  seen.started = true;
  var out = [];
  for (var id of Object.keys(state.tickets)) {
    var ticket = state.tickets[id];
    if (first && !ticket.loaded) seen.pending[id] = now;
    if (Object.prototype.hasOwnProperty.call(seen.pending, id)) {
      // Waiting for its comments, also while it is out of the inbox.
      if (!ticket.loaded) continue;
      var cutoff = seen.pending[id];
      delete seen.pending[id];
      for (var item of ticket.history) {
        if (!item.mine && item.received <= cutoff && item.revision > (seen.revisions[id] || 0)) seen.revisions[id] = item.revision;
      }
    }
    var newest = newestFromOthers(ticket);
    var before = seen.revisions[id] || 0;
    if (newest > before) seen.revisions[id] = newest;
    if (first || newest <= before || unread(state, ticket) === 0 || (scope === "mine" && !ticket.mine)) continue;
    out.push(ticket);
  }
  return out.sort(function(a, b) { return b.received - a.received || a.id.localeCompare(b.id); });
}

// A notification's action carries the account it came from: "<host>/<id>"
// (show) or "<host>/<id>:<revision>[,…]" (the buttons). Ticket ids and read
// markers belong to one Zendesk account (`host`, as `host()` gives it), so an
// action from another account's notification, or one without a host, is
// null and does nothing. Otherwise the tickets, at most 100: [{ id, revision }]
// (revision 0 for show); malformed entries are skipped.
function parseAction(payload, host, withRevision) {
  var value = String(payload || "");
  var slash = value.indexOf("/");
  if (!host || slash < 0 || value.slice(0, slash) !== host) return null;
  var out = [];
  var pattern = withRevision ? /^([0-9]{1,15}):([0-9]{1,16})$/ : /^([0-9]{1,15})$/;
  for (var part of value.slice(slash + 1).split(",").slice(0, 100)) {
    var match = pattern.exec(part.trim());
    if (match) out.push({ id: match[1], revision: withRevision ? Number(match[2]) : 0 });
  }
  return out;
}

// Notification bodies are markup: plain text is escaped, folded to one line
// and cut short. (The shell's JavaScript has no trimEnd.)
function notificationText(value, limit) {
  var text = String(value || "").replace(/\s+/g, " ").trim();
  if (text.length > limit) text = text.slice(0, limit - 1).replace(/ $/, "") + "…";
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Whole calendar days from `ms` to `now` in local time: 0 today, 1 yesterday,
// negative for a time ahead of the clock.
function daysAgo(ms, now) {
  var day = new Date(ms), today = new Date(now);
  var start = function(date) { return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime(); };
  return Math.round((start(today) - start(day)) / 86400000);
}

function markRead(state, id, now) {
  var ticket = state.tickets[id];
  if (!ticket || unread(state, ticket) === 0) return false;
  state.read[id] = { revision: ticket.revision, at: now || Date.now() };
  return true;
}

// A notification's button: read up to the comment it showed, so a reply that
// came in since stays unread. Works for a ticket that has left the inbox too.
function markReadUpTo(state, id, revision, now) {
  if (!/^[0-9]{1,15}$/.test(String(id)) || !Number.isSafeInteger(revision) || revision <= marker(state, id)) return false;
  state.read[id] = { revision: revision, at: now || Date.now() };
  return true;
}

// Makes the newest comment from someone else unread again.
function markUnread(state, id, now) {
  var ticket = state.tickets[id];
  if (!ticket || unread(state, ticket) > 0) return false;
  var newest = ticket.history.find(function(item) { return !item.mine; });
  if (!newest) return false;
  state.read[id] = { revision: newest.revision - 1, at: now || Date.now() };
  return true;
}

// Marks every unread ticket read and returns what `restore` needs to undo it.
function markAllRead(state, now) {
  var batch = [];
  for (var id of Object.keys(state.tickets)) {
    var previous = state.read[id] ? Object.assign({}, state.read[id]) : null;
    if (markRead(state, id, now)) batch.push({ id: id, previous: previous });
  }
  return batch;
}

function restore(state, batch) {
  for (var entry of batch) {
    if (entry.previous) state.read[entry.id] = entry.previous;
    else delete state.read[entry.id];
  }
}

// The read-state file: { version: 1, read: { id: { revision, at } } }.
// At most MAX_MARKERS are kept, the most recently marked: numeric keys
// enumerate in ascending order, so cutting by key order would drop the newest
// tickets, the ones most likely still in the inbox.
var MAX_MARKERS = 2000
function parseReadState(text) {
  var doc = null;
  try { doc = JSON.parse(text || "{}"); } catch (e) { return {}; }
  var source = doc && doc.read && typeof doc.read === "object" ? doc.read : {};
  var valid = Object.keys(source).filter(function(id) {
    var entry = source[id];
    return /^[0-9]{1,15}$/.test(id) && entry && Number.isSafeInteger(entry.revision) && Number.isFinite(entry.at);
  });
  valid.sort(function(a, b) { return source[b].at - source[a].at; });
  var read = {};
  for (var id of valid.slice(0, MAX_MARKERS)) read[id] = { revision: source[id].revision, at: source[id].at };
  return read;
}

function serializeReadState(state) {
  return JSON.stringify({ version: 1, read: state.read }) + "\n";
}

// `acme`, `acme.zendesk.com` or `https://acme.zendesk.com/` → `acme.zendesk.com`.
function host(address) {
  var value = String(address || "").trim().toLowerCase().replace(/^https:\/\//, "").replace(/\/$/, "");
  if (!/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.zendesk\.com)?$/.test(value)) return "";
  return value.endsWith(".zendesk.com") ? value : value + ".zendesk.com";
}

function ticketUrl(address, id) {
  var name = host(address);
  return name && /^[0-9]{1,15}$/.test(String(id)) ? "https://" + name + "/agent/tickets/" + id : "";
}

// What a fetch's exit means for the inbox. `started` is the store's
// generation when the fetch began, `current` its generation now: restart()
// (another account, or signed out) moves it on, and an older fetch's exit,
// stopped (143) or with a full reply that was already on its way, belongs to
// an inbox that is gone. Otherwise the helper's last line: the tickets (and
// the read-state file they go with, and whether the helper's bounds left
// tickets or groups out), or the failed reply (null if none).
function fetchOutcome(started, current, text) {
  if (started !== current) return { stale: true };
  var reply = null;
  try { reply = JSON.parse(String(text).trim().split("\n").pop()); } catch (e) {}
  if (reply && reply.ok && Array.isArray(reply.tickets)) {
    var cut = reply.truncated && typeof reply.truncated === "object" ? reply.truncated : {};
    return { ok: true, tickets: reply.tickets, statePath: typeof reply.state_path === "string" ? reply.state_path : null,
             truncated: { tickets: cut.tickets === true, groups: cut.groups === true } };
  }
  return { ok: false, reply: reply };
}

if (typeof module !== "undefined") module.exports = {
  empty, ticketFrom, applySnapshot, known, unread, waiting, section, visible, daysAgo, markRead, markUnread,
  markReadUpTo, markAllRead, restore, parseReadState, serializeReadState, host, ticketUrl, newestFromOthers, notices,
  arrivals, parseAction, notificationText, fetchOutcome
};
