# datadog_query

Primitives for emitting and linting Datadog query syntax in Gleam.

```sh
gleam add datadog_query
```

```gleam
import datadog_query/filter
import datadog_query/lint
import datadog_query/quote

quote.value("my service")                      // "\"my service\""
filter.tag("env", "prod")                      // "env:prod"
filter.tag_in("env", ["prod", "staging"])      // "env IN (prod, staging)"
lint.at_prefixed_attrs("sum:m{@type:foo}")     // ["@type"]
```
