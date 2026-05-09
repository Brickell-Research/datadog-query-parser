import datadog_query/lint
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
