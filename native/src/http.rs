//! HTTPS to the Zendesk account: the kit's TLS (Graviola, system roots),
//! proxies from the environment, bounded replies, and one absolute deadline
//! per request for every socket read and write (the connector below is
//! foamy-train's, which closes ureq's CONNECT-reply gap), and a connect that
//! falls back between IPv6 and IPv4 addresses (foamy-todoist's).

use std::net::SocketAddr;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use foamy_helper::{Failure, tls};
use serde_json::Value;
use ureq::config::AutoHeaderValue;
use ureq::tls::{Certificate, RootCerts, TlsConfig, TlsProvider};
use ureq::unversioned::resolver::{DefaultResolver, Resolver};
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

/// How long a connect to one address may take while other addresses are
/// left to try. A healthy route answers well within it, and it leaves room
/// for one lost SYN (Linux resends it after 1 s).
const ATTEMPT: Duration = Duration::from_millis(2500);

/// Opens the TCP connection like ureq's `TcpConnector`, one address at a
/// time, but each attempt except the last gets at most [`ATTEMPT`] and the
/// addresses alternate between IPv6 and IPv4 (RFC 8305). ureq alone splits
/// the budget geometrically, so a host that lists eight AAAA records first
/// left its IPv4 addresses a few milliseconds when the IPv6
/// route drops packets.
#[derive(Debug, Default)]
struct FallbackConnector(TcpConnector);

impl<In: Transport> Connector<In> for FallbackConnector {
    type Out = <TcpConnector as Connector<In>>::Out;

    fn connect(
        &self,
        details: &ConnectionDetails,
        chained: Option<In>,
    ) -> Result<Option<Self::Out>, ureq::Error> {
        if chained.is_some() {
            return self.0.connect(details, chained);
        }
        let started = Instant::now();
        let budget = *details.timeout.after;
        let addrs = interleave(&details.addrs);
        let mut last = None;
        for (index, &addr) in addrs.iter().enumerate() {
            let left = budget.saturating_sub(started.elapsed());
            if left.is_zero() {
                break;
            }
            // The last address keeps the whole remaining budget, so a host
            // with one address waits as long as before.
            let attempt = if index + 1 == addrs.len() {
                left
            } else {
                left.min(ATTEMPT)
            };
            let mut one = details.resolver.empty();
            one.push(addr);
            let single = ConnectionDetails {
                uri: details.uri,
                addrs: one,
                config: details.config,
                request_level: details.request_level,
                resolver: details.resolver,
                now: (details.current_time)(),
                timeout: NextTimeout {
                    after: attempt.into(),
                    ..details.timeout
                },
                current_time: details.current_time.clone(),
                run_connector: details.run_connector.clone(),
                register_shutdown: details.register_shutdown.clone(),
            };
            match self.0.connect(&single, None) {
                Err(error @ ureq::Error::Timeout(_)) => last = Some(error),
                Err(ureq::Error::Io(error)) if elsewhere(&error) => {
                    last = Some(ureq::Error::Io(error));
                }
                done => return done,
            }
        }
        if started.elapsed() >= budget {
            return Err(ureq::Error::Timeout(details.timeout.reason));
        }
        Err(last
            .unwrap_or_else(|| std::io::Error::from(std::io::ErrorKind::ConnectionRefused).into()))
    }
}

/// A failure of this address only: another one may still connect. The same
/// kinds ureq moves on for.
fn elsewhere(error: &std::io::Error) -> bool {
    use std::io::ErrorKind::*;
    matches!(
        error.kind(),
        ConnectionRefused | HostUnreachable | NetworkUnreachable | AddrNotAvailable
    )
}

/// The resolver's addresses with the families alternating, starting with
/// the family of its first: v6 v6 v4 v4 becomes v6 v4 v6 v4.
fn interleave(addrs: &[SocketAddr]) -> Vec<SocketAddr> {
    let first_v6 = addrs.first().is_some_and(SocketAddr::is_ipv6);
    let (first, other): (Vec<SocketAddr>, Vec<SocketAddr>) =
        addrs.iter().partition(|addr| addr.is_ipv6() == first_v6);
    let mut out = Vec::with_capacity(addrs.len());
    for index in 0..first.len().max(other.len()) {
        out.extend(first.get(index));
        out.extend(other.get(index));
    }
    out
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
        Client::with_resolver(base, timeout, DefaultResolver::default())
    }

    /// [`Client::new`] with another resolver: tests give fixed addresses.
    fn with_resolver(base: String, timeout: Duration, resolver: impl Resolver) -> Client {
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
                .chain(FallbackConnector::default())
                .chain(DeadlineConnector(deadline.clone()))
                .chain(RustlsConnector::default());
        Client {
            base,
            agent: Agent::with_parts(config.build(), connector, resolver),
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
    use std::io::{ErrorKind, Read, Write};
    use std::net::{TcpListener, TcpStream};
    use ureq::unversioned::resolver::ResolvedSocketAddrs;

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

    /// A reply over 4 MB is refused, a redirect comes back as it is (the
    /// bearer token never follows it elsewhere), and a body that is not JSON
    /// is `Null`.
    #[test]
    fn replies_are_bounded_never_followed_and_json_or_null() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let paths = Arc::new(Mutex::new(Vec::new()));
        let seen = Arc::clone(&paths);
        // One connection at a time; every reply closes its connection.
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
                seen.lock().unwrap().push(path.clone());
                match path.as_str() {
                    "/big" => {
                        let _ = stream.write_all(
                            b"HTTP/1.1 200 OK\r\nContent-Length: 10000000\r\nConnection: close\r\n\r\n",
                        );
                        // Until the client gives up reading.
                        let chunk = vec![b' '; 64 * 1024];
                        while stream.write_all(&chunk).is_ok() {}
                    }
                    "/moved" => {
                        let _ = stream.write_all(
                            b"HTTP/1.1 302 Found\r\nLocation: /elsewhere\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                        );
                    }
                    _ => {
                        let _ = stream.write_all(
                            b"HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\nnot json",
                        );
                    }
                }
            }
        });
        let client = Client::new(base, Duration::from_secs(5));
        let big = client.request("GET", "/big", None, None);
        let failure = big.expect_err("a reply over 4 MB is refused");
        assert_eq!(
            (failure.code.as_str(), failure.message.as_str()),
            ("HTTP", "Zendesk sent an oversized reply.")
        );
        let moved = client.request("GET", "/moved", Some("A1"), None).unwrap();
        assert_eq!(moved.status, 302, "the redirect comes back, not followed");
        let plain = client.request("GET", "/plain", None, None).unwrap();
        assert_eq!(
            (plain.status, plain.body),
            (200, Value::Null),
            "a body that is not JSON"
        );
        // `/plain` was asked after `/moved` returned, so a followed redirect
        // would be in the list by now.
        assert_eq!(*paths.lock().unwrap(), ["/big", "/moved", "/plain"]);
    }

    /// The addresses the test chooses, whatever the URL's host.
    #[derive(Debug)]
    struct Fixed(Vec<SocketAddr>);

    impl Resolver for Fixed {
        fn resolve(
            &self,
            _uri: &ureq::http::Uri,
            _config: &ureq::config::Config,
            _timeout: NextTimeout,
        ) -> Result<ResolvedSocketAddrs, ureq::Error> {
            let mut addrs = self.empty();
            for &addr in &self.0 {
                addrs.push(addr);
            }
            Ok(addrs)
        }
    }

    /// An address that never answers a connect, like a route that drops
    /// packets: a listener whose accept queue is full, so the kernel drops
    /// every new SYN. Keep the returned listener and streams alive.
    fn silent(ip: &str) -> (SocketAddr, TcpListener, Vec<TcpStream>) {
        let listener = TcpListener::bind((ip, 0)).unwrap();
        let addr = listener.local_addr().unwrap();
        let mut queued = Vec::new();
        loop {
            match TcpStream::connect_timeout(&addr, Duration::from_millis(200)) {
                Ok(stream) => queued.push(stream),
                Err(error) if error.kind() == ErrorKind::TimedOut => {
                    return (addr, listener, queued);
                }
                Err(error) => panic!("filling the accept queue: {error}"),
            }
            assert!(queued.len() < 8192, "the accept queue never filled");
        }
    }

    /// An address that refuses at once: nothing listens there any more.
    fn refusing() -> SocketAddr {
        TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
    }

    #[test]
    fn a_silent_ipv6_route_falls_back_to_ipv4() {
        // A CloudFront-like host: AAAA records first. The IPv6 ones never
        // answer; the IPv4 one is a working server.
        let (v6, _listener, _queued) = silent("::1");
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let v4 = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buffer = [0u8; 1024];
            let _ = stream.read(&mut buffer);
            let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}");
        });
        let client =
            Client::with_resolver(format!("http://{v4}"), TIMEOUT, Fixed(vec![v6, v6, v6, v4]));
        let started = Instant::now();
        let reply = client
            .request("GET", "/x", None, None)
            .unwrap_or_else(|failure| panic!("no fallback: {failure:?}"));
        assert_eq!(reply.status, 200);
        server.join().unwrap();
        assert!(
            started.elapsed() < Duration::from_secs(5),
            "IPv4 was reached only after {:?}",
            started.elapsed()
        );
    }

    #[test]
    fn a_host_that_never_answers_times_out_at_the_deadline() {
        let (v4, _listener4, _queued4) = silent("127.0.0.1");
        let (v6, _listener6, _queued6) = silent("::1");
        let limit = Duration::from_secs(3);
        let client = Client::with_resolver(
            "http://127.0.0.1:9".to_string(),
            limit,
            Fixed(vec![v6, v4, v6, v4]),
        );
        let started = Instant::now();
        let failure = client.request("GET", "/x", None, None).unwrap_err();
        assert_eq!(failure.code, "TIMEOUT");
        assert!(
            started.elapsed() < limit + Duration::from_millis(500),
            "the connect outlasted the request's limit: {:?}",
            started.elapsed()
        );
    }

    #[test]
    fn a_host_that_refuses_everywhere_is_a_network_failure() {
        let client = Client::with_resolver(
            "http://127.0.0.1:9".to_string(),
            TIMEOUT,
            Fixed(vec![refusing(), refusing()]),
        );
        let started = Instant::now();
        let failure = client.request("GET", "/x", None, None).unwrap_err();
        assert_eq!(failure.code, "NETWORK");
        assert!(started.elapsed() < Duration::from_secs(2));
    }

    #[test]
    fn the_address_families_alternate() {
        let v6: SocketAddr = "[2001:db8::1]:443".parse().unwrap();
        let v4: SocketAddr = "192.0.2.1:443".parse().unwrap();
        for (given, expected) in [
            (vec![v6, v6, v4, v4], vec![v6, v4, v6, v4]),
            (vec![v4, v6, v6, v6], vec![v4, v6, v6, v6]),
            (vec![v6, v6], vec![v6, v6]),
            (vec![], vec![]),
        ] {
            assert_eq!(interleave(&given), expected, "{given:?}");
        }
    }
}
