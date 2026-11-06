//! OAuth pieces with no I/O: the account address, PKCE, the authorize URL,
//! the loopback callback request, and URL encoding.

use foamy_helper::Failure;
use foamy_helper::hash::sha256;

/// Read-only access to the account. The admin's OAuth client must allow it.
pub const SCOPE: &str = "read";
/// The loopback redirect path registered in the OAuth client.
pub const CALLBACK_PATH: &str = "/callback";

fn invalid(message: &str) -> Failure {
    Failure::coded("INVALID_ARGUMENT", message)
}

/// `acme`, `acme.zendesk.com` or `https://acme.zendesk.com/` → `acme.zendesk.com`.
/// Only `*.zendesk.com`: OAuth and the API live on the account's subdomain.
pub fn normalize_address(input: &str) -> Result<String, Failure> {
    let text = input.trim().to_ascii_lowercase();
    let text = text.strip_prefix("https://").unwrap_or(&text);
    let text = text.strip_suffix('/').unwrap_or(text);
    let subdomain = text.strip_suffix(".zendesk.com").unwrap_or(text);
    let valid = !subdomain.is_empty()
        && subdomain.len() <= 63
        && subdomain
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        && !subdomain.starts_with('-')
        && !subdomain.ends_with('-');
    if !valid {
        return Err(invalid(
            "Enter your Zendesk address, like acme or acme.zendesk.com.",
        ));
    }
    Ok(format!("{subdomain}.zendesk.com"))
}

/// The OAuth client's unique identifier, as the admin entered it.
pub fn validate_client_id(input: &str) -> Result<String, Failure> {
    let id = input.trim();
    let valid = !id.is_empty()
        && id.len() <= 128
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'-' | b'.'));
    if valid {
        Ok(id.to_string())
    } else {
        Err(invalid("Enter the OAuth client's unique identifier."))
    }
}

/// A redirect port the plugin may listen on (no privileged ports).
pub fn validate_port(input: &str) -> Result<u16, Failure> {
    match input.trim().parse::<u16>() {
        Ok(port) if port >= 1024 => Ok(port),
        _ => Err(invalid("Choose a redirect port between 1024 and 65535.")),
    }
}

pub fn redirect_uri(port: u16) -> String {
    format!("http://127.0.0.1:{port}{CALLBACK_PATH}")
}

/// base64url without padding (RFC 7636 appendix A).
pub fn base64url(data: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let n = chunk
            .iter()
            .enumerate()
            .fold(0u32, |n, (i, &b)| n | (b as u32) << (16 - 8 * i));
        for i in 0..=chunk.len() {
            out.push(ALPHABET[(n >> (18 - 6 * i) & 63) as usize] as char);
        }
    }
    out
}

/// S256 challenge for a verifier.
pub fn challenge(verifier: &str) -> String {
    base64url(&sha256(verifier.as_bytes()))
}

/// Percent-encodes everything but RFC 3986 unreserved characters.
pub fn encode(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for byte in text.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
            out.push(byte as char);
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

fn decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let hex = |b: u8| (b as char).to_digit(16);
        match bytes[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < bytes.len() => {
                if let (Some(h), Some(l)) = (hex(bytes[i + 1]), hex(bytes[i + 2])) {
                    out.push((h * 16 + l) as u8);
                    i += 3;
                    continue;
                }
                out.push(b'%');
            }
            b => out.push(b),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

pub struct Authorize<'a> {
    pub base: &'a str,
    pub client_id: &'a str,
    pub redirect_uri: &'a str,
    pub challenge: &'a str,
    pub state: &'a str,
}

impl Authorize<'_> {
    pub fn url(&self) -> String {
        format!(
            "{}/oauth/authorizations/new?response_type=code&client_id={}&redirect_uri={}&scope={}&state={}&code_challenge={}&code_challenge_method=S256",
            self.base,
            encode(self.client_id),
            encode(self.redirect_uri),
            encode(SCOPE),
            encode(self.state),
            encode(self.challenge)
        )
    }
}

/// What the browser brought back to the loopback listener.
#[derive(Debug, PartialEq, Eq)]
pub enum Callback {
    /// `/callback?code=…&state=…`
    Code { code: String, state: String },
    /// `/callback?error=…` (the user denied access, or the client is misconfigured).
    Denied { error: String, state: String },
    /// Any other path (favicon, a stray request): answer 404 and keep waiting.
    Other,
}

/// Parses an HTTP request head (`GET /callback?… HTTP/1.1\r\n…`).
pub fn parse_callback(head: &str) -> Callback {
    let line = head.lines().next().unwrap_or("");
    let mut parts = line.split(' ');
    let (Some("GET"), Some(target)) = (parts.next(), parts.next()) else {
        return Callback::Other;
    };
    let (path, query) = target.split_once('?').unwrap_or((target, ""));
    if path != CALLBACK_PATH {
        return Callback::Other;
    }
    let mut code = None;
    let mut state = String::new();
    let mut error = None;
    for pair in query.split('&') {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        match key {
            "code" => code = Some(decode(value)),
            "state" => state = decode(value),
            "error" => error = Some(decode(value)),
            _ => {}
        }
    }
    match (code, error) {
        (_, Some(error)) => Callback::Denied { error, state },
        (Some(code), None) if !code.is_empty() => Callback::Code { code, state },
        _ => Callback::Other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pkce_matches_rfc_7636() {
        assert_eq!(
            challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        );
        assert_eq!(base64url(b""), "");
        assert_eq!(base64url(b"f"), "Zg");
        assert_eq!(base64url(b"fo"), "Zm8");
        assert_eq!(base64url(b"foo"), "Zm9v");
        assert_eq!(base64url(&[0xfb, 0xff]), "-_8");
    }

    #[test]
    fn addresses_normalize_to_the_zendesk_subdomain() {
        for input in [
            "acme",
            "ACME.zendesk.com",
            "https://acme.zendesk.com/",
            " acme ",
        ] {
            assert_eq!(normalize_address(input).unwrap(), "acme.zendesk.com");
        }
        for input in [
            "",
            "-acme",
            "acme.example.com",
            "ac me",
            "https://evil.com/x.zendesk.com",
            "a/b",
        ] {
            assert_eq!(
                normalize_address(input).unwrap_err().code,
                "INVALID_ARGUMENT",
                "{input}"
            );
        }
    }

    #[test]
    fn client_ids_and_ports_are_checked() {
        assert_eq!(
            validate_client_id(" foamy_zendesk-1 ").unwrap(),
            "foamy_zendesk-1"
        );
        assert!(validate_client_id("has space").is_err());
        assert!(validate_client_id("").is_err());
        assert_eq!(validate_port("47823").unwrap(), 47823);
        for port in ["80", "0", "70000", "x", ""] {
            assert!(validate_port(port).is_err(), "{port}");
        }
    }

    #[test]
    fn authorize_url_carries_pkce_state_and_scope() {
        let url = Authorize {
            base: "https://acme.zendesk.com",
            client_id: "foamy",
            redirect_uri: &redirect_uri(47823),
            challenge: "abc-_",
            state: "s1",
        }
        .url();
        assert_eq!(
            url,
            "https://acme.zendesk.com/oauth/authorizations/new?response_type=code&client_id=foamy\
             &redirect_uri=http%3A%2F%2F127.0.0.1%3A47823%2Fcallback&scope=read&state=s1\
             &code_challenge=abc-_&code_challenge_method=S256"
        );
    }

    #[test]
    fn callbacks_are_parsed_and_decoded() {
        assert_eq!(
            parse_callback("GET /callback?code=a%2Bb&state=s%3D HTTP/1.1\r\nHost: x\r\n\r\n"),
            Callback::Code {
                code: "a+b".into(),
                state: "s=".into()
            }
        );
        assert_eq!(
            parse_callback("GET /callback?error=access_denied&state=s HTTP/1.1\r\n"),
            Callback::Denied {
                error: "access_denied".into(),
                state: "s".into()
            }
        );
        assert_eq!(
            parse_callback("GET /favicon.ico HTTP/1.1\r\n"),
            Callback::Other
        );
        assert_eq!(
            parse_callback("POST /callback?code=x HTTP/1.1\r\n"),
            Callback::Other
        );
        assert_eq!(
            parse_callback("GET /callback?code=&state=s HTTP/1.1\r\n"),
            Callback::Other
        );
        assert_eq!(parse_callback("garbage"), Callback::Other);
        assert_eq!(decode("%zz%4"), "%zz%4");
    }
}
