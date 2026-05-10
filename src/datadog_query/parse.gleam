/// Recursive-descent parser for Datadog scope-filter expressions.
///
/// Accepts the contents of a `{...}` scope and returns an `ast.Filter`.
/// Grammar (closely modelled on ddqp's MetricFilter):
///
///   filter      := disjunction
///   disjunction := conjunction (OR conjunction)*
///   conjunction := primary (AND primary)*
///   primary     := NOT primary | "(" filter ")" | simple | "*"
///   simple      := "!"? ident sep value_or_list
///   sep         := ":" | ":>" | ":<" | ":>=" | ":<=" | ":~" | "IN" | "NOT" "IN"
///   value_or_list := "(" value ("," value)* ")" | value
///   value       := quoted_string | bare_token
///
/// The wildcard `*` is parsed as `Wildcard` only when it stands alone (it
/// remains valid inside values like `service:foo-*`, where the lexer
/// greedy-consumes it as part of the bare value).
import datadog_query/ast.{
  type ComparisonOp, type Filter, And, Gt, Gte, Lt, Lte, NegatedTag, Not, Or,
  Tag, TagComparison, TagIn, TagNotIn, TagRegex, Wildcard,
}
import gleam/list
import gleam/result
import gleam/string

pub type ParseError {
  UnexpectedEnd
  Unexpected(String)
  EmptyInput
}

pub fn filter(input: String) -> Result(Filter, ParseError) {
  let chars = string.to_graphemes(input)
  let chars = skip_whitespace(chars)
  case chars {
    [] -> Error(EmptyInput)
    _ -> {
      use #(parsed, rest) <- result.try(parse_or(chars))
      case skip_whitespace(rest) {
        [] -> Ok(parsed)
        leftover -> Error(Unexpected(string.concat(leftover)))
      }
    }
  }
}

// ---- Boolean layers ----

fn parse_or(chars: List(String)) -> Result(#(Filter, List(String)), ParseError) {
  use #(first, rest) <- result.try(parse_and(chars))
  collect_or([first], rest)
}

fn collect_or(
  acc: List(Filter),
  chars: List(String),
) -> Result(#(Filter, List(String)), ParseError) {
  let chars = skip_whitespace(chars)
  case match_keyword(chars, "OR") {
    Ok(rest) -> {
      use #(next, rest) <- result.try(parse_and(skip_whitespace(rest)))
      collect_or([next, ..acc], rest)
    }
    Error(_) ->
      case acc {
        [single] -> Ok(#(single, chars))
        many -> Ok(#(Or(list.reverse(many)), chars))
      }
  }
}

fn parse_and(chars: List(String)) -> Result(#(Filter, List(String)), ParseError) {
  use #(first, rest) <- result.try(parse_primary(chars))
  collect_and([first], rest)
}

fn collect_and(
  acc: List(Filter),
  chars: List(String),
) -> Result(#(Filter, List(String)), ParseError) {
  let chars = skip_whitespace(chars)
  case match_keyword(chars, "AND") {
    Ok(rest) -> {
      use #(next, rest) <- result.try(parse_primary(skip_whitespace(rest)))
      collect_and([next, ..acc], rest)
    }
    Error(_) ->
      case acc {
        [single] -> Ok(#(single, chars))
        many -> Ok(#(And(list.reverse(many)), chars))
      }
  }
}

fn parse_primary(
  chars: List(String),
) -> Result(#(Filter, List(String)), ParseError) {
  let chars = skip_whitespace(chars)
  case match_keyword(chars, "NOT") {
    Ok(rest) -> {
      // Distinguish unary `NOT <expr>` from `NOT IN` separator. The latter
      // belongs to a simple-filter and shouldn't be consumed here. We peek
      // ahead: if `IN` follows, this `NOT` is part of a separator —
      // bail and let parse_simple_filter handle it.
      let after_ws = skip_whitespace(rest)
      case match_keyword(after_ws, "IN") {
        Ok(_) -> parse_atom(chars)
        Error(_) -> {
          use #(inner, rest) <- result.try(parse_primary(after_ws))
          Ok(#(Not(inner), rest))
        }
      }
    }
    Error(_) -> parse_atom(chars)
  }
}

fn parse_atom(chars: List(String)) -> Result(#(Filter, List(String)), ParseError) {
  case chars {
    ["(", ..rest] -> {
      use #(inner, rest) <- result.try(parse_or(skip_whitespace(rest)))
      let rest = skip_whitespace(rest)
      case rest {
        [")", ..tail] -> Ok(#(inner, tail))
        [] -> Error(UnexpectedEnd)
        [c, ..] -> Error(Unexpected(c))
      }
    }
    _ -> parse_simple_or_wildcard(chars)
  }
}

// ---- Simple filter / wildcard ----

fn parse_simple_or_wildcard(
  chars: List(String),
) -> Result(#(Filter, List(String)), ParseError) {
  // Standalone `*`: the only filter content. Recognised only when followed
  // by end-of-input, whitespace, or boolean keyword boundary.
  case chars {
    ["*", ..rest] ->
      case is_filter_terminator(skip_whitespace(rest)) {
        True -> Ok(#(Wildcard, rest))
        False -> parse_simple_filter(chars)
      }
    _ -> parse_simple_filter(chars)
  }
}

fn is_filter_terminator(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    [")", ..] -> True
    _ ->
      case match_keyword(chars, "AND") {
        Ok(_) -> True
        Error(_) ->
          case match_keyword(chars, "OR") {
            Ok(_) -> True
            Error(_) -> False
          }
      }
  }
}

fn parse_simple_filter(
  chars: List(String),
) -> Result(#(Filter, List(String)), ParseError) {
  let #(negated, chars) = case chars {
    ["!", ..rest] -> #(True, rest)
    _ -> #(False, chars)
  }

  use #(name, rest) <- result.try(parse_ident(chars))
  let rest_ws = skip_whitespace(rest)

  case parse_separator(rest, rest_ws) {
    Ok(#(SepColon, after)) -> {
      use #(value, after) <- result.try(parse_value(after))
      case negated {
        True -> Ok(#(NegatedTag(name, value), after))
        False -> Ok(#(Tag(name, value), after))
      }
    }
    Ok(#(SepCompare(op), after)) -> {
      use #(value, after) <- result.try(parse_value(after))
      let node = TagComparison(name, op, value)
      case negated {
        True -> Ok(#(Not(node), after))
        False -> Ok(#(node, after))
      }
    }
    Ok(#(SepRegex, after)) -> {
      use #(value, after) <- result.try(parse_value(after))
      let node = TagRegex(name, value)
      case negated {
        True -> Ok(#(Not(node), after))
        False -> Ok(#(node, after))
      }
    }
    Ok(#(SepIn, after)) -> {
      use #(values, after) <- result.try(parse_value_list(after))
      let node = TagIn(name, values)
      case negated {
        True -> Ok(#(Not(node), after))
        False -> Ok(#(node, after))
      }
    }
    Ok(#(SepNotIn, after)) -> {
      use #(values, after) <- result.try(parse_value_list(after))
      let node = TagNotIn(name, values)
      case negated {
        True -> Ok(#(Not(node), after))
        False -> Ok(#(node, after))
      }
    }
    Error(e) -> Error(e)
  }
}

type Separator {
  SepColon
  SepCompare(ComparisonOp)
  SepRegex
  SepIn
  SepNotIn
}

/// Looks for a separator immediately after the tag name (`tight`, no space)
/// or after intervening whitespace (`loose`, for `IN`/`NOT IN`).
fn parse_separator(
  tight: List(String),
  loose: List(String),
) -> Result(#(Separator, List(String)), ParseError) {
  case tight {
    [":", ">", "=", ..rest] -> Ok(#(SepCompare(Gte), rest))
    [":", "<", "=", ..rest] -> Ok(#(SepCompare(Lte), rest))
    [":", ">", ..rest] -> Ok(#(SepCompare(Gt), rest))
    [":", "<", ..rest] -> Ok(#(SepCompare(Lt), rest))
    [":", "~", ..rest] -> Ok(#(SepRegex, rest))
    [":", ..rest] -> Ok(#(SepColon, rest))
    _ ->
      case match_keyword(loose, "NOT") {
        Ok(after_not) -> {
          let after_not_ws = skip_whitespace(after_not)
          case match_keyword(after_not_ws, "IN") {
            Ok(rest) -> Ok(#(SepNotIn, skip_whitespace(rest)))
            Error(_) -> Error(Unexpected("NOT without IN after tag name"))
          }
        }
        Error(_) ->
          case match_keyword(loose, "IN") {
            Ok(rest) -> Ok(#(SepIn, skip_whitespace(rest)))
            Error(_) ->
              case loose {
                [] -> Error(UnexpectedEnd)
                [c, ..] -> Error(Unexpected(c))
              }
          }
      }
  }
}

// ---- Identifier and value lexing ----

fn parse_ident(
  chars: List(String),
) -> Result(#(String, List(String)), ParseError) {
  case take_while(chars, is_ident_char) {
    #([], _) ->
      case chars {
        [] -> Error(UnexpectedEnd)
        [c, ..] -> Error(Unexpected(c))
      }
    #(taken, rest) -> Ok(#(string.concat(taken), rest))
  }
}

fn is_ident_char(c: String) -> Bool {
  // Tag names: letters, digits, `_`, `.`, `-`, `@`. No `:` (separator) or
  // structural punctuation. Mirrors the practical subset of Datadog facets.
  case c {
    "." | "_" | "-" | "@" -> True
    _ -> is_alnum(c)
  }
}

fn parse_value(
  chars: List(String),
) -> Result(#(String, List(String)), ParseError) {
  case chars {
    ["\"", ..rest] -> parse_quoted(rest, [])
    _ ->
      case take_while(chars, is_bare_value_char) {
        #([], _) ->
          case chars {
            [] -> Error(UnexpectedEnd)
            [c, ..] -> Error(Unexpected(c))
          }
        #(taken, rest) -> Ok(#(string.concat(taken), rest))
      }
  }
}

fn is_bare_value_char(c: String) -> Bool {
  // Bare values stop at structural delimiters or whitespace; everything
  // else (including `:`, `*`, `/`, `.`) is part of the value.
  case c {
    " " | "\t" | "\n" | "\r" | "," | "(" | ")" | "}" -> False
    _ -> True
  }
}

fn parse_quoted(
  chars: List(String),
  acc: List(String),
) -> Result(#(String, List(String)), ParseError) {
  case chars {
    [] -> Error(UnexpectedEnd)
    ["\\", "\"", ..rest] -> parse_quoted(rest, ["\"", ..acc])
    ["\\", c, ..rest] -> parse_quoted(rest, [c, "\\", ..acc])
    ["\"", ..rest] -> Ok(#(string.concat(list.reverse(acc)), rest))
    [c, ..rest] -> parse_quoted(rest, [c, ..acc])
  }
}

fn parse_value_list(
  chars: List(String),
) -> Result(#(List(String), List(String)), ParseError) {
  let chars = skip_whitespace(chars)
  case chars {
    ["(", ..rest] -> collect_values([], skip_whitespace(rest))
    [] -> Error(UnexpectedEnd)
    [c, ..] -> Error(Unexpected(c))
  }
}

fn collect_values(
  acc: List(String),
  chars: List(String),
) -> Result(#(List(String), List(String)), ParseError) {
  case chars {
    [")", ..rest] -> Ok(#(list.reverse(acc), rest))
    _ -> {
      use #(value, rest) <- result.try(parse_value(chars))
      let rest = skip_whitespace(rest)
      case rest {
        [",", ..tail] -> collect_values([value, ..acc], skip_whitespace(tail))
        [")", ..tail] -> Ok(#(list.reverse([value, ..acc]), tail))
        [] -> Error(UnexpectedEnd)
        [c, ..] -> Error(Unexpected(c))
      }
    }
  }
}

// ---- Helpers ----

fn skip_whitespace(chars: List(String)) -> List(String) {
  case chars {
    [" ", ..rest] | ["\t", ..rest] | ["\n", ..rest] | ["\r", ..rest] ->
      skip_whitespace(rest)
    _ -> chars
  }
}

/// Consumes `keyword` from `chars` only if (a) it appears verbatim AND
/// (b) the character immediately after isn't an ident continuation
/// (so `OR` matches but `ORder` does not).
fn match_keyword(
  chars: List(String),
  keyword: String,
) -> Result(List(String), Nil) {
  let kw_chars = string.to_graphemes(keyword)
  case strip_prefix(chars, kw_chars) {
    Ok(rest) ->
      case rest {
        [] -> Ok(rest)
        [c, ..] ->
          case is_ident_char(c) {
            True -> Error(Nil)
            False -> Ok(rest)
          }
      }
    Error(_) -> Error(Nil)
  }
}

fn strip_prefix(
  chars: List(String),
  prefix: List(String),
) -> Result(List(String), Nil) {
  case prefix, chars {
    [], _ -> Ok(chars)
    [_, ..], [] -> Error(Nil)
    [p, ..ps], [c, ..cs] ->
      case p == c {
        True -> strip_prefix(cs, ps)
        False -> Error(Nil)
      }
  }
}

fn take_while(
  chars: List(String),
  pred: fn(String) -> Bool,
) -> #(List(String), List(String)) {
  do_take_while(chars, pred, [])
}

fn do_take_while(
  chars: List(String),
  pred: fn(String) -> Bool,
  acc: List(String),
) -> #(List(String), List(String)) {
  case chars {
    [c, ..rest] ->
      case pred(c) {
        True -> do_take_while(rest, pred, [c, ..acc])
        False -> #(list.reverse(acc), chars)
      }
    [] -> #(list.reverse(acc), chars)
  }
}

fn is_alnum(c: String) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" -> True
    "k" | "l" | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t" -> True
    "u" | "v" | "w" | "x" | "y" | "z" -> True
    "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" -> True
    "K" | "L" | "M" | "N" | "O" | "P" | "Q" | "R" | "S" | "T" -> True
    "U" | "V" | "W" | "X" | "Y" | "Z" -> True
    _ -> False
  }
}
