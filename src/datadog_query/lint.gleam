/// Static lints over Datadog query strings.
///
/// These lints operate on already-rendered query text. They flag patterns
/// that Datadog rejects at runtime so callers can surface compile-time
/// warnings or errors before `terraform apply`.
import gleam/list
import gleam/string

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
