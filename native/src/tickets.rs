//! The inbox: unsolved tickets assigned to the signed-in agent, and
//! unassigned unsolved tickets in the agent's groups, with their latest
//! comments. Comments are fetched only for tickets whose `updated_at` the
//! caller doesn't already have.

use std::collections::{BTreeMap, BTreeSet, HashMap};

use foamy_helper::Failure;
use serde_json::{Map, Value, json};

use crate::auth::Account;
use crate::http::Reply;
use crate::oauth::encode;

/// At most this many tickets per search, and in the whole inbox.
const MAX_TICKETS: usize = 100;
/// Latest comments kept per ticket.
const COMMENTS: usize = 20;
/// Changed tickets whose comments one run fetches; the rest come next run.
const MAX_COMMENT_FETCHES: usize = 25;
/// Characters of one comment body.
const MAX_BODY: usize = 16 * 1024;
/// Group searches (one per group).
const MAX_GROUPS: usize = 20;

fn expired() -> Failure {
    Failure::coded("EXPIRED", "The Zendesk sign-in has expired. Sign in again.")
}

fn get(account: &Account, access: &str, path: &str) -> Result<Value, Failure> {
    let Reply { status, body } = account.client.request("GET", path, Some(access), None)?;
    match status {
        200 => Ok(body),
        401 => Err(expired()),
        403 => Err(Failure::coded(
            "FORBIDDEN",
            "Zendesk didn't allow this request. The OAuth client needs read access.",
        )),
        429 => Err(Failure::coded(
            "RATE_LIMITED",
            "Zendesk asked to slow down. Trying again later.",
        )),
        status => Err(Failure::coded(
            "HTTP",
            crate::text::message("Zendesk answered HTTP %1.", &[&status]),
        )),
    }
}

fn id_of(value: &Value) -> Option<u64> {
    value.as_u64()
}

/// `2026-11-06T19:02:11Z` → milliseconds since the epoch (Zendesk sends UTC).
pub fn epoch_ms(text: &str) -> Option<i64> {
    let b = text.as_bytes();
    if b.len() < 20
        || b[4] != b'-'
        || b[7] != b'-'
        || b[10] != b'T'
        || b[13] != b':'
        || b[16] != b':'
    {
        return None;
    }
    let n = |range: std::ops::Range<usize>| text.get(range)?.parse::<i64>().ok();
    let (year, month, day) = (n(0..4)?, n(5..7)?, n(8..10)?);
    let (hour, minute, second) = (n(11..13)?, n(14..16)?, n(17..19)?);
    if !(1..=12).contains(&month)
        || !(1..=31).contains(&day)
        || hour > 23
        || minute > 59
        || second > 60
    {
        return None;
    }
    // Days from civil (Howard Hinnant's algorithm).
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(((days * 24 + hour) * 60 + minute) * 60_000 + second * 1000)
}

fn status(raw: &str) -> &'static str {
    match raw {
        "new" => "New",
        "open" => "Open",
        "pending" => "Pending",
        "hold" => "On-hold",
        "solved" => "Solved",
        "closed" => "Closed",
        _ => "Open",
    }
}

fn priority(raw: Option<&str>) -> &'static str {
    match raw {
        Some("low") => "Low",
        Some("high") => "High",
        Some("urgent") => "Urgent",
        _ => "Normal",
    }
}

/// Zendesk derives `plain_body` from the HTML body and leaves some of the
/// HTML behind: literal entities (`&nbsp;` mostly), a space after each line
/// break and blank-paragraph lines. Decode the entities, trim each line and
/// keep at most one blank line in a row.
fn tidy(text: &str) -> String {
    let mut decoded = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find('&') {
        decoded.push_str(&rest[..at]);
        rest = &rest[at..];
        let entity = rest[1..]
            .find(';')
            .filter(|&end| end <= 10)
            .and_then(|end| entity(&rest[1..=end]).map(|c| (c, end + 2)));
        match entity {
            Some((c, len)) => {
                decoded.push(c);
                rest = &rest[len..];
            }
            None => {
                decoded.push('&');
                rest = &rest[1..];
            }
        }
    }
    decoded.push_str(rest);

    let mut out = String::with_capacity(decoded.len());
    let mut blank = false;
    for line in decoded.replace('\u{a0}', " ").lines() {
        let line = line.trim();
        if line.is_empty() {
            blank = !out.is_empty();
            continue;
        }
        if !out.is_empty() {
            out.push_str(if blank { "\n\n" } else { "\n" });
        }
        out.push_str(line);
        blank = false;
    }
    out
}

/// The character an HTML entity name (between `&` and `;`) stands for.
fn entity(name: &str) -> Option<char> {
    Some(match name {
        "nbsp" => ' ',
        "amp" => '&',
        "lt" => '<',
        "gt" => '>',
        "quot" => '"',
        "apos" => '\'',
        _ => {
            let code = name.strip_prefix('#')?;
            let code = match code.strip_prefix(['x', 'X']) {
                Some(hex) => u32::from_str_radix(hex, 16).ok()?,
                None => code.parse().ok()?,
            };
            return char::from_u32(code).filter(|c| *c != '\0');
        }
    })
}

fn clip(text: &str) -> String {
    let text = text.trim();
    if text.chars().count() <= MAX_BODY {
        return text.to_string();
    }
    let mut out: String = text.chars().take(MAX_BODY).collect();
    out.push('…');
    out
}

fn search(account: &Account, access: &str, query: &str) -> Result<Vec<Value>, Failure> {
    let body = get(
        account,
        access,
        &format!(
            "/api/v2/search.json?query={}&sort_by=updated_at&sort_order=desc&per_page={MAX_TICKETS}",
            encode(query)
        ),
    )?;
    Ok(body["results"]
        .as_array()
        .map(|results| {
            results
                .iter()
                .filter(|r| {
                    r.get("result_type")
                        .and_then(Value::as_str)
                        .unwrap_or("ticket")
                        == "ticket"
                })
                .cloned()
                .collect()
        })
        .unwrap_or_default())
}

fn names(
    account: &Account,
    access: &str,
    ids: &BTreeSet<u64>,
) -> Result<HashMap<u64, String>, Failure> {
    let mut names = HashMap::new();
    let ids: Vec<u64> = ids.iter().copied().collect();
    for chunk in ids.chunks(100) {
        let list = chunk
            .iter()
            .map(u64::to_string)
            .collect::<Vec<_>>()
            .join(",");
        let body = get(
            account,
            access,
            &format!("/api/v2/users/show_many.json?ids={list}"),
        )?;
        for user in body["users"].as_array().into_iter().flatten() {
            if let (Some(id), Some(name)) = (id_of(&user["id"]), user["name"].as_str()) {
                names.insert(id, name.to_string());
            }
        }
    }
    Ok(names)
}

fn group_names(body: &Value) -> Vec<(u64, String)> {
    body["groups"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|g| !g["deleted"].as_bool().unwrap_or(false))
        .filter_map(|g| Some((id_of(&g["id"])?, g["name"].as_str()?.to_string())))
        .collect()
}

/// `known`: ticket id → `updated_at` the caller already has comments for.
pub fn fetch(account: &Account, known: &Map<String, Value>) -> Result<Value, Failure> {
    let access = account.access_token()?;
    let me = get(account, &access, "/api/v2/users/me.json")?;
    let me_id =
        id_of(&me["user"]["id"]).ok_or_else(|| Failure::coded("HTTP", "Zendesk sent no user."))?;
    let mine = group_names(&get(
        account,
        &access,
        &format!("/api/v2/users/{me_id}/groups.json"),
    )?);
    let mut group_name: HashMap<u64, String> = mine.iter().cloned().collect();
    // Names of other groups a ticket assigned to me may sit in (best effort).
    if let Ok(all) = get(account, &access, "/api/v2/groups.json?per_page=100") {
        group_name.extend(group_names(&all));
    }

    // Assigned to me first, then unassigned in each of my groups; one entry per ticket.
    let mut found: BTreeMap<u64, Value> = BTreeMap::new();
    let mut queries = vec!["type:ticket status<solved assignee:me".to_string()];
    queries.extend(
        mine.iter()
            .take(MAX_GROUPS)
            .map(|(id, _)| format!("type:ticket status<solved assignee:none group:{id}")),
    );
    for query in &queries {
        for ticket in search(account, &access, query)? {
            if let Some(id) = id_of(&ticket["id"]) {
                found.entry(id).or_insert(ticket);
            }
        }
    }
    let mut tickets: Vec<Value> = found.into_values().collect();
    tickets.sort_by(|a, b| b["updated_at"].as_str().cmp(&a["updated_at"].as_str()));
    tickets.truncate(MAX_TICKETS);

    // Comments for tickets the caller doesn't have at this `updated_at`.
    let mut comments: HashMap<u64, Vec<Value>> = HashMap::new();
    let mut deferred = BTreeSet::new();
    for ticket in &tickets {
        let id = id_of(&ticket["id"]).unwrap_or(0);
        let updated = ticket["updated_at"].as_str().unwrap_or("");
        if known.get(&id.to_string()).and_then(Value::as_str) == Some(updated) {
            continue;
        }
        if comments.len() >= MAX_COMMENT_FETCHES {
            deferred.insert(id);
            continue;
        }
        let body = get(
            account,
            &access,
            &format!("/api/v2/tickets/{id}/comments.json?sort_order=desc&per_page={COMMENTS}"),
        )?;
        comments.insert(id, body["comments"].as_array().cloned().unwrap_or_default());
    }

    let mut people = BTreeSet::new();
    for ticket in &tickets {
        people.extend(
            ["assignee_id", "requester_id"]
                .iter()
                .filter_map(|k| id_of(&ticket[*k])),
        );
    }
    for list in comments.values() {
        people.extend(list.iter().filter_map(|c| id_of(&c["author_id"])));
    }
    let name = names(account, &access, &people)?;
    let person = |id: Option<u64>| id.and_then(|id| name.get(&id).cloned()).unwrap_or_default();

    let out: Vec<Value> = tickets
        .iter()
        .map(|ticket| {
            let id = id_of(&ticket["id"]).unwrap_or(0);
            let assignee = id_of(&ticket["assignee_id"]);
            let mut entry = json!({
                "id": id.to_string(),
                "subject": ticket["subject"].as_str().unwrap_or("").trim(),
                "status": status(ticket["status"].as_str().unwrap_or("")),
                "priority": priority(ticket["priority"].as_str()),
                "assignee": if assignee.is_some() { person(assignee) } else { "Unassigned".into() },
                "mine": assignee == Some(me_id),
                "group": id_of(&ticket["group_id"]).and_then(|g| group_name.get(&g).cloned()).unwrap_or_default(),
                "requester": person(id_of(&ticket["requester_id"])),
                "updated_at": ticket["updated_at"].as_str().unwrap_or(""),
            });
            match comments.get(&id) {
                Some(list) => {
                    entry["comments"] = Value::Array(
                        list.iter()
                            .filter_map(|c| {
                                Some(json!({
                                    "id": id_of(&c["id"])?,
                                    "author": person(id_of(&c["author_id"])),
                                    "mine": id_of(&c["author_id"]) == Some(me_id),
                                    "public": c["public"].as_bool().unwrap_or(true),
                                    "created": epoch_ms(c["created_at"].as_str()?)?,
                                    "body": clip(&tidy(c["plain_body"].as_str().or(c["body"].as_str()).unwrap_or(""))),
                                }))
                            })
                            .collect(),
                    )
                }
                None => entry[if deferred.contains(&id) { "deferred" } else { "unchanged" }] = json!(true),
            }
            entry
        })
        .collect();
    Ok(json!({
        "ok": true,
        "me": {"id": me_id.to_string(), "name": me["user"]["name"].as_str().unwrap_or("")},
        "tickets": out,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamps_parse_as_utc() {
        assert_eq!(epoch_ms("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(epoch_ms("2026-11-06T19:02:11Z"), Some(1_793_991_731_000));
        assert_eq!(epoch_ms("2000-02-29T12:00:00Z"), Some(951_825_600_000));
        assert_eq!(epoch_ms("not a date"), None);
        assert_eq!(epoch_ms("2026-13-01T00:00:00Z"), None);
    }

    #[test]
    fn fields_map_to_the_inbox_vocabulary() {
        assert_eq!(status("hold"), "On-hold");
        assert_eq!(status("pending"), "Pending");
        assert_eq!(priority(None), "Normal");
        assert_eq!(priority(Some("urgent")), "Urgent");
        assert_eq!(clip("  hi  "), "hi");
        assert_eq!(
            clip(&"x".repeat(MAX_BODY + 5)).chars().count(),
            MAX_BODY + 1
        );
    }

    #[test]
    fn html_leftovers_are_tidied() {
        assert_eq!(
            tidy(
                "Hei,\n &nbsp;\n Fikk denne i teams nå.\n Har ikke trykket på noe.\n\n &nbsp;\n\nMvh"
            ),
            "Hei,\n\nFikk denne i teams nå.\nHar ikke trykket på noe.\n\nMvh"
        );
        assert_eq!(
            tidy("a &amp; b &lt;c&gt; &#233;&#xE9; &quot;"),
            "a & b <c> éé \""
        );
        assert_eq!(tidy("R&D & co; &bogus; &#0; &"), "R&D & co; &bogus; &#0; &");
        assert_eq!(tidy("&nbsp;\n\u{a0}\nhi\n&nbsp;"), "hi");
    }
}
