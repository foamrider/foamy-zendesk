const test = require('node:test');
const assert = require('node:assert/strict');
const Model = require('../Model.js');
const Fixtures = require('../preview/Fixtures.js');
const Schedule = require('../Schedule.js');
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

test('invalid replies are refused; text stays plain data', () => {
  assert.throws(() => Model.applySnapshot(Model.empty(), 'nope'));
  assert.throws(() => Model.applySnapshot(Model.empty(), [{ id: '__proto__' }]));
  const body = '<img src="https://example.invalid/tracker">\nSecond paragraph';
  const list = Fixtures.tickets();
  list[0].comments[0].body = body;
  assert.equal(Model.visible(seeded(list))[0].body, body);
});

test('ticket links use the configured account only', () => {
  assert.equal(Model.host('ACME'), 'acme.zendesk.com');
  assert.equal(Model.host('https://acme.zendesk.com/'), 'acme.zendesk.com');
  assert.equal(Model.host('evil.com'), '');
  assert.equal(Model.ticketUrl('acme', '4821'), 'https://acme.zendesk.com/agent/tickets/4821');
  assert.equal(Model.ticketUrl('acme', '1/../x'), '');
  assert.equal(Model.ticketUrl('', '1'), '');
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
  assert.deepEqual(snooze, { on: false, until: at(2, 16).getTime() });
  assert.equal(Schedule.effective(at(2, 15, 59), true, week, snooze), false);
  assert.equal(Schedule.effective(at(3, 8), true, week, snooze), false);
  // Pressing again goes back to the schedule: no override.
  assert.equal(Schedule.toggled(at(2, 11), true, week, snooze), null);
  // Outside the hours: resuming lasts until midnight...
  const evening = Schedule.toggled(at(2, 19), true, week, null);
  assert.deepEqual(evening, { on: true, until: at(3, 0).getTime() });
  assert.equal(Schedule.effective(at(2, 23, 59), true, week, evening), true);
  assert.equal(Schedule.effective(at(3, 0), true, week, evening), false);
  // ...or until the schedule starts, if that is sooner.
  assert.deepEqual(Schedule.toggled(at(2, 6), true, week, null), { on: true, until: at(2, 8).getTime() });
  // An overnight range: the snooze runs on past midnight to its end.
  assert.deepEqual(Schedule.toggled(at(3, 23), true, week, null), { on: false, until: at(4, 6).getTime() });
  // No schedule: snoozed until midnight.
  assert.deepEqual(Schedule.toggled(at(4, 12), false, [], null), { on: false, until: at(5, 0).getTime() });
  // The state file: expired or malformed overrides are dropped.
  const text = Schedule.serializeOverride(snooze);
  assert.deepEqual(Schedule.parseOverride(text, at(2, 12).getTime()), snooze);
  assert.equal(Schedule.parseOverride(text, at(2, 16).getTime()), null);
  assert.equal(Schedule.parseOverride('{"version":1,"override":{"on":"no","until":1}}', 0), null);
  assert.equal(Schedule.parseOverride('not json', 0), null);
  assert.equal(Schedule.serializeOverride(null), '{"version":1,"override":null}\n');
});
