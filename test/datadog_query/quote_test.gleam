import datadog_query/quote
import test_helpers

// ==== Quote ====
// Datadog requires quoting only when the value contains a scope-grammar
// delimiter (whitespace, comma, paren). Colons and wildcards stay bare.
pub fn value_test() {
  [
    #("plain alphanumeric stays unquoted", "production", "production"),
    #(
      "value with dots/hyphens/underscores stays unquoted",
      "payments-api_v2.beta",
      "payments-api_v2.beta",
    ),
    #(
      "value with embedded colons stays unquoted",
      "api::v0::ctrl",
      "api::v0::ctrl",
    ),
    #("value with whitespace gets quoted", "my service", "\"my service\""),
    #("value with tab gets quoted", "a\tb", "\"a\tb\""),
    #("value with comma gets quoted", "a,b", "\"a,b\""),
    #("value with parens gets quoted", "f(x)", "\"f(x)\""),
    #("bare wildcard stays unquoted", "*", "*"),
    #("prefix wildcard stays unquoted", "payments-*", "payments-*"),
    #("suffix wildcard stays unquoted", "*api", "*api"),
    #("wildcard + colon stays unquoted", "api::v*", "api::v*"),
    #(
      "wildcard wins over whitespace (preserves wildcard semantics)",
      "foo *",
      "foo *",
    ),
    #(
      "embedded double quote gets escaped",
      "he said \"hi\"",
      "\"he said \\\"hi\\\"\"",
    ),
  ]
  |> test_helpers.table_test_1(quote.value)
}
