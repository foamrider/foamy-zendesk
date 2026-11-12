//! The helper as the panel runs it, with a sign-in in a locked keyring: it
//! is still stored, so no command answers `signed_out`. First with the
//! stand-in `secret-tool` (fake-secret-tool.sh), then with a real
//! gnome-keyring in a private D-Bus session of its own (real-keyring.sh;
//! skipped without dbus-run-session, gnome-keyring-daemon or secret-tool).
//! Zendesk is a closed loopback port: nothing leaves the machine.

use std::fs;
use std::net::TcpListener;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde_json::Value;

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

#[test]
fn sign_out_with_a_locked_keyring_keeps_the_sign_in_and_says_so() {
    let dir = Dir::new("fake");
    let bin = dir.0.join("bin");
    let tool = bin.join("secret-tool");
    fs::write(&tool, include_str!("fake-secret-tool.sh")).unwrap();
    fs::set_permissions(&tool, fs::Permissions::from_mode(0o700)).unwrap();
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
