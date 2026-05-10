import datadog_query/lint.{Unclosed, Unmatched}
import gleam/list
import gleam/string
import test_helpers

// ==== at_prefixed_attrs ====
// Datadog metric filters strip `@` from log facets when generating log-based
// metrics, so `@type:foo` and `@type IN (...)` are rejected with a 400. The
// detector finds these in resolved query strings so callers can emit a
// compile-time warning.
pub fn at_prefixed_attrs_test() {
  [
    #("no @ anywhere returns empty", "sum:http.requests{env:prod}", []),
    #("scalar @attr:value", "sum:metric{@type:success}.as_count()", ["@type"]),
    #(
      "list @attr IN (...)",
      "sum:app.events.hits{env:prod AND @type IN (Foo::Bar::ok, Foo::Baz::ok)}.as_count()",
      ["@type"],
    ),
    #("negated scalar !@attr:value", "sum:metric{!@severity:debug}.as_count()", [
      "@severity",
    ]),
    #(
      "negated list @attr NOT IN (...)",
      "sum:metric{@type NOT IN (a, b)}.as_count()",
      ["@type"],
    ),
    #(
      "email-like values are not flagged (preceded by alphanum)",
      "sum:metric{owner:user@example.com}.as_count()",
      [],
    ),
    #(
      "bare `@` not followed by identifier is ignored",
      "sum:metric{tag:@}.as_count()",
      [],
    ),
    #(
      "multiple distinct @-prefixed attrs",
      "sum:metric{@type:foo AND @severity:bar}.as_count()",
      ["@severity", "@type"],
    ),
    #(
      "duplicate @-prefixed attr is deduplicated",
      "sum:metric{@type:foo OR @type:bar}.as_count()",
      ["@type"],
    ),
  ]
  |> test_helpers.table_test_1(fn(query) {
    lint.at_prefixed_attrs(query) |> list.sort(string.compare)
  })
}

// ==== unbalanced_braces ====
pub fn unbalanced_braces_test() {
  [
    #("balanced", "sum:m{env:prod}", Ok(Nil)),
    #(
      "unclosed open brace",
      "sum:m{env:prod",
      Error(Unclosed("{")),
    ),
    #(
      "stray close brace",
      "sum:m{env:prod}}",
      Error(Unmatched("}")),
    ),
    #("braces inside quoted value ignored", "m{tag:\"a{b}c\"}", Ok(Nil)),
  ]
  |> test_helpers.table_test_1(lint.unbalanced_braces)
}

// ==== unbalanced_parens ====
pub fn unbalanced_parens_test() {
  [
    #("balanced", "m{env IN (a, b)}", Ok(Nil)),
    #("unclosed", "m{env IN (a, b}", Error(Unclosed("("))),
    #("stray close", "m{env IN a, b))}", Error(Unmatched(")"))),
    #("parens inside quoted value ignored", "m{tag:\"f(x)\"}", Ok(Nil)),
  ]
  |> test_helpers.table_test_1(lint.unbalanced_parens)
}

// ==== dangling_joiner ====
pub fn dangling_joiner_test() {
  [
    #("clean scope", "sum:m{env:prod AND service:api}", []),
    #("leading AND", "sum:m{ AND env:prod}", ["leading joiner: AND env:prod"]),
    #("trailing OR", "sum:m{env:prod OR }", ["trailing joiner: env:prod OR"]),
    #(
      "doubled AND from empty fragment",
      "sum:m{env:prod AND  AND service:api}",
      ["doubled joiner: env:prod AND  AND service:api"],
    ),
    #("empty scope is fine", "sum:m{}", []),
    #("wildcard scope is fine", "sum:m{*}", []),
  ]
  |> test_helpers.table_test_1(lint.dangling_joiner)
}

// ==== reserved_word_as_tag_name ====
pub fn reserved_word_as_tag_name_test() {
  [
    #("clean scope", "sum:m{env:prod}", []),
    #("tag literally named IN", "sum:m{IN:foo}", ["IN"]),
    #("tag literally named AND", "sum:m{AND:foo}", ["AND"]),
    #("tag literally named true", "sum:m{true:foo}", ["true"]),
    #(
      "multiple distinct collisions deduped",
      "sum:m{IN:a AND OR:b OR IN:c}",
      ["IN", "OR"],
    ),
  ]
  |> test_helpers.table_test_1(fn(query) {
    lint.reserved_word_as_tag_name(query) |> list.sort(string.compare)
  })
}

// ==== wildcard_in_quoted_value ====
pub fn wildcard_in_quoted_value_test() {
  [
    #("clean wildcard outside quotes", "sum:m{service:foo*}", False),
    #("collapsed wildcard inside quotes", "sum:m{service:\"foo*\"}", True),
    #("escaped quote then wildcard inside string", "m{x:\"a\\\"*\"}", True),
    #("no wildcards anywhere", "sum:m{env:prod}", False),
  ]
  |> test_helpers.table_test_1(lint.wildcard_in_quoted_value)
}

// ==== empty_scope_with_grouping ====
pub fn empty_scope_with_grouping_test() {
  [
    #("empty scope with grouping", "sum:m{} by {host}", True),
    #("empty scope without grouping", "sum:m{}", False),
    #("non-empty scope with grouping", "sum:m{env:prod} by {host}", False),
    #("wildcard scope with grouping", "sum:m{*} by {host}", False),
  ]
  |> test_helpers.table_test_1(lint.empty_scope_with_grouping)
}
