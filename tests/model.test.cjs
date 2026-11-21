const test = require('node:test');
const assert = require('node:assert/strict');
const Model = require('../Model.js');
const Fixtures = require('../preview/Fixtures.js');
// Compare objects as plain data (drops undefined fields).
const plain = value => JSON.parse(JSON.stringify(value));
const Schema = require('../Preferences.js');

function seeded(list) {
  return Model.applySnapshot(Model.empty(), list || Fixtures.tickets());
}
const ids = (state, options) => Model.visible(state, options).map(t => t.id);

test('a snapshot lists tickets newest first; unread counts only comments from others', () => {
  const state = seeded();
  assert.deepEqual(ids(state), ['4821', '4818', '4824']);
  const vpn = Model.visible(state)[0];
  assert.equal(vpn.updates, 2, "Alex's own reply is never unread");
  assert.equal(vpn.sender, 'Anna');
  assert.equal(vpn.senderMine, false);
  assert.equal(vpn.history.length, 4);
  assert.deepEqual(vpn.history.map(item => item.fresh), [true, false, true, false]);
});

test('marking read survives the next snapshot; a new reply from someone else unreads it', () => {
  const state = seeded();
  assert.equal(Model.markRead(state, '4821'), true);
  assert.equal(Model.markRead(state, '4821'), false);
  Model.applySnapshot(state, Fixtures.tickets());
  assert.equal(Model.visible(state)[0].read, true);
  Model.applySnapshot(state, Fixtures.update(1, false));
  const vpn = Model.visible(state)[0];
  assert.equal(vpn.updates, 1);
  assert.equal(vpn.read, false);
});

test('my own reply after reading keeps the ticket read', () => {
  const state = seeded();
  Model.markRead(state, '4824');
  const list = Fixtures.tickets();
  list[2].comments.unshift({ id: 48242, author: 'Alex', mine: true, public: true, created: Fixtures.BASE, body: 'On my way.' });
  list[2].updated_at = '2026-11-06T09:41:00Z';
  Model.applySnapshot(state, list);
  assert.equal(Model.visible(state).find(t => t.id === '4824').read, true);
});

test('unchanged tickets keep their comments; known lists what we have', () => {
  const state = seeded();
  const list = Fixtures.tickets().map(t => ({ ...t, comments: undefined, unchanged: true }));
  Model.applySnapshot(state, list);
  assert.equal(Model.visible(state)[0].history.length, 4);
  assert.deepEqual(Object.keys(Model.known(state)).sort(), ['4818', '4821', '4824']);
  const fresh = Model.applySnapshot(Model.empty(), [{ ...Fixtures.tickets()[0], comments: undefined, deferred: true }]);
  assert.deepEqual(Model.known(fresh), {}, 'deferred comments are asked for again');
});

test('a loaded ticket whose new comments are deferred asks for them on the next fetch', () => {
  const state = seeded();
  Model.markRead(state, '4821');
  // #4821 changed, but the run's comment budget was spent: no comments, a new updated_at.
  const changed = Fixtures.update(1, false)[0];
  Model.applySnapshot(state, [{ ...changed, comments: undefined, deferred: true }]);
  assert.equal(Model.visible(state)[0].history.length, 4, 'the earlier comments stay shown meanwhile');
  assert.deepEqual(Model.known(state), {}, 'the new revision is not reported as fetched');
  // The next run brings them: the reply is unread.
  Model.applySnapshot(state, [changed]);
  assert.equal(Model.known(state)['4821'], changed.updated_at);
  assert.equal(Model.visible(state)[0].updates, 1);
  // An unchanged ticket after that keeps its comments and stays known.
  Model.applySnapshot(state, [{ ...changed, comments: undefined, unchanged: true }]);
  assert.equal(Model.known(state)['4821'], changed.updated_at);
  assert.equal(Model.visible(state)[0].updates, 1);
});

test('mark as unread brings back the newest comment from someone else', () => {
  const state = seeded();
  Model.markRead(state, '4821');
  assert.equal(Model.markUnread(state, '4821'), true);
  assert.equal(Model.visible(state)[0].updates, 1);
  assert.equal(Model.markUnread(state, '4821'), false);
  assert.equal(Model.markUnread(state, 'missing'), false);
});

test('hideRead, unreadFirst and groupWaiting order the inbox', () => {
  const state = seeded();
  Model.markRead(state, '4821');
  assert.deepEqual(ids(state, { hideRead: true }), ['4818', '4824']);
  assert.deepEqual(ids(state, { unreadFirst: true }), ['4818', '4821', '4824'], 'unread first within each section');
  assert.deepEqual(ids(state, { groupWaiting: true }), ['4821', '4818', '4824'], 'an unread Pending ticket is not waiting');
  Model.markRead(state, '4818');
  assert.deepEqual(ids(state, { groupWaiting: true }), ['4821', '4824', '4818']);
});

test('your tickets come first, then unassigned ones, then waiting ones; heads mark each section', () => {
  const state = seeded();
  const heads = options => Model.visible(state, options).map(t => [t.id, t.section, t.sectionHead, t.sectionSize]);
  assert.deepEqual(heads({ groupWaiting: true }), [
    ['4821', 'mine', 'mine', 2], ['4818', 'mine', '', 2], ['4824', 'unassigned', 'unassigned', 1]]);
  Model.markRead(state, '4818');
  assert.deepEqual(heads({ groupWaiting: true }), [
    ['4821', 'mine', 'mine', 1], ['4824', 'unassigned', 'unassigned', 1], ['4818', 'waiting', 'waiting', 1]]);
  const mine = seeded(Fixtures.tickets().slice(0, 2));
  assert.deepEqual(Model.visible(mine).map(t => t.sectionHead), ['', ''], 'only your own tickets: no header');
  const unassigned = seeded(Fixtures.tickets().slice(2));
  assert.deepEqual(Model.visible(unassigned).map(t => t.sectionHead), ['unassigned']);
});

test('the Wide overview counts the sections and lists who waits for a reply, longest first', () => {
  const list = Fixtures.tickets().concat([
    { id: '4807', subject: 'Teams calls drop', status: 'New', priority: 'Normal', assignee: 'Alex', mine: true,
      group: 'Workplace', requester: 'Sofie', updated_at: '2026-11-02T08:00:00Z',
      comments: [{ id: 48071, author: 'Sofie', mine: false, public: true, created: Date.parse('2026-11-02T08:00:00Z'), body: 'Calls drop' }] },
    { id: '4802', subject: 'Shared mailbox', status: 'On-hold', priority: 'Normal', assignee: 'Alex', mine: true,
      group: '', requester: 'Kari', updated_at: '2026-11-01T08:00:00Z',
      comments: [{ id: 48021, author: 'Kari', mine: false, public: true, created: Date.parse('2026-11-01T08:00:00Z'), body: 'Missing' }] }]);
  const state = seeded(list);
  Model.markRead(state, '4818');
  Model.markRead(state, '4802');
  const view = Model.overview(Model.visible(state, { groupWaiting: true }));
  assert.deepEqual([view.unread, view.mine, view.unassigned, view.waiting], [3, 2, 1, 2]);
  // On-hold and Pending tickets wait on others, not on you; #4821 has Anna's reply after Alex's.
  assert.deepEqual(view.awaiting.map(item => item.id), ['4807', '4824', '4821']);
  assert.deepEqual(plain(view.awaiting[1]), { id: '4824', subject: 'Meeting room display is blank', status: 'New', sender: 'Maria',
    unassigned: true, received: Fixtures.BASE - 26 * 3600000 });
  assert.deepEqual(plain(view.groups), [{ name: 'IT support', mine: 2, unassigned: 0 }, { name: '', mine: 1, unassigned: 0 },
    { name: 'Facilities', mine: 0, unassigned: 1 }, { name: 'Workplace', mine: 1, unassigned: 0 }]);
  // Your own reply last: nobody waits on you.
  const replied = seeded([Object.assign(Fixtures.tickets()[0], { comments: Fixtures.tickets()[0].comments.slice(1) })]);
  assert.deepEqual(Model.overview(Model.visible(replied)).awaiting, []);
  assert.deepEqual(plain(Model.overview([])), { unread: 0, mine: 0, unassigned: 0, waiting: 0, awaiting: [], awaitingMore: 0, unknown: 0, groups: [], groupsMore: 0 });
});

test('the overview leaves out tickets whose comments have not come; group names are plain keys', () => {
  const list = Fixtures.tickets();
  // #4824's comments were deferred by the helper: who wrote last is unknown.
  delete list[2].comments;
  list[2].deferred = true;
  list[0].group = 'constructor';
  list[1].group = '__proto__';
  const view = Model.overview(Model.visible(seeded(list)));
  assert.deepEqual(view.awaiting.map(item => item.id), ['4821']);
  assert.equal(view.unknown, 1, 'the deferred New ticket may be waiting');
  assert.deepEqual(plain(view.groups), [{ name: '__proto__', mine: 1, unassigned: 0 }, { name: 'constructor', mine: 1, unassigned: 0 },
    { name: 'Facilities', mine: 0, unassigned: 1 }]);
  assert.equal(Object.prototype.mine, undefined);
});

test('the overview shows at most five waiting tickets and five groups, and counts the rest', () => {
  const many = Array.from({ length: 7 }, (_, i) => ({ id: String(5000 + i), subject: 'Ticket ' + i, status: 'Open', priority: 'Normal',
    assignee: '', unassigned: true, mine: false, group: 'Group ' + i, requester: 'Ola', updated_at: `2026-11-0${i + 1}T08:00:00Z`,
    comments: [{ id: 50000 + i, author: 'Ola', mine: false, public: true, created: Date.parse(`2026-11-0${i + 1}T08:00:00Z`), body: 'Hi' }] }));
  const view = Model.overview(Model.visible(seeded(many)));
  assert.deepEqual(view.awaiting.map(item => item.id), ['5000', '5001', '5002', '5003', '5004']);
  assert.deepEqual(view.groups.map(group => group.name), ['Group 0', 'Group 1', 'Group 2', 'Group 3', 'Group 4']);
  assert.deepEqual([view.awaitingMore, view.groupsMore], [2, 2], 'what the lists leave out is counted');
});

test('the latest comment says whether it is your own; days count calendar days', () => {
  const list = Fixtures.tickets();
  list[0].comments = list[0].comments.slice(1);
  assert.equal(Model.visible(seeded(list)).find(t => t.id === '4821').senderMine, true);
  const now = new Date(2026, 10, 6, 0, 30).getTime();
  assert.equal(Model.daysAgo(new Date(2026, 10, 6, 0, 1).getTime(), now), 0);
  assert.equal(Model.daysAgo(new Date(2026, 10, 5, 23, 59).getTime(), now), 1);
  assert.equal(Model.daysAgo(new Date(2026, 9, 30, 12).getTime(), now), 7);
  assert.equal(Model.daysAgo(new Date(2026, 10, 6, 9).getTime(), now), 0);
  assert.equal(Model.daysAgo(new Date(2026, 10, 7, 9).getTime(), now), -1);
});

test('a ticket being read keeps its place until it is released', () => {
  const state = seeded();
  // Opened unread, then marked read: it stays put, even with hideRead and unreadFirst.
  Model.markRead(state, '4821');
  const held = { held: { 4821: false }, hideRead: true, unreadFirst: true, groupWaiting: true };
  assert.deepEqual(ids(state, held), ['4821', '4818', '4824']);
  assert.equal(Model.visible(state, held)[0].read, true, 'it shows as read');
  assert.deepEqual(ids(state, { hideRead: true }), ['4818', '4824'], 'released, it hides');
  // A read Pending ticket opened from the waiting section stays there.
  Model.markRead(state, '4818');
  assert.deepEqual(ids(state, { groupWaiting: true, held: { 4818: true } }), ['4821', '4824', '4818']);
});

test('mark all as read can be undone back to the earlier markers', () => {
  const state = seeded();
  Model.markRead(state, '4818');
  const batch = Model.markAllRead(state);
  assert.deepEqual(batch.map(entry => entry.id).sort(), ['4821', '4824']);
  assert.ok(Model.visible(state).every(t => t.read));
  assert.deepEqual(Model.markAllRead(state), []);
  Model.restore(state, batch);
  assert.deepEqual(Model.visible(state).map(t => [t.id, t.read]), [['4821', false], ['4818', true], ['4824', false]]);
});

test('markers of tickets that left are kept a while, then pruned', () => {
  const state = seeded();
  Model.markRead(state, '4824', 1000);
  Model.applySnapshot(state, Fixtures.tickets().slice(0, 2), 1000 + 86400000);
  assert.ok(state.read['4824'], 'kept: the ticket may come back');
  Model.applySnapshot(state, Fixtures.tickets().slice(0, 2), 1000 + 31 * 86400000);
  assert.equal(state.read['4824'], undefined);
});

test('the read-state file round-trips and ignores junk', () => {
  const state = seeded();
  Model.markRead(state, '4821', 5);
  assert.deepEqual(Model.parseReadState(Model.serializeReadState(state)), { 4821: { revision: 48213, at: 5 } });
  assert.deepEqual(Model.parseReadState('{nope'), {});
  assert.deepEqual(Model.parseReadState(JSON.stringify({ read: { x: { revision: 1, at: 1 }, 7: { revision: 'a', at: 1 } } })), {});
});

test('a read-state file over the limit keeps the most recently marked tickets', () => {
  // Numeric keys enumerate in ascending order, so the newest tickets (the
  // highest ids, most likely in the inbox) come last.
  const read = {};
  for (let i = 1; i <= 2001; i++) read[String(1000 + i)] = { revision: i, at: i };
  read['1001'].at = 5000;
  const kept = Model.parseReadState(JSON.stringify({ version: 1, read }));
  assert.equal(Object.keys(kept).length, 2000);
  assert.deepEqual(kept['3001'], { revision: 2001, at: 2001 }, 'the newest marker stays');
  assert.deepEqual(kept['1001'], { revision: 1, at: 5000 }, 'an old ticket marked recently stays');
  assert.equal(kept['1002'], undefined, 'the least recently marked goes');
});

test('a hostile or broken reply is refused whole, bounded and defaulted', () => {
  assert.throws(() => Model.applySnapshot(Model.empty(), 'nope'));
  assert.throws(() => Model.applySnapshot(Model.empty(), [{ id: '__proto__' }]));
  // One bad ticket refuses the whole reply: the previous inbox stays.
  const state = seeded();
  assert.throws(() => Model.applySnapshot(state, Fixtures.tickets().concat([{ id: '12a' }])));
  assert.deepEqual(ids(state), ['4821', '4818', '4824']);
  // Ticket ids have at most 15 digits.
  assert.throws(() => Model.applySnapshot(Model.empty(), [{ id: '1'.repeat(16) }]));
  assert.deepEqual(Object.keys(Model.applySnapshot(Model.empty(), [{ id: '1'.repeat(15) }]).tickets), ['1'.repeat(15)]);
  // At most 200 tickets and 20 comments per ticket are kept.
  const many = Array.from({ length: 201 }, (_, i) => ({ id: String(6000 + i) }));
  assert.equal(Object.keys(Model.applySnapshot(Model.empty(), many).tickets).length, 200);
  const c = (id, created) => ({ id, author: 'Ola', mine: false, public: true, created, body: 'Hi' });
  const long = Model.ticketFrom({ id: '1', comments: Array.from({ length: 25 }, (_, i) => c(100 - i, 1)) });
  assert.equal(long.history.length, 20);
  // Comments with an id or time that is not a safe integer are dropped.
  assert.deepEqual(Model.ticketFrom({ id: '2', comments: [c(1.5, 1), c(7, 'x'), c(2 ** 53, 1), c(9, 1)] }).history.map(h => h.revision), [9]);
  // Missing fields get defaults.
  const bare = Model.ticketFrom({ id: '1', comments: [{ id: 1, created: 1 }] });
  assert.deepEqual([bare.subject, bare.status, bare.priority, bare.sender], ['(no subject)', 'Open', 'Normal', '?']);
  const body = '<img src="https://example.invalid/tracker">\nSecond paragraph';
  const list = Fixtures.tickets();
  list[0].comments[0].body = body;
  assert.equal(Model.visible(seeded(list))[0].body, body);
});

test('text cut to its limit says so; a comment the helper clipped keeps its mark', () => {
  // The helper clips a comment at 16384 characters (code points) and adds "…".
  const clipped = 'x'.repeat(16384) + '…';
  const emoji = '😀'.repeat(16384) + '…';
  const list = Fixtures.tickets();
  list[0].comments[0].body = clipped;
  list[1].comments[0].body = emoji;
  list[2].subject = 's'.repeat(600);
  const state = seeded(list);
  assert.equal(state.tickets[list[0].id].body, clipped);
  assert.equal(state.tickets[list[1].id].body, emoji);
  const subject = state.tickets[list[2].id].subject;
  assert.equal(subject.length, 512);
  assert.ok(subject.endsWith('…'), 'a subject cut short ends in an ellipsis');
  // Never half a surrogate pair.
  const cut = Model.ticketFrom({ id: '1', subject: 'a' + '😀'.repeat(300) }).subject;
  assert.ok(cut.endsWith('…') && !/[\uD800-\uDBFF]…$/.test(cut));
});

test('a fetch from before an account switch is ignored, even a full reply that arrives late', () => {
  const reply = JSON.stringify({ ok: true, tickets: Fixtures.tickets(), state_path: '/state/acme.json' });
  const now = Model.fetchOutcome(3, 3, 'progress\n' + reply + '\n');
  assert.equal(now.ok, true);
  assert.equal(now.tickets.length, 3);
  assert.equal(now.statePath, '/state/acme.json');
  assert.deepEqual(Model.fetchOutcome(2, 3, reply), { stale: true }, 'the previous account\'s full reply');
  assert.deepEqual(Model.fetchOutcome(2, 3, ''), { stale: true }, 'stopped (143) with nothing');
  assert.deepEqual(Model.fetchOutcome(3, 3, ''), { ok: false, reply: null });
  const failed = Model.fetchOutcome(3, 3, JSON.stringify({ ok: false, code: 'EXPIRED', error: 'x' }));
  assert.equal(failed.ok, false);
  assert.equal(failed.reply.code, 'EXPIRED');
  assert.equal(Model.fetchOutcome(3, 3, JSON.stringify({ ok: true, tickets: [] })).statePath, null);
  assert.equal(Model.fetchOutcome(3, 3, JSON.stringify({ ok: true, tickets: 'nope' })).ok, false);
});

test('unassigned comes from the flag, not the name: an agent may be called "Unassigned"', () => {
  const named = Model.ticketFrom({ id: '1', assignee: 'Unassigned', unassigned: false });
  assert.equal(named.unassigned, false);
  assert.equal(named.assignee, 'Unassigned');
  const none = Model.ticketFrom({ id: '2', assignee: '', unassigned: true });
  assert.equal(none.unassigned, true);
  assert.equal(none.assignee, '');
  assert.equal(Model.ticketFrom({ id: '3', assignee: 'Alex', unassigned: 'yes' }).unassigned, false);
});

test("the helper's truncated flags reach the inbox; anything else is not cut", () => {
  const outcome = truncated => Model.fetchOutcome(1, 1, JSON.stringify({ ok: true, tickets: [], truncated })).truncated;
  assert.deepEqual(outcome({ tickets: true, groups: false }), { tickets: true, groups: false });
  assert.deepEqual(outcome({ tickets: false, groups: true }), { tickets: false, groups: true });
  for (const odd of [undefined, null, 'yes', { tickets: 'true', groups: 1 }]) assert.deepEqual(outcome(odd), { tickets: false, groups: false });
});

test('ticket links use the configured account only', () => {
  // The helper normalizes the address the same way: native/src/oauth.rs
  // addresses_normalize_to_the_zendesk_subdomain holds the same rows. If the
  // two disagree, the read file and notifications name another host.
  const hosts = [
    ['ACME', 'acme.zendesk.com'],
    ['https://acme.zendesk.com/', 'acme.zendesk.com'],
    [' Acme ', 'acme.zendesk.com'],
    ['a'.repeat(63), 'a'.repeat(63) + '.zendesk.com'],
    ['evil.com', ''],
    ['acme.zendesk.com.evil.com', ''],
    ['http://acme.zendesk.com', ''],
    ['acme/x', ''],
    ['-acme', ''],
    ['acme-', ''],
    ['a'.repeat(64), ''],
    ['zendesk.com', ''],
    ['', ''],
  ];
  for (const [input, expected] of hosts) assert.equal(Model.host(input), expected, JSON.stringify(input));
  assert.equal(Model.ticketUrl('acme', '4821'), 'https://acme.zendesk.com/agent/tickets/4821');
  assert.equal(Model.ticketUrl('acme', '1/../x'), '');
  assert.equal(Model.ticketUrl('', '1'), '');
});

test('notifications: only comments from others that are new since the last fetch', () => {
  const state = seeded();
  const seen = Model.notices();
  // The first fetch only sets what has been seen.
  assert.deepEqual(Model.arrivals(state, seen, 'all'), [], 'the first inbox is never announced');
  assert.deepEqual(seen.revisions, { 4821: 48213, 4818: 48181, 4824: 48241 });
  assert.deepEqual(Model.arrivals(state, seen, 'all'), [], 'nothing new, nothing announced');
  // A reply from someone else, then a new unassigned ticket.
  Model.applySnapshot(state, Fixtures.update(1, false));
  assert.deepEqual(Model.arrivals(state, seen, 'all').map(t => t.id), ['4821']);
  Model.applySnapshot(state, Fixtures.update(2, true));
  assert.deepEqual(Model.arrivals(state, seen, 'mine'), [], 'unassigned tickets only with "all"');
  Model.applySnapshot(state, Fixtures.update(3, true));
  assert.deepEqual(Model.arrivals(state, seen, 'all').map(t => t.id), ['4903']);
});

test('notifications: own replies, read tickets and returning tickets stay quiet', () => {
  const state = seeded();
  const seen = Model.notices();
  Model.arrivals(state, seen, 'all');
  const mine = Fixtures.tickets();
  mine[0].updated_at = '2026-11-06T10:41:00Z';
  mine[0].comments.unshift({ id: 48219, author: 'Alex', mine: true, public: true, created: Fixtures.BASE + 60000, body: 'Done.' });
  Model.applySnapshot(state, mine);
  assert.deepEqual(Model.arrivals(state, seen, 'all'), []);
  // Read on this computer before the fetch saw it: nothing to announce.
  const reply = Fixtures.update(1, false);
  Model.applySnapshot(state, reply);
  Model.markRead(state, '4821');
  assert.deepEqual(Model.arrivals(state, seen, 'all'), []);
  // A ticket that drops out of the search and comes back isn't new.
  Model.applySnapshot(state, Fixtures.tickets().slice(1));
  Model.applySnapshot(state, Fixtures.tickets());
  Model.markUnread(state, '4821');
  assert.deepEqual(Model.arrivals(state, seen, 'all'), []);
});

// The helper fetches comments for at most 25 changed tickets per run; the rest
// come "deferred" (no comments) and follow on later runs.
function deferredInbox(count, withComments, created) {
  const list = [];
  for (let i = 0; i < count; i++) {
    const id = String(5000 + i);
    const raw = { id, subject: 'Ticket ' + id, status: 'Open', priority: 'Normal', assignee: i % 2 ? '' : 'Alex', unassigned: i % 2 === 1,
                  mine: i % 2 === 0, group: 'IT support', requester: 'Jonas', updated_at: '2026-11-06T10:00:00Z' };
    if (withComments(i)) raw.comments = [{ id: 50000 + i * 10, author: 'Jonas', mine: false, public: true, created: created, body: 'Old.' }];
    else raw.deferred = true;
    list.push(raw);
  }
  return list;
}

test('notifications: tickets whose comments come after the first inbox are taken in quietly', () => {
  const started = Fixtures.BASE + 3600000;
  const state = Model.empty();
  const seen = Model.notices();
  Model.applySnapshot(state, deferredInbox(60, i => i < 25, Fixtures.BASE));
  assert.deepEqual(Model.arrivals(state, seen, 'all', started), []);
  assert.equal(Object.keys(seen.pending).length, 35, 'the deferred tickets wait for their comments');
  // The next two runs bring the rest: old comments, nothing to announce, in either scope.
  Model.applySnapshot(state, deferredInbox(60, i => i < 50, Fixtures.BASE));
  assert.deepEqual(Model.arrivals(state, seen, 'mine', started + 60000), []);
  Model.applySnapshot(state, deferredInbox(60, () => true, Fixtures.BASE));
  assert.deepEqual(Model.arrivals(state, seen, 'all', started + 120000), []);
  assert.deepEqual(seen.pending, {});
  assert.equal(Model.visible(state).filter(t => !t.read).length, 60, 'still unread in the inbox, just not announced');
  // A real reply on one of them later is announced.
  const reply = deferredInbox(60, () => true, Fixtures.BASE);
  reply[40].comments.unshift({ id: 50401, author: 'Jonas', mine: false, public: true, created: started + 150000, body: 'New.' });
  Model.applySnapshot(state, reply);
  assert.deepEqual(Model.arrivals(state, seen, 'all', started + 180000).map(t => t.id), ['5040']);
});

test('notifications: a deferred ticket announces only comments newer than the first inbox', () => {
  const started = Fixtures.BASE + 3600000;
  const state = Model.empty();
  const seen = Model.notices();
  Model.applySnapshot(state, deferredInbox(30, i => i < 25, Fixtures.BASE));
  Model.arrivals(state, seen, 'all', started);
  // #5027 leaves the inbox before its comments came, and returns with a reply
  // written after the first inbox; #5028 brings only old comments.
  Model.applySnapshot(state, deferredInbox(30, i => i < 25, Fixtures.BASE).filter(t => t.id !== '5027'));
  assert.deepEqual(Model.arrivals(state, seen, 'all', started + 60000), []);
  assert.ok('5027' in seen.pending, 'a ticket out of the inbox keeps waiting');
  const back = deferredInbox(30, () => true, Fixtures.BASE);
  back[27].comments.unshift({ id: 50271, author: 'Jonas', mine: false, public: true, created: started + 90000, body: 'Still broken.' });
  Model.applySnapshot(state, back);
  assert.deepEqual(Model.arrivals(state, seen, 'all', started + 120000).map(t => t.id), ['5027']);
  assert.equal(seen.revisions['5028'], 50280);
});

test('notifications: a ticket new after the first inbox counts from 0, even when its comments come later', () => {
  const started = Fixtures.BASE + 3600000;
  const state = Model.empty();
  const seen = Model.notices();
  Model.applySnapshot(state, deferredInbox(25, () => true, Fixtures.BASE));
  Model.arrivals(state, seen, 'all', started);
  // A new ticket the run had no budget left for.
  const later = deferredInbox(26, i => i < 25, Fixtures.BASE);
  Model.applySnapshot(state, later);
  assert.deepEqual(Model.arrivals(state, seen, 'all', started + 60000), []);
  assert.deepEqual(seen.pending, {}, 'only the first inbox waits quietly');
  Model.applySnapshot(state, deferredInbox(26, () => true, Fixtures.BASE));
  assert.deepEqual(Model.arrivals(state, seen, 'all', started + 120000).map(t => t.id), ['5025']);
});

test('notification actions name their account; another account\'s do nothing', () => {
  const host = 'acme.zendesk.com';
  assert.deepEqual(Model.parseAction('acme.zendesk.com/4821:48215,4824:48241,junk', host, true),
                   [{ id: '4821', revision: 48215 }, { id: '4824', revision: 48241 }]);
  assert.deepEqual(Model.parseAction('acme.zendesk.com/4821', host, false), [{ id: '4821', revision: 0 }]);
  assert.equal(Model.parseAction('other.zendesk.com/4821:48215', host, true), null, 'another account');
  assert.equal(Model.parseAction('4821:48215', host, true), null, 'no account (an older notification)');
  assert.equal(Model.parseAction('4821', host, false), null);
  assert.equal(Model.parseAction('acme.zendesk.com/4821:48215', '', true), null, 'signed out');
  assert.equal(Model.parseAction('acme.zendesk.com.evil/4821:1', host, true), null);
  assert.deepEqual(Model.parseAction('acme.zendesk.com/', host, true), []);
});

test('a notification button reads up to the comment it showed, never back', () => {
  const state = seeded();
  Model.applySnapshot(state, Fixtures.update(2, false));
  assert.equal(Model.markReadUpTo(state, '4821', 48214), true);
  assert.equal(Model.visible(state)[0].updates, 1, 'the newer reply stays unread');
  assert.equal(Model.markReadUpTo(state, '4821', 48213), false, 'a marker never moves back');
  assert.equal(Model.markReadUpTo(state, '9999', 5), true, 'a ticket that left the inbox keeps the marker');
  assert.equal(Model.markReadUpTo(state, 'x', 5), false);
  assert.equal(Model.markReadUpTo(state, '4818', 1.5), false);
});

test('notification text is escaped markup on one line', () => {
  assert.equal(Model.notificationText('Tom & <b>Jerry</b>\n\nhi', 100), 'Tom &amp; &lt;b&gt;Jerry&lt;/b&gt; hi');
  assert.equal(Model.notificationText('abcdefghij', 6), 'abcde…');
  assert.equal(Model.notificationText(null, 6), '');
});

test('the settings schema agrees with the manifest; its patterns refuse bad values', () => {
  const manifest = require('../manifest.json');
  const pick = f => ({ key: f.key, type: f.type, defaultValue: f.defaultValue, options: f.options, min: f.min, max: f.max, step: f.step });
  assert.deepEqual(plain(manifest.barWidget.schema.map(pick)), plain(Schema.fields.map(pick)));
  const defaults = Object.fromEntries(Schema.fields.map(field => [field.key, field.defaultValue]));
  assert.deepEqual(defaults, manifest.barWidget.defaults);
  const pattern = key => new RegExp(Schema.fields.find(field => field.key === key).pattern);
  const rows = [
    [new RegExp(Schema.schedulePattern), ['', '08:00-16:00', '22:00-02:00', '00:00-24:00'], ['8:00-16:00', '24:00-01:00', '08:00']],
    [new RegExp(Schema.addressPattern), ['', 'acme', 'ACME.zendesk.com', 'https://acme.zendesk.com/'],
      ['evil.com', 'acme.zendesk.com.evil', 'http://acme', '-acme', 'acme x']],
    [pattern('oauthClientId'), ['foamy-test', 'a.b_c'], ['a b', 'x'.repeat(129)]],
    [pattern('oauthPort'), ['', '47823'], ['80a', '123456']],
  ];
  for (const [re, accepted, refused] of rows) {
    for (const value of accepted) assert.match(value, re);
    for (const value of refused) assert.doesNotMatch(value, re);
  }
});
