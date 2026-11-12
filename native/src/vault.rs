//! Where the tokens live: the Secret Service keyring through `secret-tool`
//! (libsecret), one item per account and OAuth client. Nothing else on disk.
//!
//! `secret-tool lookup` and `clear` exit 1 without a word both when no item
//! matches and when the item is in a locked keyring: `lookup` asks to unlock
//! it and gives up when the prompt is dismissed or can't be shown, and
//! `clear` only removes unlocked items, never asking. So after either one,
//! `search` (without `--unlock`, which never prompts) says whether an item
//! is still there: one that is, locked, is `KEYRING_LOCKED`, never "signed
//! out" or "removed".

use std::ffi::OsString;
use std::io::ErrorKind;
#[cfg(test)]
use std::sync::Mutex;
#[cfg(test)]
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use foamy_helper::Failure;
use foamy_helper::child::Bounded;

const SERVICE: &str = "foamy-zendesk";
/// secret-tool may wait for a keyring unlock prompt.
const TIMEOUT: Duration = Duration::from_secs(60);
const MAX_SECRET: usize = 64 * 1024;

pub fn unavailable(detail: &str) -> Failure {
    let detail = detail.lines().next().unwrap_or("").trim();
    Failure::coded(
        "KEYRING_UNAVAILABLE",
        if detail.is_empty() {
            "No keyring is available to store the Zendesk sign-in.".to_string()
        } else {
            crate::text::message(
                "No keyring is available to store the Zendesk sign-in (%1).",
                &[&detail],
            )
        },
    )
}

/// The item is there but can't be read or removed: its keyring is locked.
pub fn locked() -> Failure {
    Failure::coded(
        "KEYRING_LOCKED",
        "The keyring that holds the Zendesk sign-in is locked. Unlock it and try again.",
    )
}

/// `get` is `None` only when no item matches; `delete` is `Ok` only when
/// none is left. A locked item is `KEYRING_LOCKED` for both.
pub trait Vault {
    fn get(&self) -> Result<Option<String>, Failure>;
    fn put(&self, secret: &str) -> Result<(), Failure>;
    fn delete(&self) -> Result<(), Failure>;
}

/// `secret-tool {lookup|store|clear|search} service foamy-zendesk host <host> client <id>`.
pub struct SecretTool {
    program: OsString,
    host: String,
    client_id: String,
}

impl SecretTool {
    pub fn new(host: &str, client_id: &str) -> SecretTool {
        SecretTool {
            program: "secret-tool".into(),
            host: host.into(),
            client_id: client_id.into(),
        }
    }

    fn command(&self, verb: &str) -> Bounded {
        let mut command = Bounded::new(&self.program).arg(verb);
        if verb == "store" {
            command = command.arg(format!("--label=Foamy Zendesk ({})", self.host));
        }
        command
            .args([
                "service",
                SERVICE,
                "host",
                self.host.as_str(),
                "client",
                self.client_id.as_str(),
            ])
            .keep_env(&[
                "PATH",
                "HOME",
                "XDG_RUNTIME_DIR",
                "DBUS_SESSION_BUS_ADDRESS",
                "DISPLAY",
                "WAYLAND_DISPLAY",
            ])
            .timeout(TIMEOUT)
            .max_output(MAX_SECRET)
    }

    fn run(command: Bounded) -> Result<foamy_helper::child::Output, Failure> {
        match command.run() {
            Ok(output) if output.timed_out => Err(unavailable("the keyring didn't answer")),
            Ok(output) => Ok(output),
            Err(error) if error.kind() == ErrorKind::NotFound => {
                Err(unavailable("secret-tool isn't installed"))
            }
            Err(error) => Err(unavailable(&error.to_string())),
        }
    }

    /// Whether the keyring still holds a matching item, locked or not.
    /// `search` lists each one (`[/<id>]`, its label and dates, and the
    /// secret of an unlocked one) on stdout, and complains on stderr about
    /// a locked one's secret but still exits 0; no item: no output.
    fn exists(&self) -> Result<bool, Failure> {
        let output = SecretTool::run(self.command("search"))?;
        if !output.success() {
            return Err(failed(&output));
        }
        Ok(!output.stdout.iter().all(u8::is_ascii_whitespace))
    }
}

/// Exited 1 on its own and said nothing: "no such item", or a locked one.
fn silent_miss(output: &foamy_helper::child::Output) -> bool {
    output.status.code() == Some(1)
        && !output.overflowed
        && output.stderr.iter().all(u8::is_ascii_whitespace)
}

/// Any other failure: what it said, else how it ended.
fn failed(output: &foamy_helper::child::Output) -> Failure {
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !stderr.trim().is_empty() {
        unavailable(&stderr)
    } else if output.overflowed {
        unavailable("secret-tool's answer was too long")
    } else {
        unavailable(&format!("secret-tool ended with {}", output.status))
    }
}

impl Vault for SecretTool {
    fn get(&self) -> Result<Option<String>, Failure> {
        let output = SecretTool::run(self.command("lookup"))?;
        if output.success() {
            return Ok(Some(output.stdout_lossy()));
        }
        // A missing or broken keyring says why.
        if !silent_miss(&output) {
            return Err(failed(&output));
        }
        if self.exists()? {
            Err(locked())
        } else {
            Ok(None)
        }
    }

    fn put(&self, secret: &str) -> Result<(), Failure> {
        let output = SecretTool::run(self.command("store").stdin(secret.as_bytes().to_vec()))?;
        if output.success() {
            Ok(())
        } else {
            Err(unavailable(&String::from_utf8_lossy(&output.stderr)))
        }
    }

    fn delete(&self) -> Result<(), Failure> {
        let output = SecretTool::run(self.command("clear"))?;
        if !output.success() && !silent_miss(&output) {
            return Err(failed(&output));
        }
        // Removed, or nothing it could remove: either way, what is left?
        if self.exists()? {
            Err(locked())
        } else {
            Ok(())
        }
    }
}

/// For tests; shared between threads, like the keyring between helpers.
#[cfg(test)]
#[derive(Default)]
pub struct Memory {
    secret: Mutex<Option<String>>,
    /// A locked keyring whose unlock prompt is dismissed: its item can't be
    /// read, removed or replaced.
    pub locked: AtomicBool,
    /// Reads work, but storing fails (say, the keyring can't write).
    pub read_only: AtomicBool,
}

#[cfg(test)]
impl Memory {
    /// What is stored, locked or not.
    pub fn held(&self) -> Option<String> {
        self.secret.lock().unwrap().clone()
    }

    fn is_locked(&self) -> bool {
        self.locked.load(Ordering::SeqCst)
    }
}

#[cfg(test)]
impl Vault for Memory {
    fn get(&self) -> Result<Option<String>, Failure> {
        match self.held() {
            Some(_) if self.is_locked() => Err(locked()),
            held => Ok(held),
        }
    }
    fn put(&self, secret: &str) -> Result<(), Failure> {
        if self.is_locked() {
            return Err(unavailable("Cannot create an item in a locked collection"));
        }
        if self.read_only.load(Ordering::SeqCst) {
            return Err(unavailable("No space left on device"));
        }
        *self.secret.lock().unwrap() = Some(secret.into());
        Ok(())
    }
    fn delete(&self) -> Result<(), Failure> {
        let mut secret = self.secret.lock().unwrap();
        if secret.is_some() && self.is_locked() {
            return Err(locked());
        }
        *secret = None;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use std::path::{Path, PathBuf};

    /// `tests/fake-secret-tool.sh` in a directory of its own, which holds
    /// its state (the item, whether it is locked, its log).
    fn fake(tag: &str) -> (PathBuf, SecretTool) {
        let dir =
            std::env::temp_dir().join(format!("foamy-zendesk-vault-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let script = dir.join("secret-tool");
        std::fs::write(&script, include_str!("../tests/fake-secret-tool.sh")).unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o700)).unwrap();
        let mut tool = SecretTool::new("acme.zendesk.com", "foamy");
        tool.program = script.into();
        (dir, tool)
    }

    fn set(dir: &Path, item: bool, locked: bool) {
        let _ = std::fs::remove_file(dir.join("item"));
        let _ = std::fs::remove_file(dir.join("locked"));
        if item {
            std::fs::write(dir.join("item"), r#"{"access_token":"A1"}"#).unwrap();
        }
        if locked {
            std::fs::write(dir.join("locked"), "").unwrap();
        }
    }

    fn code<T: std::fmt::Debug>(result: Result<T, Failure>) -> String {
        result.unwrap_err().code
    }

    #[test]
    fn a_locked_item_is_neither_absent_nor_removed() {
        let (dir, tool) = fake("cases");
        // (case, item, locked, get, delete, item left after delete)
        let cases = [
            ("unlocked with the item", true, false, "some", "ok", false),
            ("unlocked without it", false, false, "none", "ok", false),
            (
                "locked with the item",
                true,
                true,
                "KEYRING_LOCKED",
                "KEYRING_LOCKED",
                true,
            ),
            ("locked without it", false, true, "none", "ok", false),
        ];
        for (case, item, locked, get, delete, left) in cases {
            set(&dir, item, locked);
            let got = match tool.get() {
                Ok(Some(secret)) => {
                    assert_eq!(secret, r#"{"access_token":"A1"}"#, "{case}");
                    "some".to_string()
                }
                Ok(None) => "none".into(),
                Err(failure) => failure.code,
            };
            assert_eq!(got, get, "get, {case}");
            let deleted = match tool.delete() {
                Ok(()) => "ok".to_string(),
                Err(failure) => failure.code,
            };
            assert_eq!(deleted, delete, "delete, {case}");
            assert_eq!(
                dir.join("item").exists(),
                left,
                "the item after delete, {case}"
            );
        }
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_silent_miss_is_checked_and_any_other_failure_is_an_error() {
        let (dir, tool) = fake("failures");
        set(&dir, false, false);
        std::fs::write(dir.join("search-fails"), "").unwrap();
        // Not found, but whether it is there can't be told: an error, not "absent".
        assert_eq!(code(tool.get()), "KEYRING_UNAVAILABLE");
        assert_eq!(code(tool.delete()), "KEYRING_UNAVAILABLE");
        std::fs::remove_file(dir.join("search-fails")).unwrap();
        std::fs::write(dir.join("lookup-dies"), "").unwrap();
        let failure = tool.get().unwrap_err();
        assert_eq!(failure.code, "KEYRING_UNAVAILABLE");
        assert!(failure.message.contains("signal"), "{}", failure.message);
        // A found item is read without asking `search`.
        std::fs::remove_file(dir.join("lookup-dies")).unwrap();
        set(&dir, true, false);
        std::fs::remove_file(dir.join("log")).unwrap();
        assert!(tool.get().unwrap().is_some());
        assert_eq!(
            std::fs::read_to_string(dir.join("log")).unwrap(),
            "lookup\n"
        );
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
