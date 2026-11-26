// A comment that came in as mail often ends with the mail it answers: the
// program's "On … wrote:" line and the earlier mail, quoted. The reading pane
// shows that mail as a comment of its own, so it folds the quote away behind
// "Show quoted text" (TicketPane.qml). This finds the quote.
//
// A quoted tail starts at a mail program's header line or at a run of lines
// that start with ">", and counts only when every line after it, to the end
// of the comment, is a quoted line, a blank line or another such header. A
// quote the author answers below it, a line that only happens to start with
// ">" (a log line, a prompt) and an earlier mail without ">" marks therefore
// stay in the text: nothing says where such a mail ends, and it may be a
// forwarded mail the agent has to read.

var TEXT = 0
var BLANK = 1
var QUOTED = 2
var HEADER = 3

// A header is a short line: a paragraph that ends in "wrote:" is not one.
var MAX_HEADER = 200

var QUOTED_LINE = /^[ \t]*>/
// "On Thu, 5 Nov 2026 at 16:02, Alex <alex@acme.example> wrote:"
var WROTE = /^On\s.+\swrote:$/i
// "Den 05.11.2026 16:02, skrev Alex:", "tor. 5. nov. 2026 kl. 16:02 skrev Alex <alex@acme.example>:"
var SKREV = /^(Den\s.+|.*\d{1,2}[.:]\d{2}.*)\sskrev\s.*:$/i
// "-----Original Message-----", "-----Opprinnelig melding-----"
var ORIGINAL = /^-{2,}\s*(Original Message|Opprinnelig melding)\s*-{2,}$/i
// Outlook's block: "From: …" and "Sent: …" on one line or on two, then the
// rest of the mail's header.
var FROM = /^(From|Fra):\s*\S/i
var SENT = /^(Sent|Sendt):\s*\S/i
var FROM_SENT = /^(From|Fra):\s.+\s(Sent|Sendt):\s/i
var BLOCK_FIELD = /^(Sent|Sendt|To|Til|Cc|Kopi|Bcc|Blindkopi|Subject|Emne|Date|Dato|Importance|Viktighet):/i

// `text` without its trailing whitespace. A loop from the end, not
// /\s+$/: that regex retries from every space of a long run in the middle
// of a line (mail can hold thousands of &nbsp;), which costs n² steps.
function trimEnd(text) {
  var end = text.length
  while (end > 0 && /\s/.test(text.charAt(end - 1)))
    end--
  return text.slice(0, end)
}

function clean(line) {
  return trimEnd(line)
}

function attribution(text) {
  return text.length <= MAX_HEADER && (WROTE.test(text) || SKREV.test(text))
}

// How many lines the header that starts at `at` takes (0: no header there).
// A mail program wraps a long "On … wrote:" line, so one may take up to three
// lines; a wrapped one must hold a date or a time, as a sentence that only
// starts with "On" does not.
function headerLines(lines, at) {
  var first = clean(lines[at])
  if (first === "" || QUOTED_LINE.test(first))
    return 0
  if (ORIGINAL.test(first) || attribution(first))
    return 1
  if (FROM.test(first)) {
    var next = at + 1
    if (!FROM_SENT.test(first)) {
      if (next >= lines.length || !SENT.test(clean(lines[next])))
        return 0
      next++
    }
    while (next < lines.length && BLOCK_FIELD.test(clean(lines[next])))
      next++
    return next - at
  }
  var joined = first
  for (var more = 1; more <= 2 && at + more < lines.length; more++) {
    var line = clean(lines[at + more])
    if (line === "" || QUOTED_LINE.test(line))
      return 0
    joined += " " + line
    if (/\d/.test(joined) && attribution(joined))
      return more + 1
  }
  return 0
}

function kindsOf(lines) {
  var kinds = []
  for (var i = 0; i < lines.length; i++) {
    var line = clean(lines[i])
    var header = headerLines(lines, i)
    if (header > 0) {
      for (var j = 0; j < header; j++)
        kinds.push(HEADER)
      i += header - 1
    } else
      kinds.push(line === "" ? BLANK : QUOTED_LINE.test(line) ? QUOTED : TEXT)
  }
  return kinds
}

// { text, tail }: what the author wrote and the quoted mail that ends the
// comment ("" when there is none). Together they hold every line of `body`
// but the blank ones between them.
function split(body) {
  var whole = { text: typeof body === "string" ? body : "", tail: "" }
  // A quoted mail has a line with ">": most comments end here.
  if (whole.text.indexOf(">") < 0)
    return whole
  var lines = whole.text.split("\n")
  var kinds = kindsOf(lines)
  var start = lines.length
  while (start > 0 && kinds[start - 1] !== TEXT)
    start--
  while (start < lines.length && kinds[start] === BLANK)
    start++
  var quoted = 0
  for (var i = start; i < lines.length; i++)
    if (kinds[i] === QUOTED)
      quoted++
  // A header with nothing quoted under it, or one line with a ">" and no
  // header above it, is not a quoted mail.
  if (quoted === 0 || (kinds[start] === QUOTED && quoted < 2))
    return whole
  var text = trimEnd(lines.slice(0, start).join("\n"))
  // A comment that is only a quote keeps it in view.
  if (text === "")
    return whole
  return { text: text, tail: trimEnd(lines.slice(start).join("\n")) }
}

if (typeof module !== "undefined") module.exports = { split }
