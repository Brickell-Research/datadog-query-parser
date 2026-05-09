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
