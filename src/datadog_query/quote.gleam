/// Quoting rules for Datadog tag values.
///
/// Datadog's metric query parser greedily consumes characters after `tag:`
/// until it hits a delimiter, so most values can be emitted bare. Quoting is
/// only required when the value contains characters that *are* delimiters in
/// the scope grammar: whitespace, commas, and parentheses.
///
/// Two values are intentionally NOT quoted:
/// - Values containing `:` — bare `tag:foo::bar` is parsed correctly; quoting
///   it (`tag:"foo::bar"`) is rejected with a 400.
/// - Values containing `*` — wildcards are part of the filter grammar; quoting
///   collapses them to literal characters.
import gleam/string

/// Wraps a value in double quotes when it contains characters that would
/// otherwise be ambiguous to the Datadog scope parser. Embedded double quotes
/// are escaped.
pub fn value(input: String) -> String {
  case needs_quoting(input) {
    True -> "\"" <> string.replace(input, "\"", "\\\"") <> "\""
    False -> input
  }
}

fn needs_quoting(input: String) -> Bool {
  case string.contains(input, "*") {
    True -> False
    False ->
      string.contains(input, " ")
      || string.contains(input, "\t")
      || string.contains(input, ",")
      || string.contains(input, "(")
      || string.contains(input, ")")
  }
}
