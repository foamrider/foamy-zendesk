//! Where the tokens live: the Secret Service keyring through `secret-tool`
//! (libsecret), one item per account and OAuth client. Nothing else on disk.

#[cfg(test)]
use std::cell::RefCell;
use std::io::ErrorKind;
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

pub trait Vault {
    fn get(&self) -> Result<Option<String>, Failure>;
    fn put(&self, secret: &str) -> Result<(), Failure>;
    fn delete(&self) -> Result<(), Failure>;
}

/// `secret-tool {lookup|store|clear} service foamy-zendesk host <host> client <id>`.
pub struct SecretTool {
    host: String,
    client_id: String,
}

impl SecretTool {
    pub fn new(host: &str, client_id: &str) -> SecretTool {
        SecretTool {
            host: host.into(),
            client_id: client_id.into(),
        }
    }

    fn command(&self, verb: &str) -> Bounded {
        let mut command = Bounded::new("secret-tool").arg(verb);
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
}

impl Vault for SecretTool {
    fn get(&self) -> Result<Option<String>, Failure> {
        let output = SecretTool::run(self.command("lookup"))?;
        if output.success() {
            return Ok(Some(output.stdout_lossy()));
        }
        // "Not found" is a silent exit 1; a missing or broken keyring says why.
        let stderr = String::from_utf8_lossy(&output.stderr);
        if stderr.trim().is_empty() {
            Ok(None)
        } else {
            Err(unavailable(&stderr))
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
        let stderr = String::from_utf8_lossy(&output.stderr);
        if output.success() || stderr.trim().is_empty() {
            Ok(())
        } else {
            Err(unavailable(&stderr))
        }
    }
}

/// For tests.
#[cfg(test)]
#[derive(Default)]
pub struct Memory(pub RefCell<Option<String>>);

#[cfg(test)]
impl Vault for Memory {
    fn get(&self) -> Result<Option<String>, Failure> {
        Ok(self.0.borrow().clone())
    }
    fn put(&self, secret: &str) -> Result<(), Failure> {
        *self.0.borrow_mut() = Some(secret.into());
        Ok(())
    }
    fn delete(&self) -> Result<(), Failure> {
        *self.0.borrow_mut() = None;
        Ok(())
    }
}
