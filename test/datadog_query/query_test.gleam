import datadog_query/filter
import datadog_query/query.{
  Avg, Count, Max, Min, Percentile, Query, Sum, by, new, to_string,
  with_function,
}
import test_helpers

// ==== to_string ====
pub fn to_string_test() {
  [
    #(
      "minimal sum query with simple scope",
      Query(Sum, "http.requests", filter.tag("env", "prod"), [], []),
      "sum:http.requests{env:prod}",
    ),
    #(
      "wildcard scope",
      Query(Avg, "system.cpu.user", filter.wildcard_all, [], []),
      "avg:system.cpu.user{*}",
    ),
    #(
      "empty scope",
      Query(Count, "events", "", [], []),
      "count:events{}",
    ),
    #(
      "grouping appended after scope",
      Query(Max, "system.load.1", filter.tag("env", "prod"), ["host", "region"], []),
      "max:system.load.1{env:prod} by {host,region}",
    ),
    #(
      "single postfix function",
      Query(Sum, "http.requests", filter.tag("env", "prod"), [], ["as_count()"]),
      "sum:http.requests{env:prod}.as_count()",
    ),
    #(
      "function chain",
      Query(
        Sum,
        "http.requests",
        filter.tag("env", "prod"),
        [],
        ["as_count()", "rollup(sum, 60)"],
      ),
      "sum:http.requests{env:prod}.as_count().rollup(sum, 60)",
    ),
    #(
      "percentile aggregator",
      Query(Percentile(95), "trace.web.duration", filter.tag("service", "api"), [], []),
      "p95:trace.web.duration{service:api}",
    ),
    #(
      "min aggregator",
      Query(Min, "queue.depth", filter.wildcard_all, [], []),
      "min:queue.depth{*}",
    ),
    #(
      "composed scope (and_of two filters)",
      Query(
        Sum,
        "metric",
        filter.all_of([filter.tag("env", "prod"), filter.tag("service", "api")]),
        [],
        [],
      ),
      "sum:metric{env:prod AND service:api}",
    ),
  ]
  |> test_helpers.table_test_1(to_string)
}

// ==== builder helpers ====
pub fn builder_test() {
  let q =
    new(Sum, "http.requests", filter.tag("env", "prod"))
    |> by(["host"])
    |> with_function("as_count()")
    |> with_function("rollup(sum, 60)")
  case
    to_string(q)
    == "sum:http.requests{env:prod} by {host}.as_count().rollup(sum, 60)"
  {
    True -> Nil
    False -> panic as "builder pipeline produced unexpected output"
  }
}
