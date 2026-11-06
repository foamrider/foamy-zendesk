//! HTTPS to the Zendesk account: the kit's TLS (Graviola, system roots),
//! proxies from the environment, bounded replies, and one absolute deadline
//! per request for every socket read and write (the connector below is
//! foamy-train's, which closes ureq's CONNECT-reply gap).

use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use foamy_helper::{Failure, tls};
use serde_json::Value;
use ureq::config::AutoHeaderValue;
use ureq::tls::{Certificate, RootCerts, TlsConfig, TlsProvider};
use ureq::unversioned::resolver::DefaultResolver;
use ureq::unversioned::transport::{
    Buffers, ConnectProxyConnector, ConnectionDetails, Connector, NextTimeout, RustlsConnector,
    TcpConnector, Transport,
};
use ureq::{Agent, Proxy, Timeout};

/// Test-only override of `https://<host>`: a loopback `http://` base URL.
pub const BASE_ENV: &str = "FOAMY_ZENDESK_BASE_URL";
const USER_AGENT: &str = "foamy-zendesk-helper";
const MAX_BYTES: u64 = 4_000_000;
pub const TIMEOUT: Duration = Duration::from_secs(20);

pub fn network() -> Failure {
    Failure::coded("NETWORK", "Can't reach Zendesk. Check your connection.")
}

fn timed_out() -> Failure {
    Failure::coded("TIMEOUT", "Zendesk didn't answer in time.")
}

/// Where requests go: `https://<host>`, or a loopback test server.
pub fn base_for(host: &str) -> Result<String, Failure> {
    match std::env::var(BASE_ENV) {
        Err(_) => Ok(format!("https://{host}")),
        Ok(value) => loopback(&value).ok_or_else(network),
    }
}

/// `http://127.0.0.1:<port>` (or `localhost`), nothing else.
pub fn loopback(text: &str) -> Option<String> {
    let rest = text.strip_prefix("http://")?;
    let rest = rest.strip_suffix('/').unwrap_or(rest);
    let port = rest
        .strip_prefix("127.0.0.1:")
        .or_else(|| rest.strip_prefix("localhost:"))?;
    port.parse::<u16>().ok().filter(|&p| p != 0)?;
    Some(format!("http://{rest}"))
}

fn roots() -> Arc<Vec<Certificate<'static>>> {
    static ROOTS: OnceLock<Arc<Vec<Certificate<'static>>>> = OnceLock::new();
    ROOTS
        .get_or_init(|| {
            Arc::new(
                tls::system_roots_der()
                    .iter()
                    .map(|der| Certificate::from_der(der.as_ref()).to_owned())
                    .collect(),
            )
        })
        .clone()
}

#[derive(Debug, Clone, Default)]
struct Deadline(Arc<Mutex<Option<Instant>>>);

impl Deadline {
    fn set(&self, at: Instant) {
        *self.0.lock().unwrap_or_else(|e| e.into_inner()) = Some(at);
    }
    fn get(&self) -> Option<Instant> {
        *self.0.lock().unwrap_or_else(|e| e.into_inner())
    }
}

#[derive(Debug)]
struct DeadlineConnector(Deadline);

impl<In: Transport> Connector<In> for DeadlineConnector {
    type Out = DeadlineTransport<In>;

    fn connect(
        &self,
        _details: &ConnectionDetails,
        chained: Option<In>,
    ) -> Result<Option<Self::Out>, ureq::Error> {
        Ok(chained.map(|inner| DeadlineTransport {
            inner,
            deadline: self.0.clone(),
        }))
    }
}

/// Every read and write capped at the time left before the request's deadline.
#[derive(Debug)]
struct DeadlineTransport<T> {
    inner: T,
    deadline: Deadline,
}

impl<T> DeadlineTransport<T> {
    fn cap(&self, timeout: NextTimeout) -> Result<NextTimeout, ureq::Error> {
        let Some(at) = self.deadline.get() else {
            return Ok(timeout);
        };
        let left = at.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(ureq::Error::Timeout(Timeout::Global));
        }
        let left = left.into();
        Ok(if left < timeout.after {
            NextTimeout {
                after: left,
                reason: Timeout::Global,
                ..timeout
            }
        } else {
            timeout
        })
    }
}

impl<T: Transport> Transport for DeadlineTransport<T> {
    fn buffers(&mut self) -> &mut dyn Buffers {
        self.inner.buffers()
    }
    fn transmit_output(&mut self, amount: usize, timeout: NextTimeout) -> Result<(), ureq::Error> {
        let timeout = self.cap(timeout)?;
        self.inner.transmit_output(amount, timeout)
    }
    fn await_input(&mut self, timeout: NextTimeout) -> Result<bool, ureq::Error> {
        let timeout = self.cap(timeout)?;
        self.inner.await_input(timeout)
    }
    fn is_open(&mut self) -> bool {
        self.inner.is_open()
    }
    fn is_tls(&self) -> bool {
        self.inner.is_tls()
    }
}

/// A reply: HTTP status and the JSON body (`Value::Null` when empty or not JSON).
#[derive(Debug)]
pub struct Reply {
    pub status: u16,
    pub body: Value,
}

pub struct Client {
    pub base: String,
    agent: Agent,
    deadline: Deadline,
    timeout: Duration,
}

impl Client {
    pub fn new(base: String, timeout: Duration) -> Client {
        let deadline = Deadline::default();
        let mut config = Agent::config_builder()
            .http_status_as_error(false)
            .max_redirects(0)
            .user_agent(USER_AGENT)
            .accept_encoding(AutoHeaderValue::None)
            .proxy(if base.starts_with("https://") {
                Proxy::try_from_env()
            } else {
                None
            });
        if base.starts_with("https://") {
            config = config.tls_config(
                TlsConfig::builder()
                    .provider(TlsProvider::Rustls)
                    .root_certs(RootCerts::Specific(roots()))
                    .unversioned_rustls_crypto_provider(tls::provider())
                    .build(),
            );
        }
        let connector =
            ().chain(ConnectProxyConnector::default())
                .chain(TcpConnector::default())
                .chain(DeadlineConnector(deadline.clone()))
                .chain(RustlsConnector::default());
        Client {
            base,
            agent: Agent::with_parts(config.build(), connector, DefaultResolver::default()),
            deadline,
            timeout,
        }
    }

    /// `method` is GET, POST (JSON body) or DELETE; `bearer` adds the token.
    pub fn request(
        &self,
        method: &str,
        path: &str,
        bearer: Option<&str>,
        body: Option<&Value>,
    ) -> Result<Reply, Failure> {
        if self.base.starts_with("https://") && !tls::cpu_supported() {
            return Err(Failure::coded("TLS_UNSUPPORTED", tls::UNSUPPORTED));
        }
        let url = format!("{}{path}", self.base);
        let authorization = bearer.map(|token| format!("Bearer {token}"));
        self.deadline.set(Instant::now() + self.timeout);
        let timeout = Some(self.timeout);
        let response = match (method, body) {
            ("POST", Some(body)) => {
                let mut request = self
                    .agent
                    .post(&url)
                    .header("Accept", "application/json")
                    .header("Content-Type", "application/json");
                if let Some(value) = &authorization {
                    request = request.header("Authorization", value);
                }
                request
                    .config()
                    .timeout_global(timeout)
                    .build()
                    .send(body.to_string().as_bytes())
            }
            ("DELETE", None) => {
                let mut request = self.agent.delete(&url).header("Accept", "application/json");
                if let Some(value) = &authorization {
                    request = request.header("Authorization", value);
                }
                request.config().timeout_global(timeout).build().call()
            }
            _ => {
                let mut request = self.agent.get(&url).header("Accept", "application/json");
                if let Some(value) = &authorization {
                    request = request.header("Authorization", value);
                }
                request.config().timeout_global(timeout).build().call()
            }
        };
        let mut response = response.map_err(classify)?;
        let status = response.status().as_u16();
        let data = response
            .body_mut()
            .with_config()
            .limit(MAX_BYTES + 1)
            .read_to_vec()
            .map_err(classify)?;
        if data.len() as u64 > MAX_BYTES {
            return Err(Failure::coded("HTTP", "Zendesk sent an oversized reply."));
        }
        Ok(Reply {
            status,
            body: serde_json::from_slice(&data).unwrap_or(Value::Null),
        })
    }
}

fn classify(error: ureq::Error) -> Failure {
    match error {
        ureq::Error::Timeout(_) => timed_out(),
        ureq::Error::Io(ref io) if foamy_helper::net::is_deadline(io) => timed_out(),
        ureq::Error::Io(ref io) if io.kind() == std::io::ErrorKind::TimedOut => timed_out(),
        ureq::Error::BodyExceedsLimit(_) => {
            Failure::coded("HTTP", "Zendesk sent an oversized reply.")
        }
        _ => network(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;

    #[test]
    fn only_loopback_overrides_are_accepted() {
        assert_eq!(
            loopback("http://127.0.0.1:8080/").unwrap(),
            "http://127.0.0.1:8080"
        );
        assert_eq!(
            loopback("http://localhost:9").unwrap(),
            "http://localhost:9"
        );
        for bad in [
            "https://127.0.0.1:1",
            "http://evil.com:80",
            "http://127.0.0.1",
            "http://127.0.0.1:0",
        ] {
            assert!(loopback(bad).is_none(), "{bad}");
        }
    }

    #[test]
    fn a_trickling_server_cannot_outlast_the_deadline() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buffer = [0u8; 1024];
            let _ = stream.read(&mut buffer);
            let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 100000\r\n\r\n");
            for _ in 0..100 {
                if stream.write_all(b" ").is_err() {
                    break;
                }
                std::thread::sleep(Duration::from_millis(100));
            }
        });
        let client = Client::new(
            format!("http://127.0.0.1:{port}"),
            Duration::from_millis(600),
        );
        let started = Instant::now();
        let failure = client.request("GET", "/x", None, None).unwrap_err();
        assert_eq!(failure.code, "TIMEOUT");
        assert!(
            started.elapsed() < Duration::from_secs(3),
            "{:?}",
            started.elapsed()
        );
    }
}
