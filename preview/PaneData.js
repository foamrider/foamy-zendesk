// Extra sample tickets for the pane prototype states (the helper's `fetch` reply format,
// as preview/Stress.js). READ: read markers, { ticket id: comment id read up to }.
// One ticket that stretches the reading pane: a subject of four lines, a
// requester and a group too long for the facts line, a comment of more than
// 40 lines (a pasted log, with a line that starts with ">"), a Norwegian
// reply that ends in quoted mail, a long sender name, a sender that is a mail
// address and a forwarded mail without ">" marks. Fictional people.
var BASE = 1793958000000 // Stress.js's: 06 Nov 2026, 10:40 (Europe/Oslo)
var MIN = 60000
var HOUR = 3600000
var DAY = 86400000

var READ = {
  "5110": 51101 // the two newer comments from the requester are unread
}

// The comments that end in quoted mail (Quote.js), for the scratch test.
var FOLDED = [51102]

function iso(ms) {
  return new Date(ms).toISOString().replace(/\.000Z$/, "Z")
}

function comment(id, author, agoMs, body, extra) {
  return Object.assign({ id: id, author: author, mine: author === "Alex", public: true, created: BASE - agoMs, body: body }, extra || {})
}

var REQUESTER = "Maximilian Alexander von Hohenstein-Brandenburg (Nordlys Regnskap og Rådgivning AS)"

var LOG = [
  "02:00:01 export started (run 2026-11-06, 22 steps)",
  "02:00:04 step 01/22 customers ............ ok (48 211 rows)",
  "02:00:19 step 02/22 customer addresses ... ok (61 004 rows)",
  "02:01:02 step 03/22 products ............. ok (12 876 rows)",
  "02:01:07 step 04/22 product groups ....... ok (214 rows)",
  "02:01:31 step 05/22 price lists .......... ok (88 430 rows)",
  "02:02:10 step 06/22 suppliers ............ ok (3 902 rows)",
  "02:02:12 step 07/22 warehouses ........... ok (17 rows)",
  "02:03:40 step 08/22 stock levels ......... ok (402 118 rows)",
  "02:05:55 step 09/22 purchase orders ...... ok (96 730 rows)",
  "02:09:21 step 10/22 purchase lines ....... ok (511 902 rows)",
  "02:10:03 step 11/22 invoices ............. ok (188 455 rows)",
  "02:14:47 step 12/22 invoice lines ........ ok (1 204 667 rows)",
  "02:15:30 step 13/22 orders ............... ok (240 019 rows)",
  "02:15:31 step 14/22 order lines .......... started",
  "02:45:31 step 14/22 order lines .......... still running (30 min)",
  "03:15:31 step 14/22 order lines .......... still running (60 min)",
  "03:41:12 step 14/22 order lines .......... FAILED",
  "03:41:12 ORA-01555: snapshot too old: rollback segment number 12 with name \"_SYSSMU12_2190673109$\" too small",
  "03:41:12 ORA-06512: at \"DWH.EXPORT_PKG\", line 418",
  "03:41:12 step 15/22 deliveries ........... skipped",
  "03:41:12 step 16/22 delivery lines ....... skipped",
  "03:41:12 step 17/22 returns .............. skipped",
  "03:41:12 step 18/22 credit notes ......... skipped",
  "03:41:12 step 19/22 payments ............. skipped",
  "03:41:12 step 20/22 ledger entries ....... skipped",
  "03:41:12 step 21/22 budgets .............. skipped",
  "03:41:12 step 22/22 currency rates ....... skipped",
  "03:41:13 export finished with errors (13 ok, 1 failed, 8 skipped)"
].join("\n")

function tickets() {
  return [
    {
      id: "5110",
      subject: "Nightly export to the data warehouse stops at step 14 of 22 (order lines) with “ORA-01555: snapshot too old” since the upgrade on Tuesday — the finance dashboards and the Monday report to the board are affected",
      status: "On-hold", priority: "High", assignee: "Alex", mine: true,
      group: "Finance systems, payroll and data warehouse — second line",
      requester: REQUESTER, updated_at: iso(BASE - 2 * MIN),
      comments: [
        comment(51103, REQUESTER, 2 * MIN, "Hi,\n\nThe nightly export to the data warehouse has failed three nights in a row. It stops at step 14 of 22 (order lines). The finance dashboards still show Tuesday's numbers, and the Monday report is built from this export.\n\nThis is the log from last night:\n\n" + LOG + "\n\nI ran step 14 by hand this morning and got the same error after about 90 minutes:\n\n> exec dwh_export.run_step(14)\n\nWhat I have checked:\n1. The disk on dwh-prod-02 is 61 % full\n2. Nobody else was signed in to the database during the night\n3. The same export runs fine in the test environment (4 minutes for step 14)\n4. Step 14 took 6 minutes before the upgrade on Tuesday\n\nCould you look at it before Monday? The report must be sent to the board at 12:00.\n\nBest regards,\nMaximilian"),
        comment(51102, REQUESTER, 3 * HOUR, "Hei Alex,\n\nJeg har ikke startet eksporten på nytt, den går automatisk kl. 02:00 hver natt. Loggen sender jeg så snart jeg får tak i den.\n\nMvh\nMaximilian\n\ntor. 5. nov. 2026 kl. 16:20 skrev Alex <support@acme.example>:\n> Hei,\n>\n> Har dere startet eksporten på nytt etter oppgraderingen? Send gjerne loggen\n> fra siste kjøring.\n>\n> Mvh Alex"),
        comment(51101, "Alex", 18 * HOUR + 20 * MIN, "Hei,\n\nHar dere startet eksporten på nytt etter oppgraderingen? Send gjerne loggen fra siste kjøring.\n\nMvh Alex"),
        comment(51100, "Ingrid Margrethe Solheim-Andersen (Database operations, Bergen)", 19 * HOUR, "The undo retention on dwh-prod-02 went back to the default (900 s) with the upgrade. Step 14 reads for longer than that. I can raise it on Monday morning, not before: the change window is closed.", { public: false }),
        comment(51099, "export-monitor@dwh.acme.example", DAY + 8 * HOUR, "ALERT dwh-prod-02: export run 2026-11-05 finished with errors (13 ok, 1 failed, 8 skipped)."),
        comment(51098, REQUESTER, 2 * DAY + 7 * HOUR, "Can you help with this? It came from our supplier this morning.\n\nFrom: DataBridge Support <support@databridge.example>\nSent: Wednesday, 4 November 2026 08:12\nTo: Maximilian Alexander von Hohenstein-Brandenburg\nSubject: Upgrade to 14.2 completed\n\nThe upgrade of your warehouse database to 14.2 was completed at 23:40 on Tuesday. Please check your nightly jobs and tell us if anything behaves differently.")
      ]
    }
  ]
}

if (typeof module !== "undefined") module.exports = { BASE, READ, FOLDED, tickets }
