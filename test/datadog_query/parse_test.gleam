import datadog_query/ast.{
  And, Gt, Gte, Lt, Lte, NegatedTag, Not, Or, Tag, TagComparison, TagIn,
  TagNotIn, TagRegex, Wildcard,
}
import datadog_query/parse
import test_helpers

// ==== parse: shape ====
pub fn shape_test() {
  [
    #("plain tag", "env:prod", Ok(Tag("env", "prod"))),
    #(
      "tag with embedded colons",
      "rails.controller:api::v0::ctrl",
      Ok(Tag("rails.controller", "api::v0::ctrl")),
    ),
    #("tag with wildcard", "service:foo*", Ok(Tag("service", "foo*"))),
    #("@-prefixed tag name", "@type:success", Ok(Tag("@type", "success"))),
    #("negated tag", "!env:prod", Ok(NegatedTag("env", "prod"))),
    #("quoted value", "msg:\"hello world\"", Ok(Tag("msg", "hello world"))),
    #(
      "quoted value with escaped quote",
      "msg:\"he said \\\"hi\\\"\"",
      Ok(Tag("msg", "he said \"hi\"")),
    ),
    #(
      "comparison gt",
      "@duration:>100",
      Ok(TagComparison("@duration", Gt, "100")),
    ),
    #(
      "comparison gte",
      "@status:>=500",
      Ok(TagComparison("@status", Gte, "500")),
    ),
    #(
      "comparison lt with float",
      "@p95:<0.5",
      Ok(TagComparison("@p95", Lt, "0.5")),
    ),
    #(
      "comparison lte",
      "@latency:<=50",
      Ok(TagComparison("@latency", Lte, "50")),
    ),
    #(
      "regex match",
      "service:~payments-.*",
      Ok(TagRegex("service", "payments-.*")),
    ),
    #("IN list", "env IN (prod, staging)", Ok(TagIn("env", ["prod", "staging"]))),
    #(
      "NOT IN list",
      "env NOT IN (dev, test)",
      Ok(TagNotIn("env", ["dev", "test"])),
    ),
    #(
      "IN list with quoted element",
      "env IN (prod, \"us east\")",
      Ok(TagIn("env", ["prod", "us east"])),
    ),
    #("wildcard scope", "*", Ok(Wildcard)),
    #(
      "AND composition",
      "env:prod AND service:api",
      Ok(And([Tag("env", "prod"), Tag("service", "api")])),
    ),
    #(
      "OR composition",
      "env:prod OR env:staging",
      Ok(Or([Tag("env", "prod"), Tag("env", "staging")])),
    ),
    #(
      "AND has higher precedence than OR",
      "a:1 OR b:2 AND c:3",
      Ok(Or([Tag("a", "1"), And([Tag("b", "2"), Tag("c", "3")])])),
    ),
    #(
      "parens override precedence",
      "(a:1 OR b:2) AND c:3",
      Ok(And([Or([Tag("a", "1"), Tag("b", "2")]), Tag("c", "3")])),
    ),
    #("NOT prefix", "NOT env:prod", Ok(Not(Tag("env", "prod")))),
    #(
      "NOT over composed",
      "NOT (env:prod OR env:staging)",
      Ok(Not(Or([Tag("env", "prod"), Tag("env", "staging")]))),
    ),
  ]
  |> test_helpers.table_test_1(parse.filter)
}

// ==== round-trip: parse then ast.to_string returns canonical form ====
pub fn round_trip_test() {
  [
    #("plain tag", "env:prod", "env:prod"),
    #("tag with whitespace value gets quoted", "msg:\"hello world\"", "msg:\"hello world\""),
    #("colon-bearing value preserved bare", "rails.controller:api::v0::ctrl", "rails.controller:api::v0::ctrl"),
    #("wildcard preserved", "service:foo*", "service:foo*"),
    #("negation", "!env:prod", "!env:prod"),
    #("comparison", "@duration:>100", "@duration:>100"),
    #("regex", "service:~payments-.*", "service:~payments-.*"),
    #(
      "IN list canonical spacing",
      "env IN (prod,staging)",
      "env IN (prod, staging)",
    ),
    #("NOT IN", "env NOT IN (dev, test)", "env NOT IN (dev, test)"),
    #("AND chain", "a:1 AND b:2 AND c:3", "a:1 AND b:2 AND c:3"),
    #(
      "precedence preserved when re-rendered (AND inside OR)",
      "a:1 OR b:2 AND c:3",
      "a:1 OR b:2 AND c:3",
    ),
    #(
      "explicit grouping preserved with parens",
      "(a:1 OR b:2) AND c:3",
      "(a:1 OR b:2) AND c:3",
    ),
    #("wildcard", "*", "*"),
    #("NOT", "NOT env:prod", "NOT env:prod"),
  ]
  |> test_helpers.table_test_1(fn(input) {
    case parse.filter(input) {
      Ok(node) -> ast.to_string(node)
      Error(e) -> "<error: " <> debug_error(e) <> ">"
    }
  })
}

fn debug_error(e: parse.ParseError) -> String {
  case e {
    parse.UnexpectedEnd -> "UnexpectedEnd"
    parse.Unexpected(c) -> "Unexpected(" <> c <> ")"
    parse.EmptyInput -> "EmptyInput"
  }
}

// ==== error cases ====
pub fn error_test() {
  case parse.filter("") {
    Error(parse.EmptyInput) -> Nil
    _ -> panic as "empty input should error"
  }
  case parse.filter("env:") {
    Error(parse.UnexpectedEnd) -> Nil
    _ -> panic as "missing value should error"
  }
  case parse.filter("env:prod AND") {
    Error(_) -> Nil
    Ok(_) -> panic as "trailing AND should error"
  }
  case parse.filter("(env:prod") {
    Error(_) -> Nil
    Ok(_) -> panic as "unclosed paren should error"
  }
}
