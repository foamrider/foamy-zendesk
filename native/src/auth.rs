//! Sign in, check and sign out: the authorization code grant with PKCE for
//! a public OAuth client (no client secret), tokens in the keyring, and
//! refresh-token rotation that saves the new pair before using it.

use std::io::{ErrorKind, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use foamy_helper::Failure;
use std::path::PathBuf;

use foamy_helper::lock::FileLock;
use foamy_helper::net::DeadlineStream;
use serde_json::{Value, json};

use crate::http::Client;
use crate::oauth::{self, Authorize, Callback};
use crate::vault::Vault;

/// Refresh this long before the access token expires.
const REFRESH_MARGIN: u64 = 60;
const MAX_HEAD: usize = 8 * 1024;

pub struct Account<'a> {
    pub client_id: String,
    pub client: Client,
    pub vault: &'a dyn Vault,
    /// Where the login and token locks live (`$XDG_RUNTIME_DIR/foamy-zendesk`);
    /// None runs without locks.
    pub locks: Option<PathBuf>,
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn expired() -> Failure {
    Failure::coded("EXPIRED", "The Zendesk sign-in has expired. Sign in again.")
}

fn signed_out() -> Value {
    json!({"ok": true, "state": "signed_out"})
}

fn text(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
}

/// The stored record from a token reply: `{access_token, refresh_token?, expires_at?, user?}`.
fn tokens_from(reply: &Value, user: Option<&Value>) -> Result<Value, Failure> {
    let access = text(reply, "access_token")
        .ok_or_else(|| Failure::coded("HTTP", "Zendesk sent no access token."))?;
    let mut record = json!({"access_token": access});
    if let Some(refresh) = text(reply, "refresh_token") {
        record["refresh_token"] = json!(refresh);
    }
    if let Some(seconds) = reply.get("expires_in").and_then(Value::as_u64) {
        record["expires_at"] = json!(now().saturating_add(seconds));
    }
    if let Some(user) = user {
        record["user"] = user.clone();
    }
    Ok(record)
}

fn parse_record(raw: &str) -> Option<Value> {
    let record: Value = serde_json::from_str(raw.trim()).ok()?;
    text(&record, "access_token").map(|_| record)
}

/// Why Zendesk refused a token request (`error`, never a token).
fn refused(reply: &crate::http::Reply) -> Failure {
    let error = text(&reply.body, "error").unwrap_or_else(|| format!("HTTP {}", reply.status));
    if error == "invalid_grant" {
        expired()
    } else {
        Failure::coded(
            "HTTP",
            crate::text::message("Zendesk refused the sign-in (%1).", &[&error]),
        )
    }
}

impl Account<'_> {
    fn me(&self, access: &str) -> Result<Value, Failure> {
        let reply = self
            .client
            .request("GET", "/api/v2/users/me.json", Some(access), None)?;
        match reply.status {
            200 => {
                let user = &reply.body["user"];
                Ok(json!({
                    "name": text(user, "name").unwrap_or_default(),
                    "email": text(user, "email").unwrap_or_default(),
                }))
            }
            401 => Err(Failure::coded("UNAUTHORIZED", "Zendesk refused the token.")),
            status => Err(Failure::coded(
                "HTTP",
                crate::text::message("Zendesk answered HTTP %1.", &[&status]),
            )),
        }
    }

    /// Exchanges the refresh token for a new pair and stores it before
    /// returning it: Zendesk invalidates the old pair, so losing the new one
    /// would sign the user out. One refresh at a time across processes.
    fn refresh(&self, old: &Value) -> Result<Value, Failure> {
        let refresh = text(old, "refresh_token").ok_or_else(expired)?;
        let _lock = self.token_lock()?;
        // Another helper may have refreshed while this one waited.
        if let Some(current) = self.vault.get()?.as_deref().and_then(parse_record)
            && current["access_token"] != old["access_token"]
        {
            return Ok(current);
        }
        let reply = self.client.request(
            "POST",
            "/oauth/tokens",
            None,
            Some(&json!({
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": self.client_id,
                "scope": oauth::SCOPE,
            })),
        )?;
        if reply.status != 200 {
            return Err(refused(&reply));
        }
        let record = tokens_from(&reply.body, old.get("user"))?;
        self.vault.put(&record.to_string())?;
        Ok(record)
    }

    /// A usable access token, refreshed (and the new pair stored) when it is
    /// about to expire. `SIGNED_OUT` or `EXPIRED` when there is none.
    pub fn access_token(&self) -> Result<String, Failure> {
        let Some(mut record) = self.vault.get()?.as_deref().and_then(parse_record) else {
            return Err(Failure::coded(
                "SIGNED_OUT",
                "Sign in to Zendesk in the settings.",
            ));
        };
        if record["expires_at"]
            .as_u64()
            .is_some_and(|at| now() + REFRESH_MARGIN >= at)
        {
            record = self.refresh(&record)?;
        }
        Ok(text(&record, "access_token").unwrap_or_default())
    }

    /// `signed_out`, `expired`, or `signed_in` with the user (`verified`
    /// false and an `error` when Zendesk can't be reached right now).
    pub fn status(&self) -> Result<Value, Failure> {
        let Some(mut record) = self.vault.get()?.as_deref().and_then(parse_record) else {
            return Ok(signed_out());
        };
        let offline = |record: &Value, failure: Failure| {
            json!({"ok": true, "state": "signed_in", "user": record.get("user").cloned().unwrap_or(Value::Null),
                   "verified": false, "error": failure.message})
        };
        let mut refreshed = false;
        if record["expires_at"]
            .as_u64()
            .is_some_and(|at| now() + REFRESH_MARGIN >= at)
        {
            match self.refresh(&record) {
                Ok(next) => (record, refreshed) = (next, true),
                Err(failure) if failure.code == "EXPIRED" => {
                    return Ok(json!({"ok": true, "state": "expired"}));
                }
                Err(failure) if failure.code == "KEYRING_UNAVAILABLE" => return Err(failure),
                Err(failure) => return Ok(offline(&record, failure)),
            }
        }
        loop {
            let access = text(&record, "access_token").unwrap_or_default();
            match self.me(&access) {
                Ok(user) => {
                    if record.get("user") != Some(&user) {
                        record["user"] = user.clone();
                        self.vault.put(&record.to_string())?;
                    }
                    return Ok(
                        json!({"ok": true, "state": "signed_in", "user": user, "verified": true}),
                    );
                }
                Err(failure)
                    if failure.code == "UNAUTHORIZED"
                        && !refreshed
                        && record.get("refresh_token").is_some() =>
                {
                    match self.refresh(&record) {
                        Ok(next) => (record, refreshed) = (next, true),
                        Err(failure) if failure.code == "EXPIRED" => {
                            return Ok(json!({"ok": true, "state": "expired"}));
                        }
                        Err(failure) => return Ok(offline(&record, failure)),
                    }
                }
                Err(failure) if failure.code == "UNAUTHORIZED" => {
                    return Ok(json!({"ok": true, "state": "expired"}));
                }
                Err(failure) => return Ok(offline(&record, failure)),
            }
        }
    }

    /// Revokes the token at Zendesk (best effort) and removes it from the keyring.
    pub fn logout(&self) -> Result<Value, Failure> {
        if let Some(record) = self.vault.get()?.as_deref().and_then(parse_record) {
            let access = text(&record, "access_token").unwrap_or_default();
            let _ = self.client.request(
                "DELETE",
                "/api/v2/oauth/tokens/current.json",
                Some(&access),
                None,
            );
        }
        self.vault.delete()?;
        Ok(signed_out())
    }

    /// The browser flow. `authorize` receives the URL to open; the helper
    /// then waits (until `wait` passes) for the redirect to the loopback port.
    pub fn login(
        &self,
        port: u16,
        wait: Duration,
        authorize: impl FnOnce(&str),
    ) -> Result<Value, Failure> {
        let lock = self
            .locks
            .as_ref()
            .map(|dir| FileLock::try_exclusive(&dir.join("login.lock")));
        // Held by another helper: one browser sign-in at a time. No lock
        // directory, or it can't be used: go on without one.
        let _lock = match lock {
            Some(Ok(None)) => {
                return Err(Failure::coded(
                    "BUSY",
                    "A Zendesk sign-in is already waiting in the browser.",
                ));
            }
            Some(Ok(Some(lock))) => Some(lock),
            Some(Err(_)) | None => None,
        };
        let listener = TcpListener::bind(("127.0.0.1", port)).map_err(|error| {
            if error.kind() == ErrorKind::AddrInUse {
                Failure::coded(
                    "PORT_IN_USE",
                    crate::text::message("Port %1 is in use. Choose another redirect port (and update the OAuth client).", &[&port]),
                )
            } else {
                Failure::coded("PORT_IN_USE", crate::text::message("Can't listen on port %1 (%2).", &[&port, &error]))
            }
        })?;
        let verifier = oauth::base64url(&random(32)?);
        let state = oauth::base64url(&random(16)?);
        let redirect = oauth::redirect_uri(port);
        authorize(
            &Authorize {
                base: &self.client.base,
                client_id: &self.client_id,
                redirect_uri: &redirect,
                challenge: &oauth::challenge(&verifier),
                state: &state,
            }
            .url(),
        );
        let code = wait_for_code(&listener, &state, Instant::now() + wait)?;
        drop(listener);
        // Codes live for 120 seconds: exchange at once.
        let reply = self.client.request(
            "POST",
            "/oauth/tokens",
            None,
            Some(&json!({
                "grant_type": "authorization_code",
                "code": code,
                "client_id": self.client_id,
                "redirect_uri": redirect,
                "scope": oauth::SCOPE,
                "code_verifier": verifier,
            })),
        )?;
        if reply.status != 200 {
            return Err(refused(&reply));
        }
        let mut record = tokens_from(&reply.body, None)?;
        let user = self.me(&text(&record, "access_token").unwrap_or_default())?;
        record["user"] = user.clone();
        self.vault.put(&record.to_string())?;
        Ok(json!({"ok": true, "state": "signed_in", "user": user, "verified": true}))
    }
}

impl Account<'_> {
    fn token_lock(&self) -> Result<Option<FileLock>, Failure> {
        let Some(dir) = &self.locks else {
            return Ok(None);
        };
        match FileLock::exclusive_within(&dir.join("token.lock"), Duration::from_secs(15)) {
            Ok(Some(lock)) => Ok(Some(lock)),
            Ok(None) => Err(Failure::coded(
                "BUSY",
                "Another Zendesk request is renewing the sign-in.",
            )),
            Err(_) => Ok(None),
        }
    }
}

fn random(bytes: usize) -> Result<Vec<u8>, Failure> {
    let mut data = vec![0u8; bytes];
    std::fs::File::open("/dev/urandom")
        .and_then(|mut file| file.read_exact(&mut data))
        .map_err(|error| {
            Failure::coded(
                "INTERNAL",
                crate::text::message("No randomness available (%1).", &[&error]),
            )
        })?;
    Ok(data)
}

fn page(status: &str, title: &str, body: &str) -> Vec<u8> {
    let html = format!(
        "<!doctype html><meta charset=utf-8><title>{title}</title>\
         <body style=\"font:16px system-ui;margin:4em auto;max-width:28em;text-align:center\">\
         <h1 style=\"font-size:1.4em\">{title}</h1><p>{body}</p>"
    );
    format!(
        "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\n\
         Cache-Control: no-store\r\nConnection: close\r\n\r\n{html}",
        html.len()
    )
    .into_bytes()
}

/// Reads one request head (bounded in size and time) and answers it.
fn handle(stream: TcpStream, state: &str) -> Option<Result<String, Failure>> {
    let mut stream = DeadlineStream::new(stream, Instant::now() + Duration::from_secs(5));
    let mut head = Vec::new();
    let mut buffer = [0u8; 1024];
    while !head.windows(4).any(|w| w == b"\r\n\r\n") && head.len() < MAX_HEAD {
        match stream.read(&mut buffer) {
            Ok(0) | Err(_) => break,
            Ok(n) => head.extend_from_slice(&buffer[..n]),
        }
    }
    let (reply, outcome) = match oauth::parse_callback(&String::from_utf8_lossy(&head)) {
        Callback::Code { code, state: got } if got == state => (
            page(
                "200 OK",
                "Signed in to Zendesk",
                "You can close this tab and go back to your desktop.",
            ),
            Some(Ok(code)),
        ),
        Callback::Denied { error, state: got } if got == state => (
            page(
                "200 OK",
                "Sign-in cancelled",
                "Zendesk didn't grant access. You can close this tab.",
            ),
            Some(Err(if error == "access_denied" {
                Failure::coded("ACCESS_DENIED", "Sign-in was cancelled in the browser.")
            } else {
                Failure::coded(
                    "HTTP",
                    "Zendesk refused the sign-in. Check the OAuth client's settings.",
                )
            })),
        ),
        // A stale tab from an earlier attempt: refuse it, keep waiting.
        Callback::Code { .. } | Callback::Denied { .. } => (
            page(
                "400 Bad Request",
                "Sign-in link expired",
                "Start again from the Zendesk settings.",
            ),
            None,
        ),
        Callback::Other => (page("404 Not Found", "Not found", ""), None),
    };
    let _ = stream.write_all(&reply);
    let _ = stream.flush();
    outcome
}

fn wait_for_code(
    listener: &TcpListener,
    state: &str,
    deadline: Instant,
) -> Result<String, Failure> {
    listener
        .set_nonblocking(true)
        .map_err(|error| Failure::coded("INTERNAL", error.to_string()))?;
    loop {
        match listener.accept() {
            Ok((stream, _)) => {
                let _ = stream.set_nonblocking(false);
                if let Some(outcome) = handle(stream, state) {
                    return outcome;
                }
            }
            Err(error) if error.kind() == ErrorKind::WouldBlock => {}
            Err(error) => return Err(Failure::coded("INTERNAL", error.to_string())),
        }
        if Instant::now() >= deadline {
            return Err(Failure::coded(
                "TIMEOUT",
                "Sign-in wasn't finished in the browser in time.",
            ));
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::Memory;
    use std::io::BufRead;
    use std::sync::{Arc, Mutex};

    type Route = Box<dyn Fn(&str, &str, &Value) -> (u16, Value) + Send>;
    /// (method, path, authorization, body) per request.
    type Log = Arc<Mutex<Vec<(String, String, String, Value)>>>;

    /// A fake Zendesk on loopback: answers every request with `route`,
    /// recording (method, path, authorization, body).
    fn fake(route: Route) -> (String, Log) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen = Arc::new(Mutex::new(Vec::new()));
        let log = Arc::clone(&seen);
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let mut stream = std::io::BufReader::new(stream.unwrap());
                let mut line = String::new();
                stream.read_line(&mut line).unwrap();
                let mut parts = line.split_whitespace();
                let (method, path) = (
                    parts.next().unwrap_or("").to_string(),
                    parts.next().unwrap_or("").to_string(),
                );
                let (mut length, mut auth) = (0usize, String::new());
                loop {
                    let mut header = String::new();
                    stream.read_line(&mut header).unwrap();
                    let header = header.trim_end();
                    if header.is_empty() {
                        break;
                    }
                    let (name, value) = header.split_once(": ").unwrap_or((header, ""));
                    match name.to_ascii_lowercase().as_str() {
                        "content-length" => length = value.parse().unwrap(),
                        "authorization" => auth = value.into(),
                        _ => {}
                    }
                }
                let mut body = vec![0; length];
                stream.read_exact(&mut body).unwrap();
                let body: Value = serde_json::from_slice(&body).unwrap_or(Value::Null);
                let (status, reply) = route(&method, &path, &body);
                log.lock().unwrap().push((method, path, auth, body));
                let reply = reply.to_string();
                let mut stream = stream.into_inner();
                write!(stream, "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{reply}", reply.len()).unwrap();
            }
        });
        (base, seen)
    }

    fn account<'a>(base: &str, vault: &'a Memory) -> Account<'a> {
        Account {
            client_id: "foamy".into(),
            client: Client::new(base.into(), Duration::from_secs(5)),
            vault,
            locks: None,
        }
    }

    fn free_port() -> u16 {
        TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port()
    }

    fn query(url: &str, key: &str) -> String {
        url.split(['?', '&'])
            .find_map(|pair| pair.strip_prefix(&format!("{key}=")))
            .unwrap()
            .to_string()
    }

    fn browser(port: u16, path: String) -> String {
        let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(stream, "GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n").unwrap();
        let mut page = String::new();
        stream.read_to_string(&mut page).unwrap();
        page
    }

    #[test]
    fn login_runs_pkce_and_stores_the_tokens() {
        let (base, seen) = fake(Box::new(|method, path, _| match (method, path) {
            ("POST", "/oauth/tokens") => (
                200,
                json!({"access_token": "A1", "refresh_token": "R1", "expires_in": 1800, "token_type": "bearer"}),
            ),
            ("GET", "/api/v2/users/me.json") => (
                200,
                json!({"user": {"name": "Alex", "email": "alex@acme.com"}}),
            ),
            _ => (404, json!({})),
        }));
        let vault = Memory::default();
        let port = free_port();
        let result = account(&base, &vault)
            .login(port, Duration::from_secs(10), |url| {
                assert!(url.starts_with(&format!("{base}/oauth/authorizations/new?")));
                assert_eq!(query(url, "code_challenge_method"), "S256");
                let state = query(url, "state");
                std::thread::spawn(move || {
                    // A stray request and a stale tab first: both refused, the wait goes on.
                    assert!(browser(port, "/favicon.ico".into()).starts_with("HTTP/1.1 404"));
                    assert!(
                        browser(port, "/callback?code=old&state=stale".into())
                            .starts_with("HTTP/1.1 400")
                    );
                    assert!(
                        browser(port, format!("/callback?code=C1&state={state}"))
                            .contains("Signed in to Zendesk")
                    );
                });
            })
            .unwrap();
        assert_eq!(result["state"], "signed_in");
        assert_eq!(result["user"]["name"], "Alex");
        let seen = seen.lock().unwrap();
        let exchange = &seen[0].3;
        assert_eq!(exchange["grant_type"], "authorization_code");
        assert_eq!(exchange["code"], "C1");
        assert_eq!(
            exchange["redirect_uri"],
            format!("http://127.0.0.1:{port}/callback")
        );
        assert!(exchange.get("client_secret").is_none());
        let verifier = exchange["code_verifier"].as_str().unwrap();
        assert_eq!(verifier.len(), 43);
        assert_eq!(seen[1].2, "Bearer A1");
        let stored: Value = serde_json::from_str(&vault.get().unwrap().unwrap()).unwrap();
        assert_eq!(
            (
                stored["access_token"].as_str(),
                stored["refresh_token"].as_str()
            ),
            (Some("A1"), Some("R1"))
        );
        assert!(stored["expires_at"].as_u64().unwrap() > now());
    }

    #[test]
    fn a_denied_login_reports_it() {
        let (base, _) = fake(Box::new(|_, _, _| (500, json!({}))));
        let vault = Memory::default();
        let port = free_port();
        let failure = account(&base, &vault)
            .login(port, Duration::from_secs(10), |url| {
                let state = query(url, "state");
                std::thread::spawn(move || {
                    browser(port, format!("/callback?error=access_denied&state={state}"))
                });
            })
            .unwrap_err();
        assert_eq!(failure.code, "ACCESS_DENIED");
        assert!(vault.get().unwrap().is_none());
    }

    #[test]
    fn a_login_nobody_finishes_times_out() {
        let (base, _) = fake(Box::new(|_, _, _| (500, json!({}))));
        let vault = Memory::default();
        let failure = account(&base, &vault)
            .login(free_port(), Duration::from_millis(200), |_| {})
            .unwrap_err();
        assert_eq!(failure.code, "TIMEOUT");
    }

    #[test]
    fn a_second_login_is_busy_while_one_waits() {
        let dir = std::env::temp_dir().join(format!("foamy-zendesk-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let held = FileLock::try_exclusive(&dir.join("login.lock")).unwrap();
        assert!(held.is_some());
        let vault = Memory::default();
        let mut second = account("http://127.0.0.1:1", &vault);
        second.locks = Some(dir.clone());
        let failure = second
            .login(free_port(), Duration::from_secs(1), |_| {})
            .unwrap_err();
        assert_eq!(failure.code, "BUSY");
        drop(held);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_busy_port_is_reported() {
        let (base, _) = fake(Box::new(|_, _, _| (500, json!({}))));
        let taken = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = taken.local_addr().unwrap().port();
        let vault = Memory::default();
        let failure = account(&base, &vault)
            .login(port, Duration::from_secs(1), |_| {})
            .unwrap_err();
        assert_eq!(failure.code, "PORT_IN_USE");
    }

    #[test]
    fn status_refreshes_an_expiring_token_and_stores_the_new_pair_first() {
        let (base, seen) = fake(Box::new(|method, path, body| match (method, path) {
            ("POST", "/oauth/tokens") if body["refresh_token"] == "R1" => (
                200,
                json!({"access_token": "A2", "refresh_token": "R2", "expires_in": 1800}),
            ),
            ("GET", "/api/v2/users/me.json") => (
                200,
                json!({"user": {"name": "Alex", "email": "alex@acme.com"}}),
            ),
            _ => (400, json!({"error": "invalid_grant"})),
        }));
        let vault = Memory::default();
        vault
            .put(
                &json!({"access_token": "A1", "refresh_token": "R1", "expires_at": now() + 10})
                    .to_string(),
            )
            .unwrap();
        let status = account(&base, &vault).status().unwrap();
        assert_eq!(
            (status["state"].as_str(), status["verified"].as_bool()),
            (Some("signed_in"), Some(true))
        );
        let stored: Value = serde_json::from_str(&vault.get().unwrap().unwrap()).unwrap();
        assert_eq!(
            (
                stored["access_token"].as_str(),
                stored["refresh_token"].as_str()
            ),
            (Some("A2"), Some("R2"))
        );
        assert_eq!(stored["user"]["email"], "alex@acme.com");
        let seen = seen.lock().unwrap();
        assert_eq!(seen[0].3["grant_type"], "refresh_token");
        assert_eq!(seen[1].2, "Bearer A2");
    }

    #[test]
    fn a_revoked_refresh_token_means_sign_in_again() {
        let (base, _) = fake(Box::new(|method, path, _| match (method, path) {
            ("GET", "/api/v2/users/me.json") => (401, json!({"error": "invalid_token"})),
            _ => (400, json!({"error": "invalid_grant"})),
        }));
        let vault = Memory::default();
        vault
            .put(
                &json!({"access_token": "A1", "refresh_token": "R1", "expires_at": now() + 3600})
                    .to_string(),
            )
            .unwrap();
        assert_eq!(account(&base, &vault).status().unwrap()["state"], "expired");
    }

    #[test]
    fn offline_status_keeps_the_stored_user() {
        let vault = Memory::default();
        vault
            .put(
                &json!({"access_token": "A1", "user": {"name": "Alex", "email": "alex@acme.com"}})
                    .to_string(),
            )
            .unwrap();
        let status = account(&format!("http://127.0.0.1:{}", free_port()), &vault)
            .status()
            .unwrap();
        assert_eq!(
            (status["state"].as_str(), status["verified"].as_bool()),
            (Some("signed_in"), Some(false))
        );
        assert_eq!(status["user"]["name"], "Alex");
        assert_eq!(
            account("http://127.0.0.1:1", &Memory::default())
                .status()
                .unwrap()["state"],
            "signed_out"
        );
    }

    #[test]
    fn fetch_lists_mine_and_unassigned_in_my_groups() {
        let (base, seen) = fake(Box::new(|method, path, _| {
            assert_eq!(method, "GET");
            let path = path.to_string();
            if path == "/api/v2/users/me.json" {
                (200, json!({"user": {"id": 7, "name": "Alex"}}))
            } else if path == "/api/v2/users/7/groups.json" {
                (200, json!({"groups": [{"id": 30, "name": "IT support"}]}))
            } else if path.starts_with("/api/v2/groups.json") {
                (
                    200,
                    json!({"groups": [{"id": 30, "name": "IT support"}, {"id": 31, "name": "Billing"}]}),
                )
            } else if path.contains("assignee%3Ame") {
                (
                    200,
                    json!({"results": [{"id": 1, "result_type": "ticket", "subject": "VPN", "status": "open", "priority": "high",
                    "assignee_id": 7, "group_id": 31, "requester_id": 9, "updated_at": "2026-11-06T09:40:00Z"}]}),
                )
            } else if path.contains("assignee%3Anone%20group%3A30") {
                (
                    200,
                    json!({"results": [{"id": 2, "result_type": "ticket", "subject": "Display", "status": "hold", "priority": null,
                    "assignee_id": null, "group_id": 30, "requester_id": 9, "updated_at": "2026-11-06T09:28:00Z"}]}),
                )
            } else if path.starts_with("/api/v2/tickets/2/comments.json") {
                (
                    200,
                    json!({"comments": [
                    {"id": 502, "author_id": 7, "public": false, "plain_body": "Checking", "created_at": "2026-11-06T09:28:00Z"},
                    {"id": 501, "author_id": 9, "public": true, "plain_body": "Screen is black", "created_at": "2026-11-06T09:20:00Z"}]}),
                )
            } else if path.starts_with("/api/v2/users/show_many.json?ids=7,9") {
                (
                    200,
                    json!({"users": [{"id": 7, "name": "Alex"}, {"id": 9, "name": "Maria"}]}),
                )
            } else {
                (404, json!({"error": path}))
            }
        }));
        let vault = Memory::default();
        vault
            .put(&json!({"access_token": "A1"}).to_string())
            .unwrap();
        let mut known = serde_json::Map::new();
        known.insert("1".into(), json!("2026-11-06T09:40:00Z"));
        let reply = crate::tickets::fetch(&account(&base, &vault), &known).unwrap();
        let tickets = reply["tickets"].as_array().unwrap();
        assert_eq!(tickets.len(), 2);
        assert_eq!(tickets[0]["id"], "1");
        assert_eq!(tickets[0]["unchanged"], true);
        assert_eq!(
            (
                tickets[0]["status"].as_str(),
                tickets[0]["priority"].as_str()
            ),
            (Some("Open"), Some("High"))
        );
        assert_eq!(
            (tickets[0]["group"].as_str(), tickets[0]["mine"].as_bool()),
            (Some("Billing"), Some(true))
        );
        let display = &tickets[1];
        assert_eq!(
            (
                display["status"].as_str(),
                display["assignee"].as_str(),
                display["requester"].as_str()
            ),
            (Some("On-hold"), Some("Unassigned"), Some("Maria"))
        );
        let comments = display["comments"].as_array().unwrap();
        assert_eq!(
            comments[0],
            json!({"id": 502, "author": "Alex", "mine": true, "public": false, "created": 1_793_957_280_000_i64, "body": "Checking"})
        );
        assert_eq!(comments[1]["author"], "Maria");
        let seen = seen.lock().unwrap();
        assert!(seen.iter().all(|request| request.2 == "Bearer A1"));
        assert!(
            !seen
                .iter()
                .any(|request| request.1.starts_with("/api/v2/tickets/1/")),
            "no comments for an unchanged ticket"
        );
    }

    #[test]
    fn fetch_without_a_sign_in_says_so() {
        let vault = Memory::default();
        let failure = crate::tickets::fetch(
            &account("http://127.0.0.1:1", &vault),
            &serde_json::Map::new(),
        )
        .unwrap_err();
        assert_eq!(failure.code, "SIGNED_OUT");
    }

    #[test]
    fn logout_revokes_and_forgets() {
        let (base, seen) = fake(Box::new(|_, _, _| (204, Value::Null)));
        let vault = Memory::default();
        vault
            .put(&json!({"access_token": "A1"}).to_string())
            .unwrap();
        assert_eq!(
            account(&base, &vault).logout().unwrap()["state"],
            "signed_out"
        );
        assert!(vault.get().unwrap().is_none());
        let seen = seen.lock().unwrap();
        assert_eq!(
            (seen[0].0.as_str(), seen[0].1.as_str(), seen[0].2.as_str()),
            ("DELETE", "/api/v2/oauth/tokens/current.json", "Bearer A1")
        );
    }
}
