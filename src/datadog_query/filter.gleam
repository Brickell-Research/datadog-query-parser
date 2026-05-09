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
