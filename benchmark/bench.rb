# Performance comparison: packrat_parser vs racc vs parslet.
#
# All three implement the same four-function integer calculator (lexing + parse
# + evaluation to an Integer). Run under the fork's legacy parser, which the
# packrat_parser grammar needs for `for ... then`:
#
#   ruby --parser=parse.y benchmark/bench.rb
#
# or:  rake bench
#
# Requires the `parslet` gem (gem install parslet). Generate calc_racc.rb first
# with `racc -o benchmark/calc_racc.rb benchmark/calc.y` (rake bench does this).
require "benchmark"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "packrat_parser"
require File.expand_path("../examples/simple_calc", __dir__)
require_relative "calc_racc"
require_relative "calc_parslet"

# Build an expression of a given size: n terms of the form "a*b" joined with "+".
# Using only "+" and "*" keeps the value independent of associativity, so the
# three parsers (packrat/parslet are right-recursive, racc is left-recursive)
# all agree despite their different grammars.
def gen_expr(n)
  (1..n).map { |i| "#{i % 9 + 1}*#{i % 7 + 1}" }.join("+")
end

SIZES = [10, 50, 200]
INPUTS = SIZES.to_h { |n| [n, gen_expr(n)] }
ITER = 2000

# Sanity check: all three must agree before timing means anything.
check = INPUTS[10]
values = {
  "packrat_parser" => SimpleCalcParser.parse(check),
  "racc"           => RaccCalc.new.parse(check),
  "parslet"        => parslet_eval(check),
}
puts "sanity (#{check[0, 20]}...): #{values.inspect}"
unless values.values.uniq.size == 1
  abort "parsers disagree: #{values.inspect}"
end
puts "all agree: #{values.values.first}"
puts

SIZES.each do |n|
  src = INPUTS[n]
  puts "=== input size #{n} terms (#{src.bytesize} bytes), #{ITER} iterations ==="
  Benchmark.bm(16) do |b|
    b.report("packrat_parser") { ITER.times { SimpleCalcParser.parse(src) } }
    b.report("racc")           { ITER.times { RaccCalc.new.parse(src) } }
    b.report("parslet")        { ITER.times { parslet_eval(src) } }
  end
  puts
end
