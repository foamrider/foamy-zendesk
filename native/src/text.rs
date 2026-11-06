//! User-facing messages are catalog keys (the plugin's `i18n/en.json`), so the
//! panel can translate them. Details that vary follow the key after U+001F
//! separators and fill its `%1`, `%2`… there: `"Zendesk answered HTTP %1.\u{1f}503"`.

use std::fmt::Display;

pub const SEPARATOR: char = '\u{1f}';

/// `key` with `values` for its placeholders.
pub fn message(key: &str, values: &[&dyn Display]) -> String {
    let mut out = key.to_string();
    for value in values {
        out.push(SEPARATOR);
        // A separator inside a value would shift the ones after it.
        out.push_str(&value.to_string().replace(SEPARATOR, " "));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn values_follow_the_key() {
        assert_eq!(message("Plain.", &[]), "Plain.");
        assert_eq!(
            message("Port %1 (%2).", &[&47823, &"a\u{1f}b"]),
            "Port %1 (%2).\u{1f}47823\u{1f}a b"
        );
    }
}
