//! foamy-zendesk-helper: Zendesk sign-in for the foamy-zendesk plugin.
//!
//! OAuth only: the authorization code grant with PKCE for a **public** OAuth
//! client (no client secret), created once by a Zendesk admin with the
//! redirect URL `http://127.0.0.1:<port>/callback`. Tokens live in the
//! Secret Service keyring (through `secret-tool`); nothing secret is printed,
//! logged or written to a file. The account address and client are always
//! given by the caller; nothing is hard-coded.
//!
//! ```text
//! foamy-zendesk-helper auth-status --address <acme|acme.zendesk.com> --client-id <id>
//! foamy-zendesk-helper auth-login  --address <…> --client-id <id> --port <1024-65535>
//! foamy-zendesk-helper auth-logout --address <…> --client-id <id>
//! foamy-zendesk-helper fetch       --address <…> --client-id <id>   < {"known":{"<id>":"<updated_at>"}}
//! ```
//!
//! `fetch` replies `{"ok":true,"me":{…},"tickets":[…],"state_path":…}`: unsolved
//! tickets assigned to the agent and unassigned ones in the agent's groups,
//! each with its latest comments (newest first) unless `known` already has
//! that `updated_at` (`"unchanged":true`) or the run's comment budget is spent
//! (`"deferred":true`). `state_path` is the plugin's read-state file in a
//! private `$XDG_STATE_HOME/foamy-zendesk/` (created here; the panel writes it).
//!
//! Every command prints one JSON reply as its last line:
//!
//! - `{"ok":true,"state":"signed_in","user":{"name":…,"email":…},"verified":true}`
//!   (`verified` false plus `error` when Zendesk can't be reached right now),
//! - `{"ok":true,"state":"signed_out"}`, `{"ok":true,"state":"expired"}`,
//! - `{"ok":false,"code":…,"error":…}` with code `INVALID_ARGUMENT`,
//!   `KEYRING_UNAVAILABLE`, `PORT_IN_USE`, `BUSY`, `TIMEOUT`, `ACCESS_DENIED`,
//!   `EXPIRED`, `NETWORK`, `HTTP`, `TLS_UNSUPPORTED` or `INTERNAL`.
//!
//! Every `error` is a catalog key of the plugin's `i18n/en.json`; varying
//! details follow it after U+001F separators and fill its `%1`, `%2`… (see
//! `text.rs`).
//!
//! `auth-login` first prints `{"event":"authorize","url":…}`: the caller opens
//! that URL in the browser. The helper then waits up to five minutes for the
//! redirect, exchanges the code and stores the tokens. Access tokens are
//! refreshed (and the rotated pair stored before use) when they expire.
//! `FOAMY_ZENDESK_BASE_URL` (a loopback `http://` URL only) replaces
//! `https://<address>` in tests.

mod auth;
mod http;
mod oauth;
mod text;
mod tickets;
mod vault;

use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use foamy_helper::{Failure, json};
use serde_json::{Value, json as value};

const LOGIN_WAIT: Duration = Duration::from_secs(300);

fn usage() -> Failure {
    Failure::coded(
        "INVALID_ARGUMENT",
        "usage: foamy-zendesk-helper auth-status|auth-login|auth-logout|fetch --address <address> --client-id <id> [--port <port>]",
    )
}

fn option<'a>(args: &'a [String], name: &str) -> Option<&'a str> {
    args.windows(2)
        .find(|pair| pair[0] == name)
        .map(|pair| pair[1].as_str())
}

/// `$XDG_STATE_HOME/foamy-zendesk` (else `~/.local/state/foamy-zendesk`), private.
fn state_dir() -> Result<PathBuf, Failure> {
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state")))
        .ok_or_else(|| Failure::coded("INTERNAL", "No home directory for the read state."))?;
    let dir = base.join("foamy-zendesk");
    foamy_helper::fs::ensure_private_dir(&dir).map_err(|error| {
        Failure::coded(
            "INTERNAL",
            text::message("Can't use %1 (%2).", &[&dir.display(), &error]),
        )
    })?;
    Ok(dir)
}

fn known_from_stdin() -> serde_json::Map<String, Value> {
    let input = foamy_helper::io::read_stdin_limited(1 << 20).unwrap_or_default();
    serde_json::from_slice::<Value>(&input)
        .ok()
        .and_then(|request| request.get("known").and_then(Value::as_object).cloned())
        .unwrap_or_default()
}

fn run(args: Vec<String>) -> Result<Value, Failure> {
    let command = args.first().ok_or_else(usage)?.as_str();
    let rest = &args[1..];
    let host = oauth::normalize_address(option(rest, "--address").ok_or_else(usage)?)?;
    let client_id = oauth::validate_client_id(option(rest, "--client-id").ok_or_else(usage)?)?;
    let keyring = vault::SecretTool::new(&host, &client_id);
    let account = auth::Account {
        client: http::Client::new(http::base_for(&host)?, http::TIMEOUT),
        client_id,
        vault: &keyring,
        locks: foamy_helper::lock::runtime_dir("foamy-zendesk").ok(),
    };
    match command {
        "auth-status" => account.status(),
        "auth-logout" => account.logout(),
        "fetch" => {
            let mut reply = tickets::fetch(&account, &known_from_stdin())?;
            let file = state_dir()?.join(format!("read-{host}.json"));
            reply["state_path"] = value!(file.to_string_lossy());
            Ok(reply)
        }
        "auth-login" => {
            let port = oauth::validate_port(option(rest, "--port").ok_or_else(usage)?)?;
            account.login(port, LOGIN_WAIT, |url| {
                let _ = json::print_line(&value!({"event": "authorize", "url": url}));
            })
        }
        _ => Err(usage()),
    }
}

fn main() -> ExitCode {
    // A shell restart while the browser is open must not leave the listener behind.
    let _ = foamy_helper::process::die_with_parent();
    json::run(
        || run(std::env::args().skip(1).collect()),
        json::error_reply,
    )
}
