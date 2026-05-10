/// Builders for Datadog metric monitor strings.
///
/// Shape: `<aggregator>(<window>):<query> <comparator> <threshold>`.
/// e.g. `avg(last_5m):avg:system.cpu.user{env:prod} > 80`.
import datadog_query/query.{type Aggregator, type Query} as q
import gleam/float
import gleam/int

pub type EvaluationWindow {
  Last1m
  Last5m
  Last10m
  Last15m
  Last30m
  Last1h
  Last2h
  Last4h
  Last1d
}

pub type Comparator {
  Gt
  Gte
  Lt
  Lte
}

pub type Monitor {
  Monitor(
    aggregator: Aggregator,
    window: EvaluationWindow,
    query: Query,
    comparator: Comparator,
    threshold: Float,
  )
}

pub fn to_string(monitor: Monitor) -> String {
  q.aggregator_to_string(monitor.aggregator)
  <> "("
  <> window_to_string(monitor.window)
  <> "):"
  <> q.to_string(monitor.query)
  <> " "
  <> comparator_to_string(monitor.comparator)
  <> " "
  <> format_threshold(monitor.threshold)
}

pub fn window_to_string(window: EvaluationWindow) -> String {
  case window {
    Last1m -> "last_1m"
    Last5m -> "last_5m"
    Last10m -> "last_10m"
    Last15m -> "last_15m"
    Last30m -> "last_30m"
    Last1h -> "last_1h"
    Last2h -> "last_2h"
    Last4h -> "last_4h"
    Last1d -> "last_1d"
  }
}

pub fn comparator_to_string(comparator: Comparator) -> String {
  case comparator {
    Gt -> ">"
    Gte -> ">="
    Lt -> "<"
    Lte -> "<="
  }
}

fn format_threshold(f: Float) -> String {
  let truncated = float.truncate(f)
  case int.to_float(truncated) == f {
    True -> int.to_string(truncated)
    False -> float.to_string(f)
  }
}
