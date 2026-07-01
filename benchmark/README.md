# Benchmark: packrat_parser vs racc vs parslet

Three implementations of the **same four-function integer calculator**
(lexing + parsing + evaluation to an `Integer`), timed on the same VM:

- `../examples/simple_calc.rb` — packrat_parser (this gem)
- `calc.y` / `calc_racc.rb` — [racc](https://github.com/ruby/racc) LALR parser
- `calc_parslet.rb` — [parslet](https://kschiess.github.io/parslet/) PEG combinators

## Running

```sh
rake bench
# or:
ruby --parser=parse.y benchmark/bench.rb
```

`--parser=parse.y` is required because the packrat_parser grammar uses the
fork's `for ... then` comprehension. Prerequisites:

- `gem install parslet`
- `racc -o benchmark/calc_racc.rb benchmark/calc.y` to (re)generate the racc
  parser (`rake bench` does this for you). The generated file is checked in so
  the benchmark also runs without racc installed.

## What it measures

Expressions of `n` terms of the form `a*b` joined with `+` (e.g. `2*2+3*3+…`).
Using only `+` and `*` keeps the value independent of associativity, so all
three grammars agree even though packrat_parser and parslet are right-recursive
while racc is left-recursive. The harness asserts agreement before timing.

## Representative results

Fork dev build (Ruby 4.1.0dev), 2000 iterations, lexing + parse + eval:

| input       | racc   | packrat_parser | parslet |
|-------------|--------|----------------|---------|
| 10 terms    | 0.06s  | 0.33s          | 1.32s   |
| 50 terms    | 0.28s  | 2.23s          | 6.23s   |
| 200 terms   | 1.18s  | 6.37s          | 26.3s   |

Relative (200 terms, racc = 1.0): **racc 1.0× · packrat_parser ~5.4× · parslet ~22×**.

Scaling from 10→200 terms (20× the input) grows the time ~20× for all three:
each is **linear** on this grammar. packrat_parser stays linear thanks to
memoization; parslet is linear here but does not memoize, so backtracking-heavy
grammars can degrade. The gap is a constant factor:

- **racc** is fastest — an offline-compiled LALR table plus a trivial regex
  lexer, with minimal per-parse allocation.
- **packrat_parser** is a pure-Ruby runtime DSL: it allocates a `Success`/
  `Failure` per terminal and a memo hash per parse, though the combinator graph
  itself is built once and cached.
- **parslet** is slowest — it builds an intermediate parse tree (nested hashes)
  and then walks it with a `Transform`, a two-pass, allocation-heavy design.

Absolute numbers depend on the VM (this is an unoptimized dev build); the
relative ordering — **racc ≫ packrat_parser > parslet** — is the takeaway.
