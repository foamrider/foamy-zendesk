pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/FoamyNative.js" as FoamyNative
import "Model.js" as Model
import "Schedule.js" as Schedule

// The inbox, shared by every bar instance: one fetch loop and one read-state
// file per shell. foamy-zendesk-helper `fetch` does the Zendesk requests;
// read markers live in the file it names (`$XDG_STATE_HOME/foamy-zendesk/`).
QtObject {
  id: store

  readonly property string pluginDir: FoamyNative.localPath(Qt.resolvedUrl("."))
  property var state: Model.empty()
  // A fetch reply that arrived while a ticket was open; applied on collapse.
  property var pending: null
  property int pendingChanges: 0
  // The last "Mark all as read", kept until any other change so it can be undone.
  property var lastBatch: []
  readonly property bool canUndoMarkAll: lastBatch.length > 0
  // Why the last fetch failed (the tickets shown are the last good ones).
  property string error: ""
  property string notice: ""
  property double lastUpdated: 0
  // When the next check after a failure runs (0 when none is due).
  property double retryAt: 0
  // The inbox has been filled at least once for this account.
  property bool loaded: false
  readonly property bool loading: fetchProcess.running
  property int failures: 0
  property bool helperMissing: false

  // Settings (pushed by the panels from the saved settings).
  property bool hideRead: false
  property bool unreadFirst: false
  property bool groupWaiting: true
  property int refreshSeconds: 60
  // Desktop notifications: "off", "mine" (assigned to you) or "all".
  property string notify: "off"
  onHideReadChanged: sync()
  onUnreadFirstChanged: sync()
  onGroupWaitingChanged: sync()

  // Weekly schedule: outside it the bar widget dims or hides and nothing is
  // fetched in the background; opening the popup still refreshes on demand.
  // The popup's snooze/resume overrides it while it lasts (Schedule.toggled).
  property bool scheduleEnabled: false
  property var week: []
  property var scheduleOverride: null
  readonly property bool overriding: !!scheduleOverride && clock.date.getTime() < scheduleOverride.until
  property FoamyWallClock clock: FoamyWallClock { enabled: store.scheduleEnabled || store.overriding }
  readonly property bool withinSchedule: Schedule.effective(clock.date, scheduleEnabled, week, scheduleOverride)
  // Snoozed from the popup (not just outside the scheduled hours).
  readonly property bool snoozed: overriding && !scheduleOverride.on

  // Snoozing is kept beside the read markers, never in shell.json: it is not a setting.
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  property string overridePath: stateHome + "/foamy-zendesk/schedule-override.json"
  property FileView overrideFile: FileView {
    path: store.overridePath
    atomicWrites: true
    printErrors: false
    onLoaded: store.scheduleOverride = Schedule.parseOverride(text(), Date.now())
  }
  function toggleSnooze() {
    scheduleOverride = Schedule.toggled(new Date(), scheduleEnabled, week, scheduleOverride);
    clock.refresh();
    overrideFile.setText(Schedule.serializeOverride(scheduleOverride));
  }

  // Preview and tests: sample tickets, no helper, no file.
  property bool fixtures: false
  // Opens a ticket in the browser; tests replace it.
  property var openUrl: function(url) { Qt.openUrlExternally(url); }

  readonly property string account: ZendeskAccount.signedIn ? Model.host(ZendeskAccount.address) + " " + ZendeskAccount.clientId : ""
  // Signed in with a working helper: refreshing on demand is possible.
  readonly property bool connected: !fixtures && account !== "" && !helperMissing
  // Also within the schedule: the inbox is checked in the background.
  readonly property bool active: connected && withinSchedule
  onAccountChanged: if (!fixtures) restart()
  onActiveChanged: if (active) refresh()

  // Index of the first ticket in the "Waiting on others" section, or -1.
  property int firstWaitingIndex: -1
  property int waitingCount: 0
  property int unreadCount: 0
  signal resetting()
  // Listed tickets; unreadCount is what the bar shows.
  readonly property int count: tickets.count
  readonly property bool reading: FoamyShared.demandCount("zendesk-reading") > 0
  property ListModel tickets: ListModel {}

  function sync() {
    var held = {};
    for (var key of Object.keys(holds)) held[holds[key].id] = holds[key].read;
    var wanted = Model.visible(state, { hideRead: hideRead, unreadFirst: unreadFirst, groupWaiting: groupWaiting, held: held });
    var waitingAt = wanted.findIndex(function(ticket) { return ticket.section === "waiting"; });
    waitingCount = waitingAt < 0 ? 0 : wanted[waitingAt].sectionSize;
    unreadCount = wanted.filter(function(ticket) { return !ticket.read; }).length;
    for (var i = 0; i < wanted.length; i++) {
      var at = -1;
      for (var j = i; j < tickets.count; j++) if (tickets.get(j).id === wanted[i].id) { at = j; break; }
      if (at < 0) tickets.insert(i, wanted[i]);
      else { if (at !== i) tickets.move(at, i, 1); tickets.set(i, wanted[i]); }
    }
    if (tickets.count > wanted.length) tickets.remove(wanted.length, tickets.count - wanted.length);
    firstWaitingIndex = waitingAt;
  }

  // A new inbox from Zendesk (or the tests). Frozen while anyone is reading.
  function receive(list) {
    if (reading) {
      pending = list;
      pendingChanges = list.filter(function(raw) {
        var current = state.tickets[String(raw.id)];
        return !current || current.updatedAt !== raw.updated_at;
      }).length;
      return;
    }
    pending = null;
    pendingChanges = 0;
    try {
      Model.applySnapshot(state, list);
      loaded = true;
      sync();
      saveRead();
    } catch (failure) { error = FoamyI18n.t("Zendesk sent an unexpected reply."); return; }
    announce();
  }
  function flush() { if (!reading && pending) receive(pending); }
  onReadingChanged: if (!reading) Qt.callLater(flush)

  function changed() { lastBatch = []; notice = ""; sync(); saveRead(); }
  function markRead(id) { if (Model.markRead(state, id)) changed(); }
  // The ticket each popup is reading stays where it was (`read`: whether it was
  // read when opened) until it is closed. `id` "" releases the popup's hold.
  property var holds: ({})
  function hold(key, id, read) {
    var next = Object.assign({}, holds);
    if (id) next[key] = { id: String(id), read: read === true };
    else if (next[key]) delete next[key];
    else return;
    holds = next;
    sync();
  }
  function ticketById(id) {
    for (var i = 0; i < tickets.count; i++) if (tickets.get(i).id === id) return { index: i, ticket: tickets.get(i) };
    return null;
  }
  function markUnread(id) { if (Model.markUnread(state, id)) changed(); }
  function toggleRead(id) { if (!Model.markRead(state, id)) Model.markUnread(state, id); changed(); }
  function markAllRead() {
    var batch = Model.markAllRead(state);
    if (!batch.length) return;
    sync();
    saveRead();
    lastBatch = batch;
    notice = FoamyI18n.tn("%1 marked as read", batch.length);
  }
  function undoMarkAll() { Model.restore(state, lastBatch); changed(); }
  function openTicket(id) {
    var url = Model.ticketUrl(ZendeskAccount.address, id);
    if (url) openUrl(url);
  }

  // ---- desktop notifications ------------------------------------------------
  // The newest comment from someone else seen on each ticket (Model.arrivals),
  // kept whether or not notifications are on, so turning them on announces
  // nothing old. null until this account's first inbox, which sets it quietly:
  // a shell start or a sign-in never announces the whole inbox.
  property var seen: null
  // A popup is open on some monitor: its inbox shows what came in.
  readonly property bool watching: FoamyShared.demandCount("zendesk") > 0
  // Sends a notification (an argv); tests replace it.
  property var sendNotification: function(argv) { Quickshell.execDetached(argv); }
  function announce() {
    var first = seen === null;
    if (first) seen = {};
    var fresh = Model.arrivals(state, seen, notify === "all" ? "all" : "mine");
    if (first || notify === "off" || watching || !withinSchedule || !fresh.length) return;
    sendNotification(notificationCommand(fresh));
  }
  // One ticket: its subject and the newest comment from someone else; a click
  // opens it in the inbox. Several: one notification listing them; a click
  // opens the inbox. The click and the button use Omarchy's notification hints.
  function notificationCommand(list) {
    var summary, body, click, actions = [];
    if (list.length === 1) {
      var ticket = list[0];
      var latest = ticket.history.find(function(item) { return !item.mine; });
      summary = ticket.subject;
      body = Model.notificationText(latest.sender + ": " + latest.body, 280);
      click = ["omarchy-shell", "-q", "foamy.zendesk", "show", ticket.id];
      var url = Model.ticketUrl(ZendeskAccount.address, ticket.id);
      if (url) actions.push({ label: FoamyI18n.t("View in Zendesk"), argv: ["xdg-open", url] });
    } else {
      var shown = list.slice(0, 4);
      summary = FoamyI18n.tn("%1 updated Zendesk tickets", list.length);
      body = shown.map(function(item) { return Model.notificationText(item.subject, 80); })
        .concat(list.length > shown.length ? [FoamyI18n.tn("and %1 more", list.length - shown.length)] : []).join("\n");
      click = ["omarchy-shell", "-q", "foamy.zendesk", "open"];
    }
    var argv = ["notify-send", "--app-name=Zendesk", "--urgency=normal",
      "--hint=string:omarchy-glyph:\u{f0516}", "--hint=string:omarchy-exec-argv:" + JSON.stringify(click)];
    if (actions.length) argv.push("--hint=string:omarchy-actions:" + JSON.stringify(actions));
    return argv.concat(["--", summary, body]);
  }

  // ---- fetching -------------------------------------------------------------
  property bool refreshAgain: false
  function refresh() {
    if (!connected) return;
    if (fetchProcess.running) { refreshAgain = true; return; }
    fetchProcess.input = JSON.stringify({ known: Model.known(state) }) + "\n";
    fetchProcess.command = ["timeout", "--kill-after=2s", "150s"].concat(FoamyNative.command(pluginDir, "foamy-zendesk-helper",
      ["fetch", "--address", ZendeskAccount.address, "--client-id", ZendeskAccount.clientId]));
    fetchProcess.stdinEnabled = true;
    fetchProcess.running = true;
  }
  // Opening the popup refreshes an inbox older than this.
  function refreshIfStale(maxAgeMs) {
    if (connected && !loading && Date.now() - lastUpdated > maxAgeMs) refresh();
  }
  function fetched(text, code) {
    if (FoamyNative.unavailable(code)) {
      helperMissing = true;
      error = FoamyI18n.t(FoamyNative.UNAVAILABLE_TEXT);
      return;
    }
    var reply = null;
    try { reply = JSON.parse(String(text).trim().split("\n").pop()); } catch (e) {}
    if (reply && reply.ok && Array.isArray(reply.tickets)) {
      error = "";
      failures = 0;
      retryAt = 0;
      lastUpdated = Date.now();
      if (typeof reply.state_path === "string" && reply.state_path !== readPath) {
        // The read markers come first, or every ticket would flash unread.
        waitingSnapshot = reply.tickets;
        readPath = reply.state_path;
        return;
      }
      if (!readReady) { waitingSnapshot = reply.tickets; return; }
      receive(reply.tickets);
      return;
    }
    failures++;
    error = reply && reply.error ? ZendeskAccount.helperText(reply.error)
      : code === 124 ? FoamyI18n.t("Zendesk didn't answer in time.") : FoamyI18n.t("Can't reach Zendesk. Check your connection.");
    // The sign-in itself went bad: let the account say so.
    if (reply && (reply.code === "EXPIRED" || reply.code === "SIGNED_OUT")) ZendeskAccount.check();
    // Count the backed-off wait from this failure.
    if (pollTimer.running) { pollTimer.restart(); retryAt = Date.now() + pollTimer.interval; }
  }

  property Process fetchProcess: Process {
    property string input: ""
    onStarted: { write(input); stdinEnabled = false; }
    stdout: StdioCollector { id: fetchOutput; waitForEnd: true }
    onExited: function(code) {
      store.fetched(fetchOutput.text, code);
      if (store.refreshAgain) { store.refreshAgain = false; Qt.callLater(store.refresh); }
    }
  }

  // Every `refreshSeconds` while signed in and within the schedule; failures
  // back off (2×, 4×, … up to 15 minutes).
  property Timer pollTimer: Timer {
    running: store.active
    repeat: true
    interval: Math.min(900, store.refreshSeconds * Math.pow(2, Math.min(store.failures, 4))) * 1000
    onTriggered: store.refresh()
  }

  // ---- read state -------------------------------------------------------------
  property string readPath: ""
  property bool readReady: false
  property var waitingSnapshot: null
  function readLoaded(text) {
    state.read = Model.parseReadState(text);
    readReady = true;
    if (waitingSnapshot) { var list = waitingSnapshot; waitingSnapshot = null; receive(list); }
    else sync();
  }
  function saveRead() {
    if (!fixtures && readReady && readPath !== "") saveTimer.restart();
  }
  property Timer saveTimer: Timer {
    interval: 300
    onTriggered: readFile.setText(Model.serializeReadState(store.state))
  }
  property FileView readFile: FileView {
    path: store.readPath
    atomicWrites: true
    printErrors: false
    onLoaded: store.readLoaded(text())
    onLoadFailed: function(failure) {
      // No file yet: nothing read. Anything else: start empty, and don't
      // overwrite a file we couldn't read.
      if (failure !== FileViewError.FileNotFound) store.readPath = "";
      store.readLoaded("");
    }
  }

  // A different account (or signed out): forget the inbox, keep the files.
  function restart() {
    resetting();
    if (saveTimer.running) { saveTimer.stop(); readFile.setText(Model.serializeReadState(state)); }
    fetchProcess.running = false;
    state = Model.empty();
    pending = null; pendingChanges = 0; lastBatch = []; waitingSnapshot = null; seen = null;
    error = ""; notice = ""; loaded = false; lastUpdated = 0; failures = 0; retryAt = 0;
    readPath = ""; readReady = false;
    sync();
    if (active) refresh();
  }

  // Preview and tests only.
  function loadFixtures(list) {
    fixtures = true;
    resetting();
    state = Model.empty();
    pending = null; pendingChanges = 0; lastBatch = []; error = ""; notice = "";
    readReady = true;
    if (list) { Model.applySnapshot(state, list); loaded = true; lastUpdated = Date.now(); }
    else loaded = false;
    seen = null;
    if (list) announce();
    sync();
  }
}
