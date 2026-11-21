//! The helper as the panel runs it, with a sign-in in a locked keyring: it
//! is still stored, so no command answers `signed_out`. First with the
//! stand-in `secret-tool` (fake-secret-tool.sh), then with a real
//! gnome-keyring in a private D-Bus session of its own (real-keyring.sh;
//! skipped without dbus-run-session, gnome-keyring-daemon or secret-tool).
//! Zendesk is a closed loopback port: nothing leaves the machine. `fetch`
//! runs the same way against a loopback Zendesk: `known` on stdin and the
//! private read-state path.

use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};

use serde_json::{Value, json};

const HELPER: &str = env!("CARGO_BIN_EXE_foamy-zendesk-helper");

/// A private temporary directory, removed when dropped.
struct Dir(PathBuf);

impl Dir {
    fn new(tag: &str) -> Dir {
        let path = std::env::temp_dir().join(format!("fzk-{tag}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        for sub in ["", "home", "run", "bin", "services"] {
            fs::create_dir_all(path.join(sub)).unwrap();
        }
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
        fs::set_permissions(path.join("run"), fs::Permissions::from_mode(0o700)).unwrap();
        Dir(path)
    }
}

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// A loopback URL nothing listens on: revoking fails at once, as offline.
fn closed_zendesk() -> String {
    let port = TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port();
    format!("http://127.0.0.1:{port}")
}

/// Only what the helper needs, all of it inside `dir`.
fn environment(command: &mut Command, dir: &Path, path: &str) {
    command
        .env_clear()
        .env("PATH", path)
        .env("HOME", dir.join("home"))
        .env("XDG_RUNTIME_DIR", dir.join("run"))
        .env("XDG_STATE_HOME", dir.join("home/state"))
        .env("FOAMY_ZENDESK_BASE_URL", closed_zendesk())
        .env("LANG", "C")
        .stdin(Stdio::null())
        .stderr(Stdio::null());
}

fn last_reply(stdout: &[u8]) -> Value {
    let text = String::from_utf8_lossy(stdout);
    serde_json::from_str(text.lines().last().unwrap_or("")).unwrap_or(Value::Null)
}

/// The stand-in `secret-tool` in `dir/bin`, which also holds its state.
fn fake_secret_tool(dir: &Dir) -> PathBuf {
    let bin = dir.0.join("bin");
    let tool = bin.join("secret-tool");
    fs::write(&tool, include_str!("fake-secret-tool.sh")).unwrap();
    fs::set_permissions(&tool, fs::Permissions::from_mode(0o700)).unwrap();
    bin
}

#[test]
fn sign_out_with_a_locked_keyring_keeps_the_sign_in_and_says_so() {
    let dir = Dir::new("fake");
    let bin = fake_secret_tool(&dir);
    let run = |command: &str| {
        let mut helper = Command::new(HELPER);
        helper.args([command, "--address", "acme", "--client-id", "foamy"]);
        environment(
            &mut helper,
            &dir.0,
            &format!("{}:/usr/bin:/bin", bin.display()),
        );
        last_reply(&helper.output().unwrap().stdout)
    };
    fs::write(bin.join("item"), r#"{"access_token":"A1"}"#).unwrap();
    fs::write(bin.join("locked"), "").unwrap();

    let logout = run("auth-logout");
    assert_eq!(logout["ok"], false, "{logout}");
    assert_eq!(logout["code"], "KEYRING_LOCKED", "{logout}");
    assert!(bin.join("item").exists(), "the sign-in is still stored");
    let status = run("auth-status");
    assert_eq!(status["code"], "KEYRING_LOCKED", "{status}");

    // Unlocked, it signs out.
    fs::remove_file(bin.join("locked")).unwrap();
    assert_eq!(run("auth-logout")["state"], "signed_out");
    assert!(!bin.join("item").exists());
    assert_eq!(run("auth-status")["state"], "signed_out");
}

/// A Zendesk on loopback with one ticket (5, by Maria, assigned to Alex)
/// and its one comment, recording each request's path. One connection at a
/// time; every reply closes its connection.
fn zendesk() -> (String, Arc<Mutex<Vec<String>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let paths = Arc::new(Mutex::new(Vec::new()));
    let seen = Arc::clone(&paths);
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let mut stream = stream.unwrap();
            let mut head = Vec::new();
            let mut byte = [0u8; 1];
            while !head.ends_with(b"\r\n\r\n") && stream.read(&mut byte).unwrap_or(0) == 1 {
                head.push(byte[0]);
            }
            let head = String::from_utf8_lossy(&head).into_owned();
            let path = head.split(' ').nth(1).unwrap_or("").to_string();
            let body = if path == "/api/v2/users/me.json" {
                json!({"user": {"id": 7, "name": "Alex"}})
            } else if path.contains("groups.json") {
                json!({"groups": []})
            } else if path.starts_with("/api/v2/search.json") {
                json!({"results": [{"id": 5, "result_type": "ticket", "subject": "VPN", "status": "open",
                "assignee_id": 7, "requester_id": 9, "updated_at": "2026-11-06T09:40:00Z"}], "count": 1})
            } else if path.starts_with("/api/v2/tickets/5/comments.json") {
                json!({"comments": [{"id": 51, "author_id": 9, "public": true, "plain_body": "Hi",
                "created_at": "2026-11-06T09:40:00Z"}]})
            } else if path.starts_with("/api/v2/users/show_many.json") {
                json!({"users": [{"id": 7, "name": "Alex"}, {"id": 9, "name": "Maria"}]})
            } else {
                json!({"error": path})
            }
            .to_string();
            seen.lock().unwrap().push(path);
            let _ = write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
        }
    });
    (base, paths)
}

/// The panel sends the tickets it has comments for on stdin; the reply
/// names the read-state file in a private state directory.
#[test]
fn fetch_takes_known_on_stdin_and_names_a_private_read_file() {
    let dir = Dir::new("fetch");
    let bin = fake_secret_tool(&dir);
    // No `expires_at`: nothing is renewed.
    fs::write(bin.join("item"), r#"{"access_token":"A1"}"#).unwrap();
    let (base, paths) = zendesk();
    let fetch = |state: &Path, stdin: &str| -> Value {
        let mut helper = Command::new(HELPER);
        helper.args(["fetch", "--address", "acme", "--client-id", "foamy"]);
        environment(
            &mut helper,
            &dir.0,
            &format!("{}:/usr/bin:/bin", bin.display()),
        );
        // A relative state directory, if it were used, lands in `dir`.
        helper
            .env("FOAMY_ZENDESK_BASE_URL", &base)
            .env("XDG_STATE_HOME", state)
            .current_dir(&dir.0)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped());
        let mut child = helper.spawn().unwrap();
        // Closed after writing: the helper reads stdin to its end.
        child
            .stdin
            .take()
            .unwrap()
            .write_all(stdin.as_bytes())
            .unwrap();
        last_reply(&child.wait_with_output().unwrap().stdout)
    };
    let private = dir.0.join("home/state");

    // Known at this `updated_at`: no comments are asked for.
    let reply = fetch(&private, r#"{"known":{"5":"2026-11-06T09:40:00Z"}}"#);
    assert_eq!(reply["tickets"][0]["unchanged"], true, "{reply}");
    assert!(
        !paths
            .lock()
            .unwrap()
            .iter()
            .any(|path| path.contains("/comments.json")),
        "no comments for a known ticket"
    );

    // Not JSON: nothing is known, so the comments come.
    let reply = fetch(&private, "not json");
    assert_eq!(reply["tickets"][0]["comments"][0]["body"], "Hi", "{reply}");
    assert_eq!(
        reply["state_path"],
        private
            .join("foamy-zendesk/read-acme.zendesk.com.json")
            .to_string_lossy()
            .as_ref()
    );
    let mode = fs::metadata(private.join("foamy-zendesk"))
        .unwrap()
        .permissions()
        .mode();
    assert_eq!(
        format!("{:o}", mode & 0o777),
        "700",
        "the read state is private"
    );
    // A read-state directory that others can enter is refused, not used. This
    // holds under any umask, also one that makes every new directory 0700.
    let open = dir.0.join("open-state");
    fs::create_dir_all(open.join("foamy-zendesk")).unwrap();
    fs::set_permissions(
        open.join("foamy-zendesk"),
        fs::Permissions::from_mode(0o755),
    )
    .unwrap();
    let reply = fetch(&open, "{}");
    assert_eq!(
        (&reply["ok"], &reply["code"]),
        (&json!(false), &json!("INTERNAL")),
        "{reply}"
    );

    // A relative XDG_STATE_HOME is ignored, as the spec says.
    let reply = fetch(Path::new("relative/state"), "{}");
    assert_eq!(
        reply["state_path"],
        dir.0
            .join("home/.local/state/foamy-zendesk/read-acme.zendesk.com.json")
            .to_string_lossy()
            .as_ref(),
        "{reply}"
    );
    assert!(!dir.0.join("relative").exists());
}

fn installed(program: &str) -> bool {
    ["/usr/bin", "/bin"]
        .iter()
        .any(|dir| Path::new(dir).join(program).is_file())
}

#[test]
fn a_real_locked_gnome_keyring_is_not_a_sign_out() {
    let missing: Vec<_> = ["dbus-run-session", "gnome-keyring-daemon", "secret-tool"]
        .into_iter()
        .filter(|program| !installed(program))
        .collect();
    if !missing.is_empty() {
        eprintln!("skipped: no {}", missing.join(", "));
        return;
    }
    let dir = Dir::new("real");
    // A session bus of its own: no activatable services (an empty service
    // directory), so no unlock prompter can start, and nothing reaches the
    // desktop's bus or keyring.
    let config = dir.0.join("bus.conf");
    fs::write(
        &config,
        format!(
            r#"<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:dir={run}</listen><servicedir>{services}</servicedir>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>
"#,
            run = dir.0.join("run").display(),
            services = dir.0.join("services").display(),
        ),
    )
    .unwrap();
    let script = dir.0.join("real-keyring.sh");
    fs::write(&script, include_str!("real-keyring.sh")).unwrap();
    let mut session = Command::new("dbus-run-session");
    session
        .arg(format!("--config-file={}", config.display()))
        .args(["--", "/bin/sh"])
        .arg(&script)
        .arg(HELPER);
    environment(&mut session, &dir.0, "/usr/bin:/bin");
    // The keyrings live here.
    session
        .env("XDG_DATA_HOME", dir.0.join("home/data"))
        .env("XDG_CONFIG_HOME", dir.0.join("home/config"));
    let output = session.output().unwrap();
    let text = String::from_utf8_lossy(&output.stdout);
    let step = |name: &str| -> Value {
        let line = text
            .lines()
            .find_map(|line| line.strip_prefix(&format!("{name} ")))
            .unwrap_or_else(|| panic!("no {name} in:\n{text}"));
        serde_json::from_str(line).unwrap_or(Value::Null)
    };

    // Unlocked: read (Zendesk unreachable, so not verified).
    let status = step("status-unlocked");
    assert_eq!(status["state"], "signed_in", "{text}");
    // Locked, no prompter: still stored, and said so.
    let logout = step("logout-locked");
    assert_eq!(logout["code"], "KEYRING_LOCKED", "{text}");
    assert_eq!(step("left-after-locked-logout"), 1, "{text}");
    assert_eq!(step("status-locked")["code"], "KEYRING_LOCKED", "{text}");
    // Locked without an item: signed out.
    assert_eq!(step("status-locked-none")["state"], "signed_out", "{text}");
    assert_eq!(step("logout-locked-none")["state"], "signed_out", "{text}");
    // Unlocked again: sign-out removes it.
    assert_eq!(step("logout-unlocked")["state"], "signed_out", "{text}");
    assert_eq!(step("left-after-logout"), 0, "{text}");
    assert_eq!(step("status-after")["state"], "signed_out", "{text}");
}
