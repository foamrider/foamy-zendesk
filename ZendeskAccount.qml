pragma Singleton
import QtQuick
import Quickshell
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

  function configure(next) {
    if (next.address === address && next.clientId === clientId && next.port === port) return;
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
    process.command = ["timeout", "--kill-after=2s", limit].concat(FoamyNative.command(pluginDir, helper, args(command, extra)));
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
    // A failed sign-in leaves the previous state; anything else is an error state.
    if (reply.code === "ACCESS_DENIED" || reply.code === "TIMEOUT" || reply.code === "PORT_IN_USE" || reply.code === "BUSY")
      state = user ? "signed_in" : "signed_out";
    else
      state = "error";
  }

  property Process statusProcess: Process {
    property int signOuts: 0
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    onExited: function(code) {
      if (statusProcess.signOuts === account.signOuts) account.apply(statusOutput.text, code);
      if (account.checkAgain) { account.checkAgain = false; Qt.callLater(account.check); }
    }
  }

  property Process loginProcess: Process {
    property string lastLine: ""
    stdout: SplitParser {
      onRead: function(line) {
        var message = null;
        try { message = JSON.parse(line); } catch (e) {}
        // The helper is listening: hand the authorize URL to the browser.
        if (message && message.event === "authorize" && /^https?:\/\//.test(message.url)) Qt.openUrlExternally(message.url);
        else loginProcess.lastLine = line;
      }
    }
    onExited: function(code) {
      if (loginProcess.lastLine === "" && code !== 0 && !FoamyNative.unavailable(code)) {
        // Cancelled (stopped by us) or killed: back to where it was.
        account.state = account.user ? "signed_in" : "signed_out";
        return;
      }
      account.apply(loginProcess.lastLine, code);
    }
  }

  property Process logoutProcess: Process {
    stdout: StdioCollector { id: logoutOutput; waitForEnd: true }
    onExited: function(code) { account.apply(logoutOutput.text, code); }
  }
}
