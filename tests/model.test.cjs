const test = require('node:test');
const assert = require('node:assert/strict');
const Model = require('../Model.js');
const Fixtures = require('../preview/Fixtures.js');
// The kit's schedule, with this plugin's settings and cases.
const Schedule = require('../kit/node-loader.cjs').load('FoamySchedule');
// Its objects come from the loader's own realm; compare them as plain data.
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

test('on-hold tickets wait like pending ones', () => {
  const list = Fixtures.tickets();
  list[1].status = 'On-hold';
  const state = seeded(list);
  Model.markRead(state, '4818');
  assert.deepEqual(ids(state, { groupWaiting: true }), ['4821', '4824', '4818']);
  assert.equal(Model.visible(state, { groupWaiting: true })[2].section, 'waiting');
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

test('invalid replies are refused; text stays plain data', () => {
  assert.throws(() => Model.applySnapshot(Model.empty(), 'nope'));
  assert.throws(() => Model.applySnapshot(Model.empty(), [{ id: '__proto__' }]));
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

test("the helper's truncated flags reach the inbox; anything else is not cut", () => {
  const outcome = truncated => Model.fetchOutcome(1, 1, JSON.stringify({ ok: true, tickets: [], truncated })).truncated;
  assert.deepEqual(outcome({ tickets: true, groups: false }), { tickets: true, groups: false });
  assert.deepEqual(outcome({ tickets: false, groups: true }), { tickets: false, groups: true });
  for (const odd of [undefined, null, 'yes', { tickets: 'true', groups: 1 }]) assert.deepEqual(outcome(odd), { tickets: false, groups: false });
});

test('ticket links use the configured account only', () => {
  assert.equal(Model.host('ACME'), 'acme.zendesk.com');
  assert.equal(Model.host('https://acme.zendesk.com/'), 'acme.zendesk.com');
  assert.equal(Model.host('evil.com'), '');
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
    const raw = { id, subject: 'Ticket ' + id, status: 'Open', priority: 'Normal', assignee: i % 2 ? 'Unassigned' : 'Alex',
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

test('schedule: overnight ranges carry into the next day; off means always within', () => {
  const week = ['', '', '', '', '', '', ''];
  week[0] = '22:00-02:00'; // Monday night into Tuesday
  assert.equal(Schedule.withinWeek(new Date(2026, 10, 2, 23), true, week), true);
  assert.equal(Schedule.withinWeek(new Date(2026, 10, 3, 1), true, week), true);
  assert.equal(Schedule.withinWeek(new Date(2026, 10, 3, 2), true, week), false);
  assert.equal(Schedule.withinWeek(new Date(2026, 10, 3, 2), false, week), true);
  assert.equal(Schedule.withinWeek(new Date(2026, 10, 4, 12), true, ['', '', '00:00-24:00', '', '', '', '']), true);
});

test('settings schema: defaults keep today\'s behaviour and match the manifest', () => {
  const manifest = require('../manifest.json');
  const defaults = Object.fromEntries(Schema.fields.map(field => [field.key, field.defaultValue]));
  assert.deepEqual(defaults, manifest.barWidget.defaults);
  assert.deepEqual(manifest.barWidget.schema.map(field => field.key), Schema.fields.map(field => field.key));
  assert.equal(Schema.fields.find(field => field.key === 'scheduleOutsideMode').defaultValue, 'mute');
  for (const value of ['', '08:00-16:00', '22:00-02:00', '00:00-24:00']) assert.match(value, new RegExp(Schema.schedulePattern));
  for (const value of ['8:00-16:00', '24:00-01:00', '08:00']) assert.doesNotMatch(value, new RegExp(Schema.schedulePattern));
});

test('schedule: snoozing and resuming override the schedule until the next day', () => {
  const at = (day, hour, minute) => new Date(2026, 10, day, hour, minute || 0);
  const week = ['08:00-16:00', '22:00-06:00', '', '', '', '', '']; // Monday, Tuesday night
  // Within the hours: a snooze lasts until they end, then the schedule rules again.
  const snooze = Schedule.toggled(at(2, 10), true, week, null);
  assert.deepEqual(plain(snooze), { on: false, until: at(2, 16).getTime() });
  assert.equal(Schedule.effective(at(2, 15, 59), true, week, snooze), false);
  assert.equal(Schedule.effective(at(3, 8), true, week, snooze), false);
  // Pressing again goes back to the schedule: no override.
  assert.equal(Schedule.toggled(at(2, 11), true, week, snooze), null);
  // Outside the hours: resuming lasts until midnight...
  const evening = Schedule.toggled(at(2, 19), true, week, null);
  assert.deepEqual(plain(evening), { on: true, until: at(3, 0).getTime() });
  assert.equal(Schedule.effective(at(2, 23, 59), true, week, evening), true);
  assert.equal(Schedule.effective(at(3, 0), true, week, evening), false);
  // ...or until the schedule starts, if that is sooner.
  assert.deepEqual(plain(Schedule.toggled(at(2, 6), true, week, null)), { on: true, until: at(2, 8).getTime() });
  // An overnight range: the snooze runs on past midnight to its end.
  assert.deepEqual(plain(Schedule.toggled(at(3, 23), true, week, null)), { on: false, until: at(4, 6).getTime() });
  // No schedule: snoozed until midnight.
  assert.deepEqual(plain(Schedule.toggled(at(4, 12), false, [], null)), { on: false, until: at(5, 0).getTime() });
  // The state file: expired or malformed overrides are dropped.
  const text = Schedule.serializeOverride(snooze);
  assert.deepEqual(plain(Schedule.parseOverride(text, at(2, 12).getTime())), plain(snooze));
  assert.equal(Schedule.parseOverride(text, at(2, 16).getTime()), null);
  assert.equal(Schedule.parseOverride('{"version":1,"override":{"on":"no","until":1}}', 0), null);
  assert.equal(Schedule.parseOverride('not json', 0), null);
  assert.equal(Schedule.serializeOverride(null), '{"version":1,"override":null}\n');
});
