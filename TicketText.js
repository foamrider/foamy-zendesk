// What a closed ticket row shows of a comment: its message as one run of
// text, in place of the raw start of a mail ("Hi Alex," and a blank line, a
// long URL, the quoted mail under a short answer).

// Only this much of a comment is looked at: the preview needs far less, and
// a comment can be 32 KiB.
var MAX_SCAN = 4000
// The preview's length. A row shows two lines of it at most.
var MAX_PREVIEW = 300
// A first line that starts with one of these and ends in "," or "!" is a
// salutation ("Hi Alex,"). Only these: "Urgent!" and "Thanks," are content.
var GREETINGS = ["Hi", "Hello", "Hey", "Dear", "Hei", "Hallo", "God morgen"]
// A salutation is the greeting and a name: with more words it is a sentence.
var MAX_SALUTATION_WORDS = 5

function blank(line) {
  return !/\S/.test(line)
}

// A line of the mail that is being answered.
function quoted(line) {
  return /^\s*>/.test(line)
}

// The line a mail program puts above the mail it quotes:
// "On Thu, 5 Nov 2026 at 16:02, Alex <support@acme.example> wrote:" or
// "Den 5. nov. 2026 kl. 16:02 skrev Alex <support@acme.example>:".
// It carries a date, so "On that note, the customer wrote:" is not one.
function quoteHeader(line) {
  return /\d/.test(line) && (/^\s*On\s.*\swrote:\s*$/i.test(line) || /^\s*Den\s.*\sskrev\s.*:\s*$/i.test(line))
}

// Where the quoted mail starts: the index of its first line, or the number
// of lines when nothing is quoted.
function quoteStart(lines) {
  for (var i = 0; i < lines.length; i++) {
    // A long header is wrapped: "On …, Alex <…>" and "wrote:" on the next line.
    if (quoteHeader(lines[i]) || (i + 1 < lines.length && /^\s*(On|Den)\s/i.test(lines[i]) && quoteHeader(lines[i] + " " + lines[i + 1])))
      return i
    if (!quoted(lines[i]))
      continue
    // The line that introduces the quote, in any language ("… skrev Alex:").
    var above = i - 1
    while (above >= 0 && blank(lines[above]))
      above--
    return above >= 0 && /:\s*$/.test(lines[above]) ? above : i
  }
  return lines.length
}

function salutation(line) {
  var text = line.trim()
  if (!/[,!]$/.test(text))
    return false
  var words = text.slice(0, -1)
  // "Hi, I can't sign in!" is the message, not a greeting.
  if (/[.,;:!?]/.test(words) || words.split(/\s+/).length > MAX_SALUTATION_WORDS)
    return false
  var lower = words.toLowerCase()
  return GREETINGS.some(function(greeting) {
    var start = greeting.toLowerCase()
    return lower === start || lower.indexOf(start + " ") === 0
  })
}

// Each http(s) URL as its host, with "/…" when it goes on:
// "https://erp.acme.example/invoices/2026-1047?lang=nb" → "erp.acme.example/…".
function shortenUrls(text) {
  return text.replace(/https?:\/\/[^\s<>"]+/gi, function(url) {
    // Punctuation after the URL belongs to the sentence; a ")" only when the
    // URL doesn't open it.
    var end = url.length
    while (end > 0) {
      var last = url.charAt(end - 1)
      if (".,;:!?]}'".indexOf(last) < 0 && !(last === ")" && url.slice(0, end).split("(").length < url.slice(0, end).split(")").length))
        break
      end--
    }
    var address = url.slice(url.indexOf("//") + 2, end)
    var pathAt = address.search(/\/|\?|#/)
    var host = pathAt < 0 ? address : address.slice(0, pathAt)
    // Never the user name or password of "user:secret@host".
    host = host.slice(host.lastIndexOf("@") + 1)
    if (host === "")
      return url
    var more = pathAt >= 0 && address.length - pathAt > 1
    return host + (more ? "/…" : "") + url.slice(end)
  })
}

// At most `limit` UTF-16 units; cut short, it ends in "…" and never in half
// a surrogate pair. (The shell's JavaScript has no trimEnd.)
function clip(text, limit) {
  if (text.length <= limit)
    return text
  var cut = text.slice(0, limit - 1)
  if (/[\uD800-\uDBFF]$/.test(cut))
    cut = cut.slice(0, -1)
  return cut.replace(/\s+$/, "") + "…"
}

// The preview of a comment `body`: the writer's own text up to the quoted
// mail, without a leading salutation, URLs as their hosts, every run of
// whitespace folded to one space, at most MAX_PREVIEW characters.
function previewText(body) {
  if (typeof body !== "string" || body === "")
    return ""
  var lines = body.slice(0, MAX_SCAN).split(/\r\n|\r|\n/)
  var own = message(lines.slice(0, quoteStart(lines)))
  // An answer written under the quote ("Hi Alex," above it counts as
  // nothing): the quote is not the message.
  if (own.every(blank))
    own = message(lines.filter(function(line) {
      return !quoted(line) && !quoteHeader(line)
    }))
  // Nothing but a greeting, or quoted text: show it, without the marks.
  if (own.every(blank))
    own = lines.map(function(line) {
      return line.replace(/^(\s*>)+/, "")
    })
  return clip(shortenUrls(own.join("\n")).replace(/\s+/g, " ").trim(), MAX_PREVIEW)
}

// `lines` without a leading salutation ("Hi Alex,"); blank lines when that
// is all there is.
function message(lines) {
  var first = lines.findIndex(function(line) {
    return !blank(line)
  })
  return first >= 0 && salutation(lines[first]) ? lines.slice(first + 1) : lines
}

if (typeof module !== "undefined") module.exports = { MAX_PREVIEW, GREETINGS, previewText, shortenUrls, salutation, quoteStart, clip }
