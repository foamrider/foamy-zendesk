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
  return typeof value === "string" ? value.slice(0, limit || 16384) : "";
}

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
               sender: text(comment.author, 256) || "?", body: text(comment.body),
               mine: comment.mine === true, internal: comment.public === false };
    });
  }
  var latest = history.length ? history[0] : null;
  var updated = Date.parse(raw.updated_at);
  return {
    id: String(raw.id),
    subject: text(raw.subject, 512) || "(no subject)",
    status: text(raw.status, 32) || "Open",
    priority: text(raw.priority, 32) || "Normal",
    assignee: text(raw.assignee, 256) || "Unassigned",
    mine: raw.mine === true,
    group: text(raw.group, 256),
    requester: text(raw.requester, 256),
    updatedAt: text(raw.updated_at, 64),
    // Comments not fetched yet: ask for them again next time.
    loaded: Array.isArray(raw.comments) || (!!previous && previous.loaded),
    history: history,
    revision: latest ? latest.revision : 0,
    received: latest ? latest.received : (isNaN(updated) ? 0 : updated),
    sender: latest ? latest.sender : text(raw.requester, 256),
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
// seen on each ticket (0: none yet). `seen` grows across fetches, so a ticket
// that drops out of the search and comes back isn't announced again.
function newestFromOthers(ticket) {
  var item = ticket.history.find(function(entry) { return !entry.mine; });
  return item ? item.revision : 0;
}

// What a fetch brings that is worth a notification: unread tickets with a
// comment from someone else newer than any seen before (a ticket new to the
// inbox counts from 0), newest first. `scope` "mine" keeps only tickets
// assigned to the agent. Updates `seen`.
function arrivals(state, seen, scope) {
  var out = [];
  for (var id of Object.keys(state.tickets)) {
    var ticket = state.tickets[id];
    var newest = newestFromOthers(ticket);
    var before = seen[id] || 0;
    if (newest > before) seen[id] = newest;
    if (newest <= before || unread(state, ticket) === 0 || (scope === "mine" && !ticket.mine)) continue;
    out.push(ticket);
  }
  return out.sort(function(a, b) { return b.received - a.received || a.id.localeCompare(b.id); });
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
function parseReadState(text) {
  var doc = null;
  try { doc = JSON.parse(text || "{}"); } catch (e) { return {}; }
  var read = {};
  var source = doc && doc.read && typeof doc.read === "object" ? doc.read : {};
  for (var id of Object.keys(source).slice(0, 2000)) {
    var entry = source[id];
    if (/^[0-9]{1,15}$/.test(id) && entry && Number.isSafeInteger(entry.revision) && Number.isFinite(entry.at))
      read[id] = { revision: entry.revision, at: entry.at };
  }
  return read;
}

function serializeReadState(state) {
  return JSON.stringify({ version: 1, read: state.read }) + "\n";
}

// `acme`, `acme.zendesk.com` or `https://acme.zendesk.com/` → `acme.zendesk.com`.
function host(address) {
  var value = String(address || "").trim().toLowerCase().replace(/^https:\/\//, "").replace(/\/$/, "");
  if (!/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.zendesk\.com)?$/.test(value)) return "";
  return /\.zendesk\.com$/.test(value) ? value : value + ".zendesk.com";
}

function ticketUrl(address, id) {
  var name = host(address);
  return name && /^[0-9]{1,15}$/.test(String(id)) ? "https://" + name + "/agent/tickets/" + id : "";
}

if (typeof module !== "undefined") module.exports = {
  empty, ticketFrom, applySnapshot, known, unread, waiting, section, visible, daysAgo, markRead, markUnread,
  markAllRead, restore, parseReadState, serializeReadState, host, ticketUrl, newestFromOthers, arrivals,
  notificationText
};
