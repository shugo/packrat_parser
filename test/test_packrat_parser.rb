# Run with the Ruby fork's legacy parser:
#
#   ruby --parser=parse.y -Ilib test/test_packrat_parser.rb
#
require "packrat_parser"
require "test/unit"
require_relative "../examples/simple_calc"

# ---------------------------------------------------------------------------
# Grammar fixtures. These use the `for ... then` comprehension, so the whole
# file must be parsed with --parser=parse.y.
# ---------------------------------------------------------------------------
class LiteralParser < PackratParser
  def greeting
    term("hi")
  end
end

class DigitsParser < PackratParser
  start_symbol :num
  def num
    for s in term(/\d+/) then s.to_i end
  end
end

class PureParser < PackratParser
  start_symbol :nothing
  def nothing
    pure(42)
  end
end

class MapParser < PackratParser
  start_symbol :doubled
  def doubled
    term(/\d+/).map { |s| s.to_i * 2 }
  end
end

class FlatMapParser < PackratParser
  start_symbol :pair
  def pair
    term(/\d/).flat_map { |a| term(/\d/).map { |b| [a.to_i, b.to_i] } }
  end
end

class ForParser < PackratParser
  start_symbol :pair
  def pair
    for a in term(/\d/), _ in term(","), b in term(/\d/) then [a.to_i, b.to_i] end
  end
end

# `when` guard desugars to filter.
class GuardParser < PackratParser
  start_symbol :even
  def even
    for n in term(/\d+/) when n.to_i.even? then n.to_i end
  end
end

class FilterParser < PackratParser
  start_symbol :small
  def small
    term(/\d+/).map { |s| s.to_i }.filter { |n| n < 100 }
  end
end

class ChoiceParser < PackratParser
  start_symbol :ab
  def ab
    term("a") | term("b")
  end
end

class KeepLeftParser < PackratParser
  start_symbol :num
  def num
    term(/\d+/).map { |s| s.to_i } << term(";")
  end
end

class KeepRightParser < PackratParser
  start_symbol :num
  def num
    term("#") >> term(/\d+/).map { |s| s.to_i }
  end
end

# Combined, mirroring `( expr )`: skip "(", parse, then skip ")".
class WrappedParser < PackratParser
  start_symbol :wrapped
  def wrapped
    term("(") >> term(/\d+/).map { |s| s.to_i } << term(")")
  end
end

# `*` keeps both results as a pair (Scala's `~`).
class PairParser < PackratParser
  start_symbol :pair
  def pair
    term(/\d/).map { |s| s.to_i } * term(/\d/).map { |s| s.to_i }
  end
end

# `*` is left-associative and nests, like Scala's `~`.
class TripleParser < PackratParser
  start_symbol :triple
  def triple
    d = term(/\d/).map { |s| s.to_i }
    (d * d * d).map { |(a, b), c| [a, b, c] }
  end
end

# Whitespace skipping (Scala's RegexParsers mode): opt-in via skip_whitespace.
class WsCalcParser < PackratParser
  skip_whitespace
  start_symbol :additive

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
    (for _l in term("("), x in additive, _r in term(")") then x end) | number
  end

  def number
    for s in term(/\d+/) then s.to_i end
  end
end

# A custom whitespace pattern: skip spaces/tabs only, so a newline is trailing junk.
class SpacesOnlyParser < PackratParser
  skip_whitespace(/[ \t]+/)
  start_symbol :pair
  def pair
    for a in term(/\d+/), b in term(/\d+/) then [a.to_i, b.to_i] end
  end
end

# Subclasses inherit the whitespace setting (rules are inherited too; only the
# start symbol is re-declared, since start_symbol does not walk ancestors).
class InheritedWsParser < WsCalcParser
  start_symbol :additive
end

# Private methods are ordinary helpers, not grammar rules.
class HelperParser < PackratParser
  start_symbol :doubled
  def doubled
    for n in number then twice(n) end
  end
  def number
    for s in term(/\d+/) then s.to_i end
  end

  private

  def twice(n)
    n * 2
  end
end

# Multibyte literal followed by a multibyte regexp capture (katakana name, so it
# stops before the hiragana honorific "さん").
class GreetingParser < PackratParser
  start_symbol :greet
  def greet
    for _ in term("こんにちは、"), name in term(/\p{Katakana}+/), _ in term("さん") then name end
  end
end

class KanjiNumParser < PackratParser
  start_symbol :pair
  def pair
    for word in term(/\p{Han}+/), n in term(/\d+/) then [word, n.to_i] end
  end
end

# Whitespace skipping with a multibyte whitespace character (full-width space
# U+3000, 3 bytes).
class WsKanjiParser < PackratParser
  skip_whitespace(/[\s　]+/)
  start_symbol :pair
  def pair
    for a in term(/\p{Han}+/), b in term(/\p{Han}+/) then [a, b] end
  end
end

class TestPackratParser < Test::Unit::TestCase
  # -------------------------------------------------------------------------
  # Terminals: literal strings and regexps, full vs partial consumption.
  # -------------------------------------------------------------------------
  def test_literal_terminal
    assert_equal "hi", LiteralParser.parse("hi")
    assert_raise(PackratParser::ParseError) { LiteralParser.parse("ho") }
    assert_raise(PackratParser::ParseError) { LiteralParser.parse("hithere") }
  end

  def test_regexp_terminal
    assert_equal 1234, DigitsParser.parse("1234")
    assert_raise(PackratParser::ParseError) { DigitsParser.parse("abc") }
  end

  # -------------------------------------------------------------------------
  # Monadic core: pure / map / flat_map / filter, directly and via `for`.
  # -------------------------------------------------------------------------
  def test_pure_consumes_nothing
    assert_equal 42, PureParser.parse("")
  end

  def test_map
    assert_equal 20, MapParser.parse("10")
  end

  def test_flat_map
    assert_equal [3, 7], FlatMapParser.parse("37")
  end

  def test_for_comprehension
    assert_equal [4, 9], ForParser.parse("4,9")
  end

  def test_when_guard_desugars_to_filter
    assert_equal 8, GuardParser.parse("8")
    assert_raise(PackratParser::ParseError) { GuardParser.parse("7") }
  end

  def test_filter
    assert_equal 42, FilterParser.parse("42")
    assert_raise(PackratParser::ParseError) { FilterParser.parse("999") }
  end

  # -------------------------------------------------------------------------
  # Ordered choice.
  # -------------------------------------------------------------------------
  def test_choice
    assert_equal "a", ChoiceParser.parse("a")
    assert_equal "b", ChoiceParser.parse("b")
    assert_raise(PackratParser::ParseError) { ChoiceParser.parse("c") }
  end

  # -------------------------------------------------------------------------
  # Sequencing operators: `<<` keeps the left result, `>>` the right, `*` both.
  # -------------------------------------------------------------------------
  def test_keep_left
    assert_equal 42, KeepLeftParser.parse("42;")
    assert_raise(PackratParser::ParseError) { KeepLeftParser.parse("42") }
  end

  def test_keep_right
    assert_equal 7, KeepRightParser.parse("#7")
  end

  def test_keep_left_and_right_combined
    assert_equal 99, WrappedParser.parse("(99)")
  end

  def test_pair_keeps_both
    assert_equal [3, 7], PairParser.parse("37")
  end

  def test_pair_nests_left_associatively
    assert_equal [1, 2, 3], TripleParser.parse("123")
  end

  # -------------------------------------------------------------------------
  # The calculator: recursion, precedence, parens, memoization.
  # -------------------------------------------------------------------------
  def test_calculator
    assert_equal 7, SimpleCalcParser.parse("1+2*3"), "precedence: * before +"
    assert_equal 9, SimpleCalcParser.parse("(1+2)*3"), "parentheses override precedence"
    assert_equal 10, SimpleCalcParser.parse("2*3+4"), "left operand of +"
    assert_equal 12, SimpleCalcParser.parse("12/4/3"), "right-associative division"
    assert_equal 7, SimpleCalcParser.parse("((7))"), "nested parens"
    assert_raise(PackratParser::ParseError) { SimpleCalcParser.parse("1+") }
    assert_raise(PackratParser::ParseError) { SimpleCalcParser.parse("1+2x") }
  end

  def test_deeply_nested_parens
    deep = "(" * 50 + "1" + ")" * 50
    assert_equal 1, SimpleCalcParser.parse(deep)
  end

  # -------------------------------------------------------------------------
  # Whitespace skipping.
  # -------------------------------------------------------------------------
  def test_whitespace_skipping
    assert_equal 7, WsCalcParser.parse("1 + 2 * 3"), "whitespace between tokens"
    assert_equal 9, WsCalcParser.parse("( 1 + 2 ) * 3"), "whitespace inside parens"
    assert_equal 7, WsCalcParser.parse("  1+2*3  "), "leading and trailing whitespace"
    assert_equal 7, WsCalcParser.parse("1\t+\n2 * 3"), "tabs and newlines"
    assert_equal 6, WsCalcParser.parse("1+2+3"), "no whitespace still parses"
  end

  def test_default_mode_is_exact
    assert_raise(PackratParser::ParseError) { SimpleCalcParser.parse("1 + 2") }
  end

  def test_custom_whitespace_pattern
    assert_equal [1, 2], SpacesOnlyParser.parse("1 \t 2")
    assert_raise(PackratParser::ParseError) { SpacesOnlyParser.parse("1\n2") }
  end

  def test_whitespace_setting_is_inherited
    assert_equal 7, InheritedWsParser.parse("1 + 2 * 3")
  end

  # -------------------------------------------------------------------------
  # Parsing from a specific rule (Scala's parse(rule, input)).
  # -------------------------------------------------------------------------
  def test_parse_from_rule
    assert_equal 123, SimpleCalcParser.new.number.parse("123"), "rule.parse"
    assert_equal 6, SimpleCalcParser.new.multitive.parse("2*3"), "recursive rule"
    assert_equal 6, SimpleCalcParser.new.parse("2*3", :multitive), "explicit start rule"
    assert_raise(PackratParser::ParseError) { SimpleCalcParser.new.number.parse("12x") }
  end

  # -------------------------------------------------------------------------
  # Private methods are ordinary helpers, not grammar rules.
  # -------------------------------------------------------------------------
  def test_private_method_is_a_helper
    assert_equal 42, HelperParser.parse("21"), "private method usable as a helper"
    assert_false HelperParser.new.respond_to?(:twice), "private helper stays private"
    assert_equal 10, HelperParser.new.send(:twice, 5), "helper returns a value, not a Rule"
    assert_equal 7, HelperParser.new.number.parse("7"), "public sibling is still a rule"
  end

  # -------------------------------------------------------------------------
  # Multibyte (UTF-8) input: positions are tracked by byte offset.
  # -------------------------------------------------------------------------
  def test_multibyte_literals_and_regexp
    assert_equal "シュゴ", GreetingParser.parse("こんにちは、シュゴさん")
  end

  def test_byte_advance_across_kanji
    assert_equal ["三二一", 123], KanjiNumParser.parse("三二一123")
  end

  def test_multibyte_whitespace
    assert_equal ["日本", "語"], WsKanjiParser.parse(" 日本 　語 ")
  end

  def test_error_position_is_a_byte_offset
    # "三二一" is 9 bytes (3 kanji x 3 bytes) + "123" is 3 bytes, so the stray
    # "x" is at byte offset 12.
    e = assert_raise(PackratParser::ParseError) { KanjiNumParser.parse("三二一123x") }
    assert_equal 12, e.pos
  end
end
