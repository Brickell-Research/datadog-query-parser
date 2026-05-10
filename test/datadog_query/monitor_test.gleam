import datadog_query/filter
import datadog_query/monitor.{
  Gt, Gte, Last5m, Last15m, Lt, Lte, Monitor, to_string,
}
import datadog_query/query.{Avg, Query, Sum}
import test_helpers

// ==== to_string ====
pub fn to_string_test() {
  [
    #(
      "avg cpu over 5m greater than threshold",
      Monitor(
        Avg,
        Last5m,
        Query(Avg, "system.cpu.user", filter.tag("env", "prod"), [], []),
        Gt,
        80.0,
      ),
      "avg(last_5m):avg:system.cpu.user{env:prod} > 80",
    ),
    #(
      "sum requests over 15m greater-equal threshold",
      Monitor(
        Sum,
        Last15m,
        Query(Sum, "http.requests", filter.wildcard_all, [], ["as_count()"]),
        Gte,
        1000.0,
      ),
      "sum(last_15m):sum:http.requests{*}.as_count() >= 1000",
    ),
    #(
      "fractional threshold preserved",
      Monitor(
        Avg,
        Last5m,
        Query(Avg, "latency.p95", filter.tag("env", "prod"), [], []),
        Lt,
        0.5,
      ),
      "avg(last_5m):avg:latency.p95{env:prod} < 0.5",
    ),
    #(
      "less-equal comparator",
      Monitor(
        Avg,
        Last5m,
        Query(Avg, "metric", filter.wildcard_all, [], []),
        Lte,
        10.0,
      ),
      "avg(last_5m):avg:metric{*} <= 10",
    ),
  ]
  |> test_helpers.table_test_1(to_string)
}
