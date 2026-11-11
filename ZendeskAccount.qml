pragma Singleton
import QtQuick
import Quickshell.Io
import "kit"
import "kit/FoamyNative.js" as FoamyNative

// The Zendesk sign-in, shared by every bar instance. foamy-zendesk-helper
// does the OAuth work (PKCE, public client) and keeps the tokens in the
// keyring; QML only ever sees the outcome: who is signed in, or why not.
QtObject {
  id: account

  readonly property string pluginDir: FoamyNative.localPath(Qt.resolvedUrl("."))
  readonly property string helper: "foamy-zendesk-helper"

  // Pushed by the panels from the saved settings.
  property string address: ""
  property string clientId: ""
  property int port: 0
  readonly property bool configured: address !== "" && clientId !== "" && port > 0

  // not_configured, checking, signed_out, waiting (for the browser),
  // signed_in, expired, error, unavailable (no helper for this CPU).
  property string state: "not_configured"
  property var user: null
  // false while Zendesk can't be reached: the user shown is the saved one.
  property bool verified: false
  property string error: ""
  readonly property bool busy: statusProcess.running || loginProcess.running || logoutProcess.running
  readonly property bool signedIn: state === "signed_in"
  property bool checkAgain: false
  // Bumped by sign-out: a check that started before it answers for a sign-in
  // that is gone.
  property int signOuts: 0
  // Bumped by configure(): a helper started before it (a check, a sign-in
  // being stopped, a sign-out) answers for another address or client.
  property int configurations: 0
  // The helper's argv (after the timeout); tests replace it.
  property var helperCommand: function(args) { return FoamyNative.command(account.pluginDir, account.helper, args); }

  function configure(next) {
    if (next.address === address && next.clientId === clientId && next.port === port) return;
    configurations++;
    if (loginProcess.running) loginProcess.running = false;
    address = next.address;
    clientId = next.clientId;
    port = next.port;
    user = null;
    error = "";
    Qt.callLater(check);
  }

  function args(command, extra) {
    return [command, "--address", address, "--client-id", clientId].concat(extra || []);
  }
  function start(process, command, extra, limit) {
    process.command = ["timeout", "--kill-after=2s", limit].concat(helperCommand(args(command, extra)));
    process.configuration = configurations;
    process.running = true;
  }

  function check() {
    if (!configured) { state = "not_configured"; user = null; error = ""; return; }
    if (state === "unavailable" || loginProcess.running || logoutProcess.running) return;
    if (statusProcess.running) { checkAgain = true; return; }
    if (!signedIn) state = "checking";
    statusProcess.signOuts = signOuts;
    // Up to a minute for a keyring unlock prompt, then the Zendesk requests.
    start(statusProcess, "auth-status", [], "120s");
  }
  function signIn() {
    if (!configured || loginProcess.running || state === "unavailable") return;
    error = "";
    state = "waiting";
    loginProcess.lastLine = "";
    // The helper waits five minutes for the browser.
    start(loginProcess, "auth-login", ["--port", String(port)], "330s");
  }
  function cancelSignIn() {
    loginProcess.running = false;
  }
  function signOut() {
    if (!configured || logoutProcess.running) return;
    if (loginProcess.running) loginProcess.running = false;
    signOuts++;
    // Up to 30 seconds for a token refresh in flight to finish first.
    start(logoutProcess, "auth-logout", [], "120s");
  }

  // A helper `error`, translated: a catalog key, then the values for its
  // %1, %2… after U+001F separators.
  function helperText(message) {
    var parts = String(message || "").split("\u001f");
    return FoamyI18n.t(parts[0], parts.slice(1));
  }

  // One JSON reply from the helper.
  function apply(text, code) {
    if (FoamyNative.unavailable(code)) {
      state = "unavailable";
      error = FoamyI18n.t(FoamyNative.UNAVAILABLE_TEXT);
      return;
    }
    var reply = null;
    try { reply = JSON.parse(text.trim().split("\n").pop()); } catch (e) {}
    if (!reply) {
      state = signedIn ? state : "error";
      error = code === 124 ? FoamyI18n.t("Zendesk didn't answer in time.") : FoamyI18n.t("The Zendesk helper failed.");
      return;
    }
    if (reply.ok) {
      state = reply.state;
      user = reply.user || null;
      verified = reply.verified === true;
      error = reply.error ? helperText(reply.error) : "";
      return;
    }
    error = reply.error ? helperText(reply.error) : FoamyI18n.t("The Zendesk helper failed.");
    // A failed sign-in, or a sign-out that didn't finish (BUSY, LOCK_UNAVAILABLE:
    // the keyring is cleared but it can't promise nothing is stored again), leaves
    // the previous state, so Sign out stays there to try again; anything else is
    // an error state.
    if (reply.code === "ACCESS_DENIED" || reply.code === "TIMEOUT" || reply.code === "PORT_IN_USE" || reply.code === "BUSY"
        || reply.code === "LOCK_UNAVAILABLE")
      state = user ? "signed_in" : "signed_out";
    else
      state = "error";
  }

  property Process statusProcess: Process {
    property int signOuts: 0
    property int configuration: 0
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    onExited: function(code) {
      // From before configure(): the check it asked for follows.
      if (statusProcess.signOuts === account.signOuts && statusProcess.configuration === account.configurations)
        account.apply(statusOutput.text, code);
      if (account.checkAgain) { account.checkAgain = false; Qt.callLater(account.check); }
    }
  }

  property Process loginProcess: Process {
    property string lastLine: ""
    property int configuration: 0
    stdout: SplitParser {
      onRead: function(line) {
        var message = null;
        try { message = JSON.parse(line); } catch (e) {}
        // The helper is listening: hand the authorize URL to the browser
        // (not one for an address or client configure() replaced).
        if (message && message.event === "authorize" && /^https?:\/\//.test(message.url)) {
          if (loginProcess.configuration === account.configurations) Qt.openUrlExternally(message.url);
        }
        else loginProcess.lastLine = line;
      }
    }
    onExited: function(code) {
      // Stopped by configure(): whatever it brings is for the old address or
      // client, and the check configure() asked for waited for this exit.
      if (loginProcess.configuration !== account.configurations) { Qt.callLater(account.check); return; }
      if (loginProcess.lastLine === "" && code !== 0 && !FoamyNative.unavailable(code)) {
        // Cancelled (stopped by us) or killed: back to where it was.
        account.state = account.user ? "signed_in" : "signed_out";
        return;
      }
      account.apply(loginProcess.lastLine, code);
    }
  }

  property Process logoutProcess: Process {
    property int configuration: 0
    stdout: StdioCollector { id: logoutOutput; waitForEnd: true }
    onExited: function(code) {
      // As for a sign-in: the new address or client gets its own check.
      if (logoutProcess.configuration !== account.configurations) { Qt.callLater(account.check); return; }
      account.apply(logoutOutput.text, code);
    }
  }
}
