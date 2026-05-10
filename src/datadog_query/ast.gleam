/// AST for Datadog scope-filter expressions.
///
/// Covers what appears inside the `{...}` of a metric query: simple tag
/// filters, comparisons, regex matches, IN-lists, boolean composition,
/// negation, and the wildcard scope. The grammar mirrors `ddqp`'s
/// MetricFilter — see https://github.com/jonwinton/ddqp/blob/main/metricfilter.go
///
/// Nodes round-trip through `to_string`, which re-emits values via
/// `datadog_query/quote` so handwritten AST values are correctly quoted.
import datadog_query/quote
import gleam/list
import gleam/string

pub type ComparisonOp {
  Gt
  Gte
  Lt
  Lte
}

pub type Filter {
  Tag(name: String, value: String)
  NegatedTag(name: String, value: String)
  TagComparison(name: String, op: ComparisonOp, value: String)
  TagRegex(name: String, pattern: String)
  TagIn(name: String, values: List(String))
  TagNotIn(name: String, values: List(String))
  And(filters: List(Filter))
  Or(filters: List(Filter))
  Not(filter: Filter)
  Wildcard
}

pub fn to_string(filter: Filter) -> String {
  case filter {
    Tag(name, value) -> name <> ":" <> quote.value(value)
    NegatedTag(name, value) -> "!" <> name <> ":" <> quote.value(value)
    TagComparison(name, op, value) ->
      name <> ":" <> comparison_op_to_string(op) <> value
    TagRegex(name, pattern) -> name <> ":~" <> quote.value(pattern)
    TagIn(name, values) ->
      name
      <> " IN ("
      <> values |> list.map(quote.value) |> string.join(", ")
      <> ")"
    TagNotIn(name, values) ->
      name
      <> " NOT IN ("
      <> values |> list.map(quote.value) |> string.join(", ")
      <> ")"
    And(filters) -> render_binary(filters, " AND ", precedence_and())
    Or(filters) -> render_binary(filters, " OR ", precedence_or())
    Not(inner) -> "NOT " <> render_with_parens(inner, precedence_not())
    Wildcard -> "*"
  }
}

pub fn comparison_op_to_string(op: ComparisonOp) -> String {
  case op {
    Gt -> ">"
    Gte -> ">="
    Lt -> "<"
    Lte -> "<="
  }
}

/// Precedence levels used to decide when to parenthesize a child during
/// rendering. Higher = binds tighter. The numbers themselves don't matter
/// — only relative ordering.
fn precedence_or() -> Int {
  1
}

fn precedence_and() -> Int {
  2
}

fn precedence_not() -> Int {
  3
}

fn precedence_of(filter: Filter) -> Int {
  case filter {
    Or(_) -> precedence_or()
    And(_) -> precedence_and()
    Not(_) -> precedence_not()
    _ -> 4
  }
}

fn render_binary(filters: List(Filter), sep: String, parent_prec: Int) -> String {
  filters
  |> list.map(fn(f) { render_with_parens(f, parent_prec) })
  |> string.join(sep)
}

fn render_with_parens(filter: Filter, parent_prec: Int) -> String {
  case precedence_of(filter) < parent_prec {
    True -> "(" <> to_string(filter) <> ")"
    False -> to_string(filter)
  }
}
