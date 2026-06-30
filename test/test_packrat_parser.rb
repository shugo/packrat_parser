# Run with the Ruby fork's legacy parser:
#
#   /workspace/ruby/ruby --disable-gems --parser=parse.y -Ilib -Itest test/test_packrat_parser.rb
#
require "packrat_parser"
require "helper"

include TinyTest

# ---------------------------------------------------------------------------
# Terminals: literal strings and regexps, full vs partial consumption.
# ---------------------------------------------------------------------------
class LiteralParser < PackratParser
  start_symbol :greeting
  def greeting
    term("hi")
  end
end

assert_equal "hi", LiteralParser.parse("hi"), "literal match"
assert_raise(PackratParser::ParseError, "literal mismatch") { LiteralParser.parse("ho") }
assert_raise(PackratParser::ParseError, "trailing input") { LiteralParser.parse("hithere") }

class DigitsParser < PackratParser
  start_symbol :num
  def num
    for s in term(/\d+/) then s.to_i end
  end
end

assert_equal 1234, DigitsParser.parse("1234"), "regexp terminal"
assert_raise(PackratParser::ParseError, "regexp no match") { DigitsParser.parse("abc") }

# ---------------------------------------------------------------------------
# Monadic core: pure / map / flat_map / filter, both directly and via `for`.
# ---------------------------------------------------------------------------
class PureParser < PackratParser
  start_symbol :nothing
  def nothing
    pure(42)
  end
end
assert_equal 42, PureParser.parse(""), "pure consumes nothing"

class MapParser < PackratParser
  start_symbol :doubled
  def doubled
    term(/\d+/).map { |s| s.to_i * 2 }
  end
end
assert_equal 20, MapParser.parse("10"), "map transforms value"

class FlatMapParser < PackratParser
  start_symbol :pair
  def pair
    term(/\d/).flat_map { |a| term(/\d/).map { |b| [a.to_i, b.to_i] } }
  end
end
assert_equal [3, 7], FlatMapParser.parse("37"), "flat_map sequences"

class ForParser < PackratParser
  start_symbol :pair
  def pair
    for a in term(/\d/), _ in term(","), b in term(/\d/) then [a.to_i, b.to_i] end
  end
end
assert_equal [4, 9], ForParser.parse("4,9"), "for comprehension sequencing"

# `when` guard desugars to filter.
class GuardParser < PackratParser
  start_symbol :even
  def even
    for n in term(/\d+/) when n.to_i.even? then n.to_i end
  end
end
assert_equal 8, GuardParser.parse("8"), "when guard passes"
assert_raise(PackratParser::ParseError, "when guard fails") { GuardParser.parse("7") }

# filter directly.
class FilterParser < PackratParser
  start_symbol :small
  def small
    term(/\d+/).map { |s| s.to_i }.filter { |n| n < 100 }
  end
end
assert_equal 42, FilterParser.parse("42"), "filter passes"
assert_raise(PackratParser::ParseError, "filter fails") { FilterParser.parse("999") }

# ---------------------------------------------------------------------------
# Ordered choice.
# ---------------------------------------------------------------------------
class ChoiceParser < PackratParser
  start_symbol :ab
  def ab
    term("a") | term("b")
  end
end
assert_equal "a", ChoiceParser.parse("a"), "choice first alternative"
assert_equal "b", ChoiceParser.parse("b"), "choice second alternative"
assert_raise(PackratParser::ParseError, "choice both fail") { ChoiceParser.parse("c") }

# ---------------------------------------------------------------------------
# Sequencing operators: `<<` keeps the left result, `>>` keeps the right
# (Scala's `<~` / `~>`).
# ---------------------------------------------------------------------------
class KeepLeftParser < PackratParser
  start_symbol :num
  def num
    term(/\d+/).map { |s| s.to_i } << term(";")
  end
end
assert_equal 42, KeepLeftParser.parse("42;"), "<< keeps left result"
assert_raise(PackratParser::ParseError, "<< requires right to match") { KeepLeftParser.parse("42") }

class KeepRightParser < PackratParser
  start_symbol :num
  def num
    term("#") >> term(/\d+/).map { |s| s.to_i }
  end
end
assert_equal 7, KeepRightParser.parse("#7"), ">> keeps right result"

# Combined, mirroring `( expr )`: skip "(", parse, then skip ")".
class WrappedParser < PackratParser
  start_symbol :wrapped
  def wrapped
    term("(") >> term(/\d+/).map { |s| s.to_i } << term(")")
  end
end
assert_equal 99, WrappedParser.parse("(99)"), "combined >> ... << unwraps"

# `+` keeps both results as a pair (Scala's `~`).
class PairParser < PackratParser
  start_symbol :pair
  def pair
    term(/\d/).map { |s| s.to_i } + term(/\d/).map { |s| s.to_i }
  end
end
assert_equal [3, 7], PairParser.parse("37"), "+ keeps both results"

# `+` is left-associative and nests, like Scala's `~`.
class TripleParser < PackratParser
  start_symbol :triple
  def triple
    d = term(/\d/).map { |s| s.to_i }
    (d + d + d).map { |(a, b), c| [a, b, c] }
  end
end
assert_equal [1, 2, 3], TripleParser.parse("123"), "+ nests left-associatively"

# ---------------------------------------------------------------------------
# The calculator: recursion, precedence, parens, memoization.
# ---------------------------------------------------------------------------
require_relative "../examples/simple_calc"

assert_equal 7, SimpleCalcParser.parse("1+2*3"), "precedence: * before +"
assert_equal 9, SimpleCalcParser.parse("(1+2)*3"), "parentheses override precedence"
assert_equal 10, SimpleCalcParser.parse("2*3+4"), "left operand of +"
assert_equal 12, SimpleCalcParser.parse("12/4/3"), "right-associative division 12/(4/3)"
assert_equal 7, SimpleCalcParser.parse("((7))"), "nested parens"
assert_raise(PackratParser::ParseError, "malformed input") { SimpleCalcParser.parse("1+") }
assert_raise(PackratParser::ParseError, "trailing junk") { SimpleCalcParser.parse("1+2x") }

# Recursion / memo sanity: a deeply nested expression parses (and would be
# pathological without per-(rule,pos) memoization).
deep = "(" * 50 + "1" + ")" * 50
assert_equal 1, SimpleCalcParser.parse(deep), "deeply nested parens parse"

report!
