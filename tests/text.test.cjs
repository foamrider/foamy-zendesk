const test = require('node:test');
const assert = require('node:assert/strict');
const Quote = require('../Quote.js');
const TicketText = require('../TicketText.js');

test('a quoted mail at the end of a comment is folded away, with its header', () => {
  const body = 'Thanks, that worked.\n\nOn Thu, 5 Nov 2026 at 16:02, Alex <alex@acme.example> wrote:\n> Could you restart the client?\n> Alex';
  assert.deepEqual(Quote.split(body), {
    text: 'Thanks, that worked.',
    tail: 'On Thu, 5 Nov 2026 at 16:02, Alex <alex@acme.example> wrote:\n> Could you restart the client?\n> Alex'
  });
  // Norwegian and Outlook headers count too.
  assert.equal(Quote.split('Ok.\n\nDen 05.11.2026 16:02, skrev Alex:\n> Hei').tail, 'Den 05.11.2026 16:02, skrev Alex:\n> Hei');
  assert.equal(Quote.split('Ok.\n\nFrom: Alex\nSent: Thursday\nSubject: VPN\n> Hi\n> there').text, 'Ok.');
});

test('a long run of spaces inside a line is split in linear time', { timeout: 2000 }, () => {
  // A mail with thousands of &nbsp; (decoded to spaces) in one line.
  // As long as a comment can be (Model.js MAX_BODY).
  const body = 'Ok.\n\nOn Thu, 5 Nov 2026 at 16:02, Alex wrote:\n> a' + ' '.repeat(32700) + 'b\n> c';
  const started = process.hrtime.bigint();
  assert.equal(Quote.split(body).text, 'Ok.');
  assert.ok(Number(process.hrtime.bigint() - started) / 1e6 < 500, 'split took too long');
});

test('a quote the author answers below, a lone ">" line and a comment that is only a quote stay whole', () => {
  const answered = '> Could you restart the client?\nYes, twice.\n> And the network?\nThe same.';
  assert.deepEqual(Quote.split(answered), { text: answered, tail: '' });
  const log = 'The log says:\n> connection reset';
  assert.deepEqual(Quote.split(log), { text: log, tail: '' });
  const onlyQuote = '> one\n> two';
  assert.deepEqual(Quote.split(onlyQuote), { text: onlyQuote, tail: '' });
  // "wrote:" ending a sentence is no header, and nothing is quoted under it.
  const sentence = 'On Monday the customer wrote:\nthe printer is offline.';
  assert.deepEqual(Quote.split(sentence), { text: sentence, tail: '' });
  assert.deepEqual(Quote.split(undefined), { text: '', tail: '' });
});

test('a row preview starts at the message: no greeting, no quoted mail, URLs as their hosts', () => {
  assert.equal(TicketText.previewText('Hi Alex,\n\nThe VPN drops.\n\nOn Thu, 5 Nov 2026 at 16:02, Alex <a@acme.example> wrote:\n> Restart it.'), 'The VPN drops.');
  assert.equal(TicketText.previewText('See https://erp.acme.example/invoices/2026-1047?lang=nb, please.'), 'See erp.acme.example/…, please.');
  // Never the user name or password in a URL.
  assert.equal(TicketText.previewText('Log in at https://user:secret@acme.example/'), 'Log in at acme.example');
  // "Hi, I can't sign in!" is the message itself.
  assert.equal(TicketText.previewText("Hi, I can't sign in!"), "Hi, I can't sign in!");
  // An answer under the quote is the message; a comment that is only a quote shows it without the marks.
  assert.equal(TicketText.previewText('> Did it work?\nYes.'), 'Yes.');
  assert.equal(TicketText.previewText('> one\n> two'), 'one two');
  // A greeting above an inline quote is not the message; the answer below it is.
  assert.equal(TicketText.previewText('Hi Alex,\n\n> Could you restart the client?\n\nYes, twice.'), 'Yes, twice.');
  // A greeting alone is all there is.
  assert.equal(TicketText.previewText('Hi Alex!'), 'Hi Alex!');
});

test('a row preview is cut at its length with "…", never in half a surrogate pair', () => {
  const long = 'word '.repeat(200);
  const preview = TicketText.previewText(long);
  assert.equal(preview.length, TicketText.MAX_PREVIEW);
  assert.ok(preview.endsWith('…'));
  const emoji = 'a'.repeat(TicketText.MAX_PREVIEW - 2) + '😀😀';
  assert.ok(!/[\uD800-\uDBFF]…$/.test(TicketText.clip(emoji, TicketText.MAX_PREVIEW)));
});
