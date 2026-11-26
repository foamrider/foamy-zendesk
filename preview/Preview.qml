import QtQuick
import qs.Commons as Commons
import "../kit"
import ".." as Plugin
import "Fixtures.js" as Fixtures
import "Stress.js" as Stress
import "RowsData.js" as RowsData
import "PaneData.js" as PaneData
import "OverviewData.js" as OverviewData
import "ShellData.js" as ShellData

// The plugin's preview: its own states, the same in Wide ("wide-<state>"),
// "stress" states that load Stress.js (a realistic, untidy inbox), and the
// states of each part of the UI (rows and the open card, the reading pane,
// the overview, the account and the notice bar), with their extra tickets in
// RowsData.js, PaneData.js, OverviewData.js and ShellData.js.
//
// State names: one that starts with "wide" renders Wide (880 px wide), one
// that contains "stress" loads the realistic inbox, one that starts with
// "narrow" renders 320 px wide.
Item {
  id: preview
  required property QtObject bar
  required property Item anchorItem
  readonly property var baseStates: [
    // The plugin's own states.
    "tickets", "expanded", "pending", "all-read", "hide-read", "grouped", "grouped-expanded", "signed-out", "loading", "failed", "offline", "empty", "settings", "connection", "schedule", "outside-schedule", "narrow", "narrow-expanded", "focused", "scrolling", "menu", "wide", "wide-ticket", "wide-pending", "wide-focused", "wide-conversation", "wide-empty", "wide-settings",
    // More states, Small.
    "snoozed", "truncated", "notice", "save-error", "mark-unread-cursor",
    // The same in Wide.
    "wide-signed-out", "wide-loading", "wide-failed", "wide-offline", "wide-all-read", "wide-hide-read", "wide-menu", "wide-outside-schedule", "wide-snoozed", "wide-connection", "wide-schedule", "wide-truncated", "wide-notice", "wide-scrolling",
    // The realistic inbox, Small.
    "stress", "stress-scrolled", "stress-bottom", "stress-open", "stress-open-all", "stress-open-other", "stress-hide-read", "stress-unread-first", "stress-ungrouped", "stress-focused", "narrow-stress",
    // The realistic inbox, Wide.
    "wide-stress", "wide-stress-list-bottom", "wide-stress-ticket", "wide-stress-ticket-scrolled", "wide-stress-internal", "wide-stress-unassigned", "wide-stress-nocomments", "wide-stress-hide-read"]

  // "…-rows-notes": the realistic inbox plus RowsData's tickets (a newest
  // comment that is the agent's own or a colleague's internal note, a parked
  // Urgent ticket, a read ticket whose comments haven't loaded).
  // "…-rows-all-read": the same inbox with every ticket read: one-line rows
  // with every kind of subject, tag and name.
  // "…-rows-read-cursor": the keyboard cursor on a read row's Mark as unread.
  // "stress-rows-rtl": the list mirrored, as a right-to-left language shows it.
  // "stress-rows-assignee": a ticket assigned to a colleague (the helper sends none today).
  // Stage 2, the open card ("…-open-…"; RowsData.openCard() has their tickets):
  // "stress-open-scrolled": #5102 open and unfolded, scrolled to its end
  // (yesterday's comments, the internal notes, the footer row).
  // "stress-open-mid": the same, scrolled into the middle of the card (the
  // header band pinned to the top of the list).
  // "stress-open-leaving": the same, scrolled until the footer row is near
  // the top: the pinned band stops above it and leaves with the card.
  // "narrow-stress-open": #5102 open at 320 px.
  // "…-open-names": author names of 26 and 45 characters, with both labels.
  // "stress-open-notes": #5098, an internal note among the unread comments.
  // "…-open-clip": the agent's own reply above the newest unread comment (12
  // lines) and a long internal note (6 lines, fading into its surface).
  // "stress-open-short": a short read ticket (#5091) opened in place.
  // "stress-open-unloaded": #5090, whose comments haven't loaded.
  // "stress-open-deferred": a ticket whose newer comments haven't loaded.
  // "stress-open-empty": a ticket sent without comments.
  // "stress-open-cursor": the keyboard cursor on the open card's Mark as unread.
  // "stress-open-rtl": the open card mirrored.
  // "stress-open-note-first": the newest comment is a colleague's internal note.
  readonly property var rowsOpenStates: ["stress-open-scrolled", "stress-open-mid", "stress-open-leaving", "narrow-stress-open-mid", "narrow-stress-open", "narrow-stress-open-scrolled", "stress-open-names", "narrow-stress-open-names", "stress-open-notes", "stress-open-note-first", "stress-open-clip", "narrow-stress-open-clip", "stress-open-short", "stress-open-unloaded", "stress-open-deferred", "stress-open-empty", "stress-open-cursor", "stress-open-rtl"]
  readonly property var rowsStates: ["stress-rows-notes", "wide-stress-rows-notes", "narrow-stress-rows-notes", "stress-rows-all-read", "narrow-stress-rows-all-read", "stress-rows-read-cursor", "stress-rows-rtl", "stress-rows-assignee"].concat(rowsOpenStates)

  // The reading pane's own states, all Wide with the realistic inbox:
  //   -pane-quote          #5102 with the newest comment's quoted mail shown
  //   -pane-unread         #5102 marked as unread again ("Mark as read" shows)
  //   -pane-close-cursor   the keyboard cursor on "Hide ticket"
  //   -pane-newer          #5102 updated again, its newer comments not loaded yet: the note at the conversation's end
  //   -pane-long           #5110 (PaneData.js): a long subject, long names, a comment of over 40 lines
  //   -pane-long-clip      the same, scrolled to where the long comment is cut
  //   -pane-long-open      the same with everything unfolded, at the long comment's end
  //   -pane-long-end       the same at the conversation's end: an own reply, a note from a long name,
  //                        a sender that is a mail address, a forwarded mail (not folded)
  readonly property var paneStates: ["wide-stress-pane-quote", "wide-stress-pane-unread", "wide-stress-pane-close-cursor", "wide-stress-pane-newer", "wide-stress-pane-long", "wide-stress-pane-long-clip", "wide-stress-pane-long-open", "wide-stress-pane-long-end"]

  readonly property var overviewStates: [
    // The realistic inbox: after "7 more need a reply" was pressed, that list
    // scrolled to its end, the keyboard cursor on its tenth row (scrolled
    // into view), and folded again from there ("Show less": the cursor moves
    // to the last row that stays).
    "wide-stress-overview-all", "wide-stress-overview-all-end", "wide-stress-overview-all-focused", "wide-stress-overview-folded",
    // The first screen scrolled as far as it goes, and the keyboard cursor on a row.
    "wide-stress-overview-end", "wide-stress-overview-focused",
    // The realistic inbox plus OverviewData.js: Urgent and High tickets that
    // have waited more than an hour (red waits), a very long group name and
    // more than five groups; the same scrolled to the groups.
    "wide-stress-overview-late", "wide-stress-overview-late-end",
    // The tidy inbox: everything answered, and nothing known yet (the comments
    // of the only open ticket haven't loaded).
    "wide-overview-answered", "wide-overview-unknown"]

  readonly property var shellStates: [
    // The account's states: what the empty list says for each.
    "acct-signed-out", "acct-checking", "acct-waiting", "acct-expired", "acct-error", "acct-unavailable", "wide-acct-expired", "wide-acct-error", "narrow-acct-error",
    // An empty list with something to say in the band or the notice bar.
    "empty-outside-schedule", "hide-read-done", "wide-hide-read-done",
    // The notice bar: a failed refresh, held updates, all forms at once, and after "Show".
    "offline-long", "stress-offline", "wide-stress-offline", "narrow-stress-offline", "wide-save-error", "stress-pending", "wide-stress-pending", "stress-notices", "wide-stress-notices", "stress-shown", "wide-stress-shown",
    // Settings: the first run with the account's info note open, an account that can't
    // sign in, and Settings opened over the tall Wide inbox.
    "connection-info", "settings-acct-error", "wide-settings-acct-error", "narrow-settings-acct-error", "wide-stress-settings"]

  property var previewStates: baseStates.concat(rowsStates, paneStates, overviewStates, shellStates)
  property string previewState: "tickets"
  property int settleMs: 900
  readonly property var popup: previewPopup
  // Wide: the list and the reading pane (Panel.qml's wideWidth).
  readonly property bool wide: previewState.indexOf("wide") === 0
  readonly property bool stress: previewState.indexOf("stress") >= 0
  // "loading" and "wide-loading" are the same state in the two sizes.
  function at(name) {
    return previewState === name || previewState === "wide-" + name
  }
  function among(names) {
    for (let i = 0; i < names.length; i++)
      if (at(names[i]))
        return true
    return false
  }

  function many() {
    var list = Fixtures.tickets()
    for (var i = 1; i <= 10; i++)
      list = list.concat([Fixtures.update(i, true)[0]])
    return list
  }
  // Loads the realistic inbox plus `extra` tickets, with the read markers of
  // a used inbox (Stress.READ) and `extraRead` ({ ticket id: comment id }).
  function loadStress(extra, extraRead) {
    var store = Plugin.TicketStore
    store.loadFixtures(Stress.tickets().concat(extra || []))
    const read = Object.assign({}, Stress.READ, extraRead || {})
    for (const id in read)
      store.state.read[id] = {
        revision: read[id],
        at: Stress.NOW
      }
    store.sync()
  }
  // Presses `m` on the open ticket until nothing more unfolds.
  Timer {
    id: unfold
    property int left: 0
    property string ticketId: ""
    interval: 40
    repeat: true
    onTriggered: {
      var view = preview.popup.ensureBody()
      var found = Plugin.TicketStore.ticketById(ticketId)
      var row = found ? view.repeater.itemAt(found.index) : null
      left -= 1
      if (!row || !row.showMore() || left <= 0)
        stop()
    }
  }
  function unfoldTicket(id) {
    unfold.ticketId = id
    unfold.left = 20
    unfold.start()
  }

  function applyState() {
    var view = popup.ensureBody()
    if (!view)
      return
    var store = Plugin.TicketStore
    var account = Plugin.ZendeskAccount
    unfold.stop()
    view.closeReading()
    view.editingSettings = false
    view.wide = preview.wide
    // The ⋯ menu: Snooze, then Settings.
    if (at("menu"))
      Qt.callLater(function () {
        view.band.openMenu(false)
      })
    // Rows are dated against the fixtures' time, not the render's.
    view.fixedNow = Fixtures.NOW
    store.openUrl = function (url) {
      console.log("preview: would open " + url)
    }
    store.hideRead = at("hide-read") || at("stress-hide-read")
    store.unreadFirst = at("stress-unread-first")
    store.groupWaiting = !at("stress-ungrouped")
    // An empty week with the schedule on is "outside" at any time.
    store.scheduleEnabled = at("outside-schedule")
    store.week = ["", "", "", "", "", "", ""]
    // Snoozed from the ⋯ menu, for the next eight hours.
    store.scheduleOverride = at("snoozed") ? {
      on: false,
      until: Date.now() + 8 * 3600000
    } : null
    store.readSaveFailed = false

    var signedIn = !at("signed-out") && !at("connection")
    var sample = among(["signed-out", "loading", "failed", "empty"]) ? null : at("scrolling") ? many() : preview.stress ? Stress.tickets() : Fixtures.tickets()
    if (previewState === "wide-empty")
      sample = []
    store.loadFixtures(sample)
    if (previewState === "empty")
      store.loadFixtures([])
    account.address = signedIn ? "acme" : ""
    account.clientId = signedIn ? "foamy_zendesk" : ""
    account.port = signedIn ? 47823 : 0
    account.state = signedIn ? "signed_in" : "not_configured"
    account.error = ""
    account.user = signedIn ? {
      name: "Alex",
      email: "alex@acme.example"
    } : null
    account.verified = signedIn
    var week = {
      scheduleEnabled: true,
      scheduleOutsideMode: "mute",
      scheduleMonday: "08:00-16:00",
      scheduleTuesday: "08:00-16:00",
      scheduleWednesday: "08:00-16:00",
      scheduleThursday: "08:00-16:00",
      scheduleFriday: "08:00-14:00"
    }
    view.preferences = signedIn ? {
      zendeskAddress: "acme",
      oauthClientId: "foamy_zendesk"
    } : ({})
    if (at("schedule"))
      view.preferences = Object.assign({}, view.preferences, week)
    if (preview.wide)
      view.preferences = Object.assign({}, view.preferences, {
        panelWidth: "wide"
      })
    if (at("failed") || at("offline"))
      store.error = "Can't reach Zendesk. Check your connection."
    if (at("truncated"))
      store.ticketsTruncated = true
    if (at("notice"))
      store.notice = store.openFailedText
    if (at("save-error"))
      store.readSaveFailed = true
    view.list.contentY = 0

    if (preview.stress) {
      // Read markers of a used inbox (Stress.READ), then the list again.
      for (const id in Stress.READ)
        store.state.read[id] = {
          revision: Stress.READ[id],
          at: Stress.NOW
        }
      store.sync()
    } else if (sample && !at("all-read")) {
      // A typical inbox: #4818 (waiting on its requester) was read earlier.
      store.markRead("4818")
    }
    if (among(["expanded", "pending", "narrow-expanded"]) || previewState === "wide-ticket" || previewState === "wide-conversation")
      view.toggleTicket("4821")
    if (at("pending"))
      Qt.callLater(function () {
        store.receive(Fixtures.update(1, false))
      })
    if (at("all-read"))
      view.markAllRead()
    if (previewState === "grouped-expanded")
      view.toggleTicket("4818")
    if (among(["settings", "connection", "schedule"])) {
      view.editingSettings = true
      if (!at("settings"))
        Qt.callLater(function () {
          view.settingsPage.flickable.contentY = 9999
          view.settingsPage.flickable.returnToBounds()
        })
    }
    if (previewState === "focused" || previewState === "stress-focused")
      view.cursor.index = view.firstTicketStop
    // The keyboard cursor on a read ticket's "Mark as unread" (hidden at rest).
    if (previewState === "mark-unread-cursor") {
      const read = store.ticketById("4818")
      view.cursor.index = view.firstTicketStop + read.index * view.stopsPerTicket + 1
    }
    // The overview's first waiting ticket under the keyboard cursor.
    if (previewState === "wide-focused")
      view.cursor.index = view.paneFirstStop
    // The keyboard cursor on the selected ticket's conversation.
    if (previewState === "wide-conversation")
      view.cursor.index = view.conversationStop
    if (at("scrolling"))
      Qt.callLater(function () {
        view.list.contentY = 160
      })

    // The realistic inbox.
    if (previewState === "stress-scrolled")
      Qt.callLater(function () {
        view.list.contentY = 430
      })
    if (previewState === "stress-bottom" || previewState === "wide-stress-list-bottom")
      Qt.callLater(function () {
        view.list.contentY = 99999
        view.list.returnToBounds()
      })
    if (previewState === "stress-open" || previewState === "stress-open-all" || previewState === "wide-stress-ticket" || previewState === "wide-stress-ticket-scrolled")
      view.toggleTicket("5102")
    if (previewState === "stress-open-all")
      unfoldTicket("5102")
    // A short, read, one-line ticket opened in place.
    if (previewState === "stress-open-other")
      view.toggleTicket("5091")
    if (previewState === "wide-stress-ticket-scrolled")
      Qt.callLater(function () {
        view.pane.conversation.contentY = 620
      })
    if (previewState === "wide-stress-internal")
      view.toggleTicket("5098")
    if (previewState === "wide-stress-unassigned")
      view.toggleTicket("5103")
    if (previewState === "wide-stress-nocomments")
      view.toggleTicket("5090")

    // The prototypes' own states.
    applyRows(view, store, account)
    applyPane(view, store, account)
    applyOverview(view, store, account)
    applyShell(view, store, account)
  }

  // Called for every state, after the base state is set. `view` is the
  // InboxView, `store` the TicketStore, `account` the ZendeskAccount.
  function applyRows(view, store, account) {
    if (previewState.indexOf("stress-rows-notes") >= 0 || previewState.indexOf("stress-rows-all-read") >= 0)
      preview.loadStress(RowsData.tickets(), RowsData.READ)
    // Each ticket marked read by itself: Mark all as read would put its
    // notice over the last rows.
    if (previewState.indexOf("stress-rows-all-read") >= 0) {
      const ids = []
      for (let i = 0; i < store.count; i++)
        ids.push(store.tickets.get(i).id)
      ids.forEach(function (id) {
        store.markRead(id)
      })
    }
    if (previewState === "stress-rows-assignee")
      preview.loadStress(RowsData.assignedElsewhere(), {})
    // #5049 is read and waits for the agent: a one-line row.
    if (previewState === "stress-rows-read-cursor")
      view.cursor.index = view.firstTicketStop + store.ticketById("5049").index * view.stopsPerTicket + 1
    // The host mirrors the popup body for a right-to-left language.
    view.LayoutMirroring.enabled = previewState === "stress-rows-rtl" || previewState === "stress-open-rtl"
    view.LayoutMirroring.childrenInherit = true
    applyOpenCard(view, store)
  }
  // Stage 2: the states of the open card. `unfold`: press "show more" until
  // everything shows; `scroll`: where the list goes once the card has laid
  // out ("end": the card's end at the list's end; "mid": 400 px into it).
  function openCard(view, id, unfold, scroll) {
    view.toggleTicket(id)
    if (unfold)
      preview.unfoldTicket(id)
    rowsScroll.ticketId = id
    rowsScroll.where = scroll || "top"
    rowsScroll.restart()
  }
  function applyOpenCard(view, store) {
    rowsScroll.stop()
    var state = previewState.replace(/^narrow-/, "")
    if (rowsOpenStates.indexOf(previewState) < 0)
      return
    if (["stress-open-names", "stress-open-clip", "stress-open-deferred", "stress-open-empty"].indexOf(state) >= 0)
      preview.loadStress(RowsData.openCard(), RowsData.OPEN_READ)
    if (state === "stress-open-scrolled")
      openCard(view, "5102", true, "end")
    else if (state === "stress-open-mid")
      openCard(view, "5102", true, "mid")
    else if (state === "stress-open-leaving")
      openCard(view, "5102", true, "leaving")
    else if (state === "stress-open" || state === "stress-open-rtl")
      openCard(view, "5102", false, "top")
    else if (state === "stress-open-names")
      openCard(view, "5120", true, "top")
    else if (state === "stress-open-notes")
      openCard(view, "5098", false, "top")
    else if (state === "stress-open-note-first") {
      preview.loadStress(RowsData.tickets(), RowsData.READ)
      openCard(view, "5110", false, "top")
    } else if (state === "stress-open-clip")
      openCard(view, "5121", false, "top")
    else if (state === "stress-open-short")
      openCard(view, "5091", false, "top")
    else if (state === "stress-open-unloaded")
      openCard(view, "5090", false, "end")
    else if (state === "stress-open-deferred") {
      // The next fetch: #5122 changed and its comments were put off.
      store.receive(Stress.tickets().concat(RowsData.openCard().map(function (ticket) {
        return ticket.id === "5122" ? RowsData.deferred(ticket) : ticket
      })))
      openCard(view, "5122", false, "top")
    } else if (state === "stress-open-empty")
      openCard(view, "5123", false, "top")
    else if (state === "stress-open-cursor") {
      openCard(view, "5102", false, "top")
      view.cursor.index = view.firstTicketStop + store.ticketById("5102").index * view.stopsPerTicket + 1
    }
  }
  // Scrolls the list once the open card has unfolded and laid out.
  Timer {
    id: rowsScroll
    property string ticketId: ""
    property string where: "top"
    interval: 420
    onTriggered: {
      var view = preview.popup.ensureBody()
      var found = Plugin.TicketStore.ticketById(ticketId)
      var row = found ? view.repeater.itemAt(found.index) : null
      if (!row)
        return
      var list = view.list
      var card = row.bodyItem.parent
      var top = card.mapToItem(list.contentItem, 0, 0).y
      var limit = Math.max(0, list.contentHeight - list.height)
      if (where === "end")
        list.contentY = Math.max(0, Math.min(limit, top + card.height + FoamyStyle.gap - list.height))
      else if (where === "mid")
        list.contentY = Math.max(0, Math.min(limit, top + 400))
      else if (where === "leaving")
        list.contentY = Math.max(0, Math.min(limit, top + card.height - 90))
      else
        list.contentY = Math.max(0, Math.min(limit, top - (row.sectionHeader.visible ? row.sectionHeader.height : 0) - FoamyStyle.gap))
    }
  }
  // The first item named `name` (an objectName) under `item`, or null.
  function findNamed(item, name) {
    if (!item)
      return null
    if (item.objectName === name)
      return item
    for (const child of item.children || []) {
      const found = findNamed(child, name)
      if (found)
        return found
    }
    return null
  }

  // What a pane state does once its ticket is shown, one step per tick, so
  // the conversation lays out in between.
  property var paneSteps: []
  Timer {
    id: paneTick
    interval: 120
    repeat: true
    onTriggered: {
      var step = preview.paneSteps.shift()
      if (step)
        step()
      if (!preview.paneSteps.length)
        stop()
    }
  }
  // Scrolls the conversation so the bottom of the comment `revision` is
  // `gap` px above the pane's bottom edge.
  function paneRevealEnd(view, revision, gap) {
    var conversation = view.pane.conversation
    var item = findNamed(view.pane.comments, "comment-" + revision)
    if (!item)
      return
    var bottom = item.mapToItem(conversation.contentItem, 0, item.height).y
    conversation.contentY = Math.max(0, Math.min(conversation.contentHeight - conversation.height, bottom + gap - conversation.height))
  }
  function applyPane(view, store, account) {
    var pane = view.pane
    paneTick.stop()
    paneSteps = []
    if (previewState.indexOf("wide-stress-pane-") !== 0)
      return
    var longTicket = previewState.indexOf("wide-stress-pane-long") === 0
    if (longTicket)
      loadStress(PaneData.tickets(), PaneData.READ)
    if (previewState === "wide-stress-pane-newer") {
      // #5102 changed again and the helper left its comments for the next
      // update (it fetches a bounded number per run): the earlier ones stay.
      const again = Stress.tickets()
      again[0].updated_at = new Date(Stress.NOW + 60000).toISOString()
      delete again[0].comments
      store.receive(again)
    }
    view.toggleTicket(longTicket ? "5110" : "5102")
    var steps = []
    if (previewState === "wide-stress-pane-newer")
      steps.push(function () {
        var conversation = pane.conversation
        conversation.contentY = Math.max(0, conversation.contentHeight - conversation.height)
      })
    // `m`, as the keyboard would press it: the first fold in view opens.
    if (previewState === "wide-stress-pane-quote")
      steps.push(function () {
        pane.showMore()
      })
    if (previewState === "wide-stress-pane-unread")
      view.toggleRead("5102", view.selected.index)
    if (previewState === "wide-stress-pane-close-cursor")
      view.cursor.index = view.paneFirstStop + 2
    if (previewState === "wide-stress-pane-long-clip")
      steps.push(function () {
        paneRevealEnd(view, 51102, 12)
      })
    if (previewState === "wide-stress-pane-long-end")
      steps.push(function () {
        paneRevealEnd(view, 51098, 12)
      })
    if (previewState === "wide-stress-pane-long-open") {
      // Everything unfolds (the long comment, then the quoted mail), then the
      // view goes to the end of the comment with the quote.
      for (let i = 0; i < 3; i++)
        steps.push(function () {
          pane.showMore()
        })
      steps.push(function () {
        paneRevealEnd(view, 51102, 12)
      })
    }
    if (steps.length) {
      paneSteps = steps
      paneTick.start()
    }
  }

  Timer {
    id: overviewKeys
    interval: 120
    onTriggered: {
      var view = preview.popup.ensureBody()
      view.cursor.index = view.paneFirstStop + 9
      view.reveal()
    }
  }
  function applyOverview(view, store, account) {
    var name = previewState
    var scroll = view.overview.scroll
    // The store keeps what "N more need a reply" showed: every state starts folded.
    store.expandOverview(false)
    scroll.contentY = 0
    if (name.indexOf("wide-stress-overview-late") === 0)
      loadStress(OverviewData.tickets(), OverviewData.READ)
    // The agent wrote last on every open ticket, and has read them all:
    // nothing needs a reply.
    if (name === "wide-overview-answered") {
      store.loadFixtures(OverviewData.answered())
      store.markRead("4821")
      store.markRead("4818")
    }
    // The only open ticket's comments were deferred by the helper.
    if (name === "wide-overview-unknown")
      store.loadFixtures(OverviewData.unknown())
    // A click on the link itself, as the pointer does it.
    var more = findNamed(view.overview, "awaitingMore")
    if (name.indexOf("wide-stress-overview-all") === 0 || name === "wide-stress-overview-folded")
      more.clicked()
    if (name === "wide-stress-overview-focused")
      view.cursor.index = view.paneFirstStop + 1
    // The keyboard: the cursor on the tenth row, which the view scrolls to
    // (once the new rows are laid out, as a key press finds them).
    overviewKeys.stop()
    if (name === "wide-stress-overview-all-focused")
      overviewKeys.start()
    if (name === "wide-stress-overview-end" || name === "wide-stress-overview-all-end" || name === "wide-stress-overview-late-end" || name === "wide-stress-overview-folded")
      Qt.callLater(function () {
        scroll.contentY = 99999
        scroll.returnToBounds()
        // From the end of the long list, the cursor on its tenth row: "Show less".
        if (name === "wide-stress-overview-folded") {
          view.cursor.index = view.paneFirstStop + 9
          more.clicked()
        }
      })
  }

  // The account in `state`, with nothing loaded. `configured`: an address and
  // a client ID are saved.
  function shellAccount(view, store, account, state, error, configured) {
    store.loadFixtures(null)
    account.address = configured ? "acme" : ""
    account.clientId = configured ? "foamy_zendesk" : ""
    account.port = configured ? 47823 : 0
    account.user = null
    account.verified = false
    account.error = error
    account.state = state
    view.preferences = Object.assign(configured ? {
      zendeskAddress: "acme",
      oauthClientId: "foamy_zendesk"
    } : ({}), preview.wide ? {
      panelWidth: "wide"
    } : ({}))
  }
  // Opens Settings once the inbox is laid out, as a user does: the Wide card
  // then keeps the height the inbox gave it.
  Timer {
    id: shellSettings
    interval: 250
    onTriggered: preview.popup.ensureBody().editingSettings = true
  }
  function applyShell(view, store, account) {
    // "wide-acct-error" and "narrow-acct-error" are "acct-error" in another size.
    var name = previewState.replace(/^(wide|narrow)-/, "")
    shellSettings.stop()
    if (name === "stress-settings")
      shellSettings.restart()
    var offline = FoamyI18n.t(ShellData.OFFLINE)
    var keyring = FoamyI18n.t(ShellData.KEYRING_SAVE, [ShellData.KEYRING_REASON])
    // The account section's (i) note stays as the last state left it.
    var accountNote = findNamed(view.settingsPage, "zendeskSection").infoNote
    accountNote.close()

    // The base states' error, through the catalog as the store does, so the
    // Norwegian render shows the Norwegian text.
    if (name === "failed" || name === "offline")
      store.error = offline
    // An inbox that can't be refreshed is old: the footer says how old.
    if (["offline", "offline-long", "stress-offline", "stress-notices"].indexOf(name) >= 0)
      store.lastUpdated = Date.now() - 190 * 60000
    // The base "notice" state loses its notice to the markRead() that follows it.
    if (name === "notice")
      store.notice = store.openFailedText
    // Settings open at the top, where the account is now.
    if (name === "connection")
      Qt.callLater(function () {
        view.settingsPage.flickable.contentY = 0
      })

    if (name === "acct-signed-out")
      shellAccount(view, store, account, "signed_out", "", true)
    if (name === "acct-checking")
      shellAccount(view, store, account, "checking", "", true)
    if (name === "acct-waiting")
      shellAccount(view, store, account, "waiting", "", true)
    if (name === "acct-expired")
      shellAccount(view, store, account, "expired", "", true)
    if (name === "acct-error" || name === "settings-acct-error")
      shellAccount(view, store, account, "error", keyring, true)
    if (name === "acct-unavailable")
      shellAccount(view, store, account, "unavailable", FoamyI18n.t("This plugin's helper isn't available for this CPU."), true)
    if (name === "settings-acct-error")
      view.editingSettings = true
    // The first run: Settings as "Open settings" shows them, the (i) note read.
    if (name === "connection-info") {
      shellAccount(view, store, account, "not_configured", "", false)
      view.editingSettings = true
      accountNote.open()
    }

    // Signed in, nothing listed, outside the schedule (an empty week, as the
    // base state): the band has only the schedule left to say. Snoozed reads
    // "Snoozed" the same way.
    if (name === "empty-outside-schedule") {
      store.loadFixtures([])
      store.scheduleEnabled = true
    }
    // Read tickets are hidden and everything was just marked as read.
    if (name === "hide-read-done") {
      store.hideRead = true
      view.markAllRead()
    }

    if (name === "offline-long")
      store.error = FoamyI18n.t(ShellData.NO_READ_ACCESS)
    if (name === "stress-offline")
      store.error = offline
    // A ticket is open and the next inbox waits: a new reply on it and a new ticket.
    if (["stress-pending", "stress-notices", "stress-shown"].indexOf(name) >= 0) {
      view.toggleTicket("5102")
      Qt.callLater(function () {
        store.receive(ShellData.updated(Stress.tickets(), Stress.BASE))
        // Every form of the bar at once: the updates, an Undo and an error.
        if (name === "stress-notices") {
          view.markAllRead()
          store.error = offline
        }
        // The "Show" link was used.
        if (name === "stress-shown")
          Qt.callLater(function () {
            view.showUpdates()
          })
      })
    }
  }

  onPreviewStateChanged: Qt.callLater(applyState)
  Component.onCompleted: Qt.callLater(applyState)
  FoamyPopup {
    id: previewPopup
    anchorItem: preview.anchorItem
    bar: preview.bar
    open: true
    // As Panel.qml (a change here must be mirrored there). Small is as tall
    // as its content. Wide is 640 high whatever it shows (a ticket, the
    // overview, Settings) and grows with the inbox, the view's
    // inboxImplicitHeight, up to 70 % of the screen as foamy-todoist's Wide.
    // The cap never goes under the 640 Wide starts at (a screen under 915
    // high): there only the screen itself limits the card, as before.
    contentWidth: fittedContentWidth(preview.previewState.indexOf("narrow") === 0 ? 320 : preview.wide ? Commons.Style.space(880) : FoamyStyle.popupWidth)
    maxHeight: preview.wide ? Math.max(Math.round(screenH * 0.7), FoamyStyle.popupMaxHeight + verticalContentInset) : 0
    contentHeight: fittedContentHeight(Math.max(preview.wide ? Math.max(FoamyStyle.popupMaxHeight, bodyItem ? (bodyItem as Plugin.InboxView).inboxImplicitHeight : 0) : bodyImplicitHeight, menuReserve), maxHeight)
    body: Component {
      Plugin.InboxView {}
    }
  }
}
