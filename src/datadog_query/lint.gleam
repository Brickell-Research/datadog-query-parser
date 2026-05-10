/// Static lints over Datadog query strings.
///
/// These lints operate on already-rendered query text. They flag patterns
/// that Datadog rejects at runtime so callers can surface compile-time
/// warnings or errors before `terraform apply`.
import gleam/list
import gleam/string

pub type BalanceError {
  Unmatched(String)
  Unclosed(String)
}

/// Scans a Datadog query string for `@`-prefixed attribute names used in
/// filter position (e.g. `@type:foo` or `@type IN (...)`).
///
/// Datadog metric filters strip the leading `@` from log facets when log-based
/// metrics are generated — the metric tag for log facet `@type` is just `type`.
/// A query that filters on `@type` against a log-based metric is rejected by
/// the SLO API with `400: numerator query is invalid`.
///
/// Returns a deduplicated list of `@`-prefixed attribute names found.
pub fn at_prefixed_attrs(query: String) -> List(String) {
  query
  |> string.replace("{", " ")
  |> string.replace("}", " ")
  |> string.replace("(", " ")
  |> string.replace(")", " ")
  |> string.replace(",", " ")
  |> string.split(" ")
  |> list.filter_map(token_to_at_attr)
  |> list.unique
}

fn token_to_at_attr(token: String) -> Result(String, Nil) {
  let stripped = case string.starts_with(token, "!") {
    True -> string.drop_start(token, 1)
    False -> token
  }
  case string.starts_with(stripped, "@") {
    False -> Error(Nil)
    True -> {
      let attr = case string.split_once(stripped, ":") {
        Ok(#(before_colon, _)) -> before_colon
        Error(_) -> stripped
      }
      case attr {
        "@" -> Error(Nil)
        _ -> Ok(attr)
      }
    }
  }
}

/// Verifies `{` / `}` are balanced. Ignores braces inside double-quoted
/// strings so `tag:"a{b}c"` doesn't trigger a false positive.
pub fn unbalanced_braces(query: String) -> Result(Nil, BalanceError) {
  check_balance(query, "{", "}")
}

/// Verifies `(` / `)` are balanced (string-aware).
pub fn unbalanced_parens(query: String) -> Result(Nil, BalanceError) {
  check_balance(query, "(", ")")
}

fn check_balance(
  query: String,
  open: String,
  close: String,
) -> Result(Nil, BalanceError) {
  let result = scan_balance(string.to_graphemes(query), open, close, 0, False)
  case result {
    BalanceOk -> Ok(Nil)
    BalanceUnmatched -> Error(Unmatched(close))
    BalanceUnclosed -> Error(Unclosed(open))
  }
}

type BalanceState {
  BalanceOk
  BalanceUnmatched
  BalanceUnclosed
}

fn scan_balance(
  graphemes: List(String),
  open: String,
  close: String,
  depth: Int,
  in_string: Bool,
) -> BalanceState {
  case graphemes {
    [] ->
      case depth {
        0 -> BalanceOk
        _ -> BalanceUnclosed
      }
    [g, ..rest] -> {
      case in_string, g {
        True, "\"" -> scan_balance(rest, open, close, depth, False)
        True, _ -> scan_balance(rest, open, close, depth, True)
        False, "\"" -> scan_balance(rest, open, close, depth, True)
        False, _ -> {
          case g == open, g == close {
            True, _ -> scan_balance(rest, open, close, depth + 1, False)
            _, True ->
              case depth {
                0 -> BalanceUnmatched
                _ -> scan_balance(rest, open, close, depth - 1, False)
              }
            _, _ -> scan_balance(rest, open, close, depth, False)
          }
        }
      }
    }
  }
}

/// Detects scope-internal artifacts produced by composing `tag_in([])` /
/// `tag_not_in([])` returning `""`. Returns the offending fragment(s) when
/// the scope contains a leading/trailing/doubled boolean joiner.
///
/// Examples flagged:
///   `metric{ AND env:prod}`     → ["leading AND"]
///   `metric{env:prod AND }`     → ["trailing AND"]
///   `metric{env:prod AND  AND service:api}` → ["doubled joiner"]
pub fn dangling_joiner(query: String) -> List(String) {
  query
  |> extract_scopes
  |> list.flat_map(check_scope_joiners)
}

fn extract_scopes(query: String) -> List(String) {
  // Best-effort: split on `{` and `}` and pick the alternating "inside" parts.
  // Doesn't try to handle nested braces in quoted values — those are flagged
  // by `unbalanced_braces` instead.
  case string.split(query, "{") {
    [_, ..rest] ->
      list.filter_map(rest, fn(chunk) {
        case string.split_once(chunk, "}") {
          Ok(#(inside, _)) -> Ok(inside)
          Error(_) -> Error(Nil)
        }
      })
    _ -> []
  }
}

fn check_scope_joiners(scope: String) -> List(String) {
  let trimmed = string.trim(scope)
  case trimmed {
    "" -> []
    _ -> {
      let leading = case
        string.starts_with(trimmed, "AND ")
        || string.starts_with(trimmed, "OR ")
      {
        True -> ["leading joiner: " <> trimmed]
        False -> []
      }
      let trailing = case
        string.ends_with(trimmed, " AND")
        || string.ends_with(trimmed, " OR")
      {
        True -> ["trailing joiner: " <> trimmed]
        False -> []
      }
      let doubled = case
        string.contains(trimmed, " AND  AND ")
        || string.contains(trimmed, " OR  OR ")
        || string.contains(trimmed, " AND  OR ")
        || string.contains(trimmed, " OR  AND ")
      {
        True -> ["doubled joiner: " <> trimmed]
        False -> []
      }
      list.flatten([leading, trailing, doubled])
    }
  }
}

/// Detects tag *names* that collide with grammar keywords. Datadog accepts
/// these tokens as separators, so a tag literally named `IN` produces
/// confusing parse errors.
pub fn reserved_word_as_tag_name(query: String) -> List(String) {
  let reserved = ["IN", "NOT", "AND", "OR", "true", "false"]
  query
  |> extract_scopes
  |> list.flat_map(fn(scope) {
    scope
    |> string.replace("(", " ")
    |> string.replace(")", " ")
    |> string.replace(",", " ")
    |> string.split(" ")
    |> list.filter_map(fn(token) {
      case string.split_once(token, ":") {
        Ok(#(name, _)) ->
          case list.contains(reserved, name) {
            True -> Ok(name)
            False -> Error(Nil)
          }
        Error(_) -> Error(Nil)
      }
    })
  })
  |> list.unique
}

/// Detects values where wildcards have been collapsed to literals by
/// quoting. Datadog matches `*` as a wildcard in bare values but as a
/// literal asterisk inside `"..."`.
///
/// Example: `metric{service:"foo*"}` — the `*` is now literal.
pub fn wildcard_in_quoted_value(query: String) -> Bool {
  scan_wildcard_quoted(string.to_graphemes(query), False)
}

fn scan_wildcard_quoted(graphemes: List(String), in_string: Bool) -> Bool {
  case graphemes {
    [] -> False
    [g, ..rest] ->
      case in_string, g {
        True, "*" -> True
        True, "\\" ->
          case rest {
            [_, ..tail] -> scan_wildcard_quoted(tail, True)
            [] -> False
          }
        True, "\"" -> scan_wildcard_quoted(rest, False)
        True, _ -> scan_wildcard_quoted(rest, True)
        False, "\"" -> scan_wildcard_quoted(rest, True)
        False, _ -> scan_wildcard_quoted(rest, False)
      }
  }
}

/// Detects `metric{} by {tag}` — a legal but suspicious query (a copy-paste
/// bug that would group a "match-everything" set; usually `metric{*}` was
/// intended).
pub fn empty_scope_with_grouping(query: String) -> Bool {
  case string.split_once(query, "{}") {
    Ok(#(_, after)) -> string.contains(after, "by {")
    Error(_) -> False
  }
}
