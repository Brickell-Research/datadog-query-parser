/// Constructors for Datadog scope-filter fragments.
///
/// Each function emits a single tag-filter expression suitable for use inside
/// a Datadog scope (`{...}`). Values are quoted via `quote.value` so callers
/// can pass raw user input.
///
/// Empty-list inputs to `tag_in` / `tag_not_in` return the empty string —
/// callers that compose filters are expected to handle empty fragments
/// (typically by stripping surrounding boolean joiners).
import datadog_query/quote
import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// `name:value` — wildcards in `value` are preserved.
pub fn tag(name: String, value: String) -> String {
  name <> ":" <> quote.value(value)
}

/// `!name:value` — negated tag filter.
pub fn negated_tag(name: String, value: String) -> String {
  "!" <> name <> ":" <> quote.value(value)
}

/// `name IN (v1, v2, ...)` — empty list returns "".
pub fn tag_in(name: String, values: List(String)) -> String {
  case values {
    [] -> ""
    _ ->
      name
      <> " IN ("
      <> values |> list.map(quote.value) |> string.join(", ")
      <> ")"
  }
}

/// `name NOT IN (v1, v2, ...)` — empty list returns "".
pub fn tag_not_in(name: String, values: List(String)) -> String {
  case values {
    [] -> ""
    _ ->
      name
      <> " NOT IN ("
      <> values |> list.map(quote.value) |> string.join(", ")
      <> ")"
  }
}

/// `name:>value` — numeric greater-than. Value rendered without quoting
/// since comparisons are only meaningful on numbers/durations.
pub fn tag_gt(name: String, value: Float) -> String {
  name <> ":>" <> format_float(value)
}

/// `name:>=value`.
pub fn tag_gte(name: String, value: Float) -> String {
  name <> ":>=" <> format_float(value)
}

/// `name:<value`.
pub fn tag_lt(name: String, value: Float) -> String {
  name <> ":<" <> format_float(value)
}

/// `name:<=value`.
pub fn tag_lte(name: String, value: Float) -> String {
  name <> ":<=" <> format_float(value)
}

/// Datadog rejects scientific notation in thresholds, but `float.to_string`
/// emits `1.0e3` for whole values. Render whole numbers as `N.0`, fall back
/// to `float.to_string` for fractional values.
fn format_float(f: Float) -> String {
  let truncated = float.truncate(f)
  case int.to_float(truncated) == f {
    True -> int.to_string(truncated) <> ".0"
    False -> float.to_string(f)
  }
}

/// Integer variant of `tag_gt`. Convenience for callers working with
/// integer thresholds (e.g. `@http.status_code:>=500`).
pub fn tag_gt_int(name: String, value: Int) -> String {
  name <> ":>" <> int.to_string(value)
}

pub fn tag_gte_int(name: String, value: Int) -> String {
  name <> ":>=" <> int.to_string(value)
}

pub fn tag_lt_int(name: String, value: Int) -> String {
  name <> ":<" <> int.to_string(value)
}

pub fn tag_lte_int(name: String, value: Int) -> String {
  name <> ":<=" <> int.to_string(value)
}

/// `name:~pattern` — regex match. Pattern is quoted via `quote.value` so
/// patterns containing whitespace round-trip safely.
pub fn tag_regex(name: String, pattern: String) -> String {
  name <> ":~" <> quote.value(pattern)
}

/// Joins sub-filters with ` AND `. Empty-string fragments are dropped so
/// composing with `tag_in([])` doesn't leave a dangling joiner.
/// Empty list (or all-empty list) returns "".
pub fn all_of(filters: List(String)) -> String {
  filters |> list.filter(fn(f) { f != "" }) |> string.join(" AND ")
}

/// Joins sub-filters with ` OR `. See `all_of` for empty-fragment handling.
pub fn any_of(filters: List(String)) -> String {
  filters |> list.filter(fn(f) { f != "" }) |> string.join(" OR ")
}

/// `NOT <filter>` — boolean negation of a sub-expression.
/// Differs from `negated_tag`: that emits `!key:value` (negation of a
/// SimpleFilter token); this emits `NOT (...)` over arbitrary sub-filters.
/// Empty input returns "".
pub fn not_(filter: String) -> String {
  case filter {
    "" -> ""
    _ -> "NOT " <> group(filter)
  }
}

/// Wraps a sub-filter in parens. Empty input returns "" (no `()`).
pub fn group(filter: String) -> String {
  case filter {
    "" -> ""
    _ -> "(" <> filter <> ")"
  }
}

/// Bare `*` — match-everything scope. Use as the entire filter body of a
/// scope: `metric{*}`.
pub const wildcard_all: String = "*"
