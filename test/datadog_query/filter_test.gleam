import datadog_query/filter
import test_helpers

// ==== tag ====
pub fn tag_test() {
  [
    #("plain value", "env", "production", "env:production"),
    #(
      "value with embedded colons stays unquoted",
      "rails.controller",
      "api::v0::elevenlabscontroller",
      "rails.controller:api::v0::elevenlabscontroller",
    ),
    #(
      "value with whitespace gets quoted",
      "service.name",
      "my service",
      "service.name:\"my service\"",
    ),
    #("value with comma gets quoted", "url.path", "a,b", "url.path:\"a,b\""),
    #("value with parens gets quoted", "expr", "f(x)", "expr:\"f(x)\""),
    #("wildcard preserved", "service.name", "prefix*", "service.name:prefix*"),
    #("bare wildcard preserved", "service.name", "*", "service.name:*"),
    #(
      "wildcard + colon preserved",
      "rails.controller",
      "api::v*",
      "rails.controller:api::v*",
    ),
    #(
      "embedded double quote gets escaped",
      "msg",
      "he said \"hi\"",
      "msg:\"he said \\\"hi\\\"\"",
    ),
  ]
  |> test_helpers.table_test_2(filter.tag)
}

// ==== negated_tag ====
pub fn negated_tag_test() {
  [
    #("plain value", "env", "staging", "!env:staging"),
    #(
      "value with embedded colons stays unquoted",
      "rails.controller",
      "api::v0::ctrl",
      "!rails.controller:api::v0::ctrl",
    ),
    #(
      "value with whitespace gets quoted",
      "service.name",
      "my service",
      "!service.name:\"my service\"",
    ),
    #("wildcard preserved", "service.name", "prefix*", "!service.name:prefix*"),
  ]
  |> test_helpers.table_test_2(filter.negated_tag)
}

// ==== tag_in ====
pub fn tag_in_test() {
  [
    #(
      "plain values",
      "env",
      ["prod", "staging", "dev"],
      "env IN (prod, staging, dev)",
    ),
    #("empty list returns empty string", "env", [], ""),
    #(
      "elements with colons stay unquoted",
      "rails.controller",
      ["api::v0::ctrl", "api::v1::ctrl"],
      "rails.controller IN (api::v0::ctrl, api::v1::ctrl)",
    ),
    #(
      "mixed quoted and bare elements",
      "env",
      ["prod", "us east"],
      "env IN (prod, \"us east\")",
    ),
    #(
      "wildcard elements preserved",
      "service.name",
      ["payments-*", "billing-api"],
      "service.name IN (payments-*, billing-api)",
    ),
    #(
      "bare wildcard element preserved",
      "service.name",
      ["foo", "*"],
      "service.name IN (foo, *)",
    ),
    #(
      "wildcard + colon element preserved",
      "rails.controller",
      ["api::v0::*", "api::v1::ctrl"],
      "rails.controller IN (api::v0::*, api::v1::ctrl)",
    ),
    #(
      "list mixing plain, colon-bearing, and whitespace elements",
      "rails.controller",
      ["plain", "api::v0::ctrl", "name with space"],
      "rails.controller IN (plain, api::v0::ctrl, \"name with space\")",
    ),
  ]
  |> test_helpers.table_test_2(filter.tag_in)
}

// ==== tag_not_in ====
pub fn tag_not_in_test() {
  [
    #("plain values", "env", ["prod", "staging"], "env NOT IN (prod, staging)"),
    #("empty list returns empty string", "env", [], ""),
    #(
      "elements with colons stay unquoted",
      "path",
      ["a:b", "c:d"],
      "path NOT IN (a:b, c:d)",
    ),
    #(
      "suffix-wildcard element preserved",
      "service.name",
      ["*-canary", "concrete"],
      "service.name NOT IN (*-canary, concrete)",
    ),
  ]
  |> test_helpers.table_test_2(filter.tag_not_in)
}

// ==== numeric comparisons ====
pub fn tag_gt_test() {
  [
    #("integer-valued float", "@duration", 1000.0, "@duration:>1000.0"),
    #("fractional", "@p95", 0.95, "@p95:>0.95"),
  ]
  |> test_helpers.table_test_2(filter.tag_gt)
}

pub fn tag_gte_test() {
  [#("threshold", "@http.status_code", 500.0, "@http.status_code:>=500.0")]
  |> test_helpers.table_test_2(filter.tag_gte)
}

pub fn tag_lt_test() {
  [#("threshold", "@latency", 50.0, "@latency:<50.0")]
  |> test_helpers.table_test_2(filter.tag_lt)
}

pub fn tag_lte_test() {
  [#("threshold", "@latency", 50.0, "@latency:<=50.0")]
  |> test_helpers.table_test_2(filter.tag_lte)
}

pub fn tag_gt_int_test() {
  [#("integer threshold", "@status", 500, "@status:>500")]
  |> test_helpers.table_test_2(filter.tag_gt_int)
}

pub fn tag_gte_int_test() {
  [#("integer threshold", "@status", 500, "@status:>=500")]
  |> test_helpers.table_test_2(filter.tag_gte_int)
}

pub fn tag_lt_int_test() {
  [#("integer threshold", "@status", 500, "@status:<500")]
  |> test_helpers.table_test_2(filter.tag_lt_int)
}

pub fn tag_lte_int_test() {
  [#("integer threshold", "@status", 500, "@status:<=500")]
  |> test_helpers.table_test_2(filter.tag_lte_int)
}

// ==== tag_regex ====
pub fn tag_regex_test() {
  [
    #("plain pattern", "service.name", "payments-.*", "service.name:~payments-.*"),
    #(
      "pattern with whitespace gets quoted",
      "msg",
      "foo bar",
      "msg:~\"foo bar\"",
    ),
  ]
  |> test_helpers.table_test_2(filter.tag_regex)
}

// ==== all_of ====
pub fn all_of_test() {
  [
    #("empty list returns empty", [], ""),
    #("single passes through", ["env:prod"], "env:prod"),
    #("two joined with AND", ["env:prod", "service:api"], "env:prod AND service:api"),
    #(
      "three joined left-to-right",
      ["env:prod", "service:api", "tier:web"],
      "env:prod AND service:api AND tier:web",
    ),
    #(
      "empty fragments dropped (handles tag_in([]) artifact)",
      ["env:prod", "", "service:api"],
      "env:prod AND service:api",
    ),
    #("all-empty list returns empty", ["", "", ""], ""),
  ]
  |> test_helpers.table_test_1(filter.all_of)
}

// ==== any_of ====
pub fn any_of_test() {
  [
    #("empty list returns empty", [], ""),
    #("single passes through", ["env:prod"], "env:prod"),
    #("two joined with OR", ["env:prod", "env:staging"], "env:prod OR env:staging"),
    #(
      "empty fragments dropped",
      ["env:prod", "", "env:staging"],
      "env:prod OR env:staging",
    ),
  ]
  |> test_helpers.table_test_1(filter.any_of)
}

// ==== not_ ====
pub fn not_test() {
  [
    #("wraps simple filter in NOT (...)", "env:prod", "NOT (env:prod)"),
    #(
      "wraps composed filter",
      "env:prod AND service:api",
      "NOT (env:prod AND service:api)",
    ),
    #("empty input returns empty", "", ""),
  ]
  |> test_helpers.table_test_1(filter.not_)
}

// ==== group ====
pub fn group_test() {
  [
    #("wraps in parens", "env:prod", "(env:prod)"),
    #("nested composition", "env:prod OR env:staging", "(env:prod OR env:staging)"),
    #("empty input returns empty", "", ""),
  ]
  |> test_helpers.table_test_1(filter.group)
}
