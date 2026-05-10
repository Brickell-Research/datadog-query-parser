/// Builders for the full Datadog metric query envelope.
///
/// A rendered query has the shape:
///   `<aggregator>:<metric>{<scope>} by {<grouping>}.<func>().<func>()`
///
/// `aggregator` is one of `sum`, `avg`, `max`, `min`, `count`, or a
/// percentile (`p50`, `p75`, `p90`, `p95`, `p99`). `scope` is a filter
/// fragment from `datadog_query/filter`. `grouping` is a list of tag names.
/// `functions` is the postfix function chain (`as_count`, `rollup`, ...) —
/// we don't model individual functions; callers pass already-rendered
/// strings like `"as_count()"` or `"rollup(sum, 60)"`.
import gleam/int
import gleam/list
import gleam/string

pub type Aggregator {
  Sum
  Avg
  Max
  Min
  Count
  Percentile(Int)
}

pub type Query {
  Query(
    aggregator: Aggregator,
    metric: String,
    scope: String,
    grouping: List(String),
    functions: List(String),
  )
}

/// Convenience constructor with sensible defaults: empty grouping and no
/// postfix functions. `scope` may be `""` to emit the empty `{}` scope or
/// `filter.wildcard_all` to emit `{*}`.
pub fn new(aggregator: Aggregator, metric: String, scope: String) -> Query {
  Query(aggregator, metric, scope, [], [])
}

/// Returns a copy of `query` with `grouping` set.
pub fn by(query: Query, grouping: List(String)) -> Query {
  Query(..query, grouping: grouping)
}

/// Appends a postfix function (already-rendered) to the chain.
pub fn with_function(query: Query, function: String) -> Query {
  Query(..query, functions: list.append(query.functions, [function]))
}

pub fn to_string(query: Query) -> String {
  let prefix = aggregator_to_string(query.aggregator) <> ":"
  let body = query.metric <> "{" <> query.scope <> "}"
  let by_clause = case query.grouping {
    [] -> ""
    _ -> " by {" <> string.join(query.grouping, ",") <> "}"
  }
  let func_chain = case query.functions {
    [] -> ""
    fs -> "." <> string.join(fs, ".")
  }
  prefix <> body <> by_clause <> func_chain
}

pub fn aggregator_to_string(aggregator: Aggregator) -> String {
  case aggregator {
    Sum -> "sum"
    Avg -> "avg"
    Max -> "max"
    Min -> "min"
    Count -> "count"
    Percentile(n) -> "p" <> int.to_string(n)
  }
}
