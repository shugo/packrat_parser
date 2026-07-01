# packrat_parser

A small [packrat](https://bford.info/packrat/) / PEG parser-combinator library
with a Scala-inspired, monadic API. Grammar rules are plain methods that return
parsers, and they can be written with the `for ... then` comprehension so the
grammar reads like a Scala for-comprehension.

```ruby
require "packrat_parser"

class SimpleCalcParser < PackratParser
  def additive
    (for x in multitive, _ in term("+"), y in additive then x + y end) |
      (for x in multitive, _ in term("-"), y in additive then x - y end) |
      multitive
  end

  def multitive
    (for x in primary, _ in term("*"), y in multitive then x * y end) |
      (for x in primary, _ in term("/"), y in multitive then x / y end) |
      primary
  end

  def primary
    (for _l in term("("), x in additive, _r in term(")") then x end) |
      number
  end

  def number
    for s in term(/\d+/) then s.to_i end
  end
end

SimpleCalcParser.parse("1+2*3")   # => 7
SimpleCalcParser.parse("(1+2)*3") # => 9
```

## Requirements

The `for ... then` comprehension is a feature of a Ruby fork and is only
recognized by its **legacy parser**. Run grammars with `--parser=parse.y`:

```sh
ruby --parser=parse.y -Ilib examples/simple_calc.rb
```

The default Prism parser rejects `for ... then`. The library itself
(`lib/`) is ordinary Ruby — only files that *write* grammars need the flag.

## API

Subclass `PackratParser`. **Every public method you define in the subclass is a
grammar rule** and must return a parser; rule methods are automatically made lazy
and memoized so they can reference one another (and themselves) recursively.

**Private methods are left as ordinary helpers** (not rules), so you can factor
out plain Ruby logic. Use the `private` section form (`private` on its own line,
then the defs); `private def foo` is not detected, because the method is still
public when it is defined.

### Building blocks (available inside rule methods)

- `term(string)` — match an exact literal at the current position.
- `term(regexp)` — match a regexp anchored at the current position.
  Both yield the matched substring (e.g. `term(/\d+/)`).
- `pure(value)` — succeed with `value` without consuming input.

### Combinators (methods on every parser)

- `flat_map { |v| parser }` — sequence: run `parser` after this one succeeds.
- `map { |v| new_value }` — transform the result.
- `filter { |v| bool }` — succeed only when the predicate holds.
- `a | b` — ordered choice: try `a`, and if it fails try `b`.
- `a * b` — sequence, keep **both** results (Scala's `~`): run `a` then `b`,
  yield the pair `[a, b]`. `*` reads as a product: the result is the product of
  the two values, just as `|` (choice) is the algebraic sum. Left-associative and
  nesting, so `a * b * c` yields `[[a, b], c]`; Ruby's block-parameter
  destructuring takes them apart the way Scala's `case a ~ b ~ c` does:
  `(a * b * c).map { |(x, y), z| ... }`.
- `a << b` — sequence, keep the **left** result (Scala's `<~`): run `a` then
  `b`, yield `a`'s value and discard `b`'s.
- `a >> b` — sequence, keep the **right** result (Scala's `~>`): run `a` then
  `b`, yield `b`'s value and discard `a`'s.
- `p.rep` — zero or more (Scala's `rep`): yields an array of results (empty when
  there are no matches). Always succeeds.
- `p.rep1` — one or more (Scala's `rep1`): like `rep` but fails unless `p`
  matches at least once; yields a non-empty array.
- `p.opt` — optional (Scala's `opt`): yields `p`'s value, or `nil` (consuming
  nothing) when `p` does not match.

The arrow direction is a useful mnemonic: `<<`/`>>` keeps whichever side it
points to. They are handy for discarding punctuation, e.g. `( expr )` is
`term("(") >> expr << term(")")`. Ruby's precedence (`*` over `<<`/`>>` over
`|`) means sequencing binds tighter than ordered choice, as you'd want.

`flat_map`, `map`, and `filter` are exactly what the `for ... then`
comprehension desugars to (a non-final generator → `flat_map`, the final
generator → `map`, a `when` guard → `filter`), so:

```ruby
for x in p, y in q when y > 0 then x + y end
# == p.flat_map { |x| q.filter { |y| y > 0 }.map { |y| x + y } }
```

### Whitespace skipping (optional)

By default `term` matches exactly. To skip whitespace implicitly — like Scala's
`RegexParsers` — declare `skip_whitespace` at the class level. Each `term` then
consumes leading whitespace before matching, and `parse` consumes trailing
whitespace before requiring full input consumption:

```ruby
class CalcParser < PackratParser
  skip_whitespace            # default pattern: /\s+/
  # skip_whitespace(/[ \t]+/)  # or a custom pattern (e.g. spaces/tabs only)
  # ... rules using term(...) ...
end

CalcParser.parse("  1 + 2 * 3  ")  # => 7
```

The setting is inherited by subclasses, so a base parser can enable it once.

### Entry point

- `start_symbol :name` (class level) — choose the rule to start from.
  If omitted, the first defined method is used as the start symbol.
- `Klass.parse(input)` / `Klass.new.parse(input)` — parse, returning the value.
  Raises `PackratParser::ParseError` on failure or leftover input.
- Parse from any rule, not just the start symbol:
  `Klass.new.number.parse("123")` (call `parse` on the rule) or
  `Klass.new.parse("123", :number)` (pass the start rule). Both apply the same
  full-consumption check and whitespace handling.

## Notes / limitations

- **Classic packrat: no left recursion.** Write rules right-recursively. A
  consequence is that `-` and `/` in the example calculator associate to the
  right (`12/4/3` parses as `12/(4/3)` == `12`).
- **No implicit whitespace by default.** `term` matches exactly. Enable implicit
  whitespace skipping with `skip_whitespace` (see above) when your grammar needs
  it.
- **Byte-oriented positions.** The parser tracks byte offsets and matches with
  `byteslice` / `byteindex`, so it stays efficient on UTF-8 input (indexing a
  multibyte string by character is O(n)). Positions are byte offsets throughout,
  including the `pos` reported on a raised `ParseError`.

## Running the tests

```sh
rake            # or: rake test
# or directly:
bin/test
# or:
ruby --parser=parse.y -Ilib test/test_packrat_parser.rb
```

The `rake test` task runs the suite under `--parser=parse.y` for you (the test
grammars need the fork's legacy parser).
