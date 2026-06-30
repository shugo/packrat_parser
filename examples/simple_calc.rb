# Run with the Ruby fork's legacy parser, which understands `for ... then`:
#
#   /workspace/ruby/ruby --disable-gems --parser=parse.y -Ilib examples/simple_calc.rb
#
require "packrat_parser"

# A four-function integer calculator.
#
# The grammar is right-recursive (additive -> multitive "+" additive), which is
# what classic packrat parsing supports without left-recursion handling. A
# consequence is that "-" and "/" associate to the right, e.g. 8-3-2 parses as
# 8-(3-2) == 7. That trade-off comes from the monadic-core / no-`rep` API.
class SimpleCalcParser < PackratParser
  def additive
    for x in multitive << term("+"), y in additive then x + y end |
      for x in multitive << term("-"), y in additive then x - y end |
      multitive
  end

  def multitive
    for x in primary << term("*"), y in multitive then x * y end |
      for x in primary << term("/"), y in multitive then x / y end |
      primary
  end

  def primary
    for x in term("(") >> additive << term(")") then x end |
      number
  end

  def number
    for s in term(/\d+/) then s.to_i end
  end
end

if __FILE__ == $PROGRAM_NAME
  examples = ["1+2*3", "(1+2)*3", "2*3+4", "12/4/3", "((7))"]
  examples.each do |src|
    puts "#{src} => #{SimpleCalcParser.parse(src)}"
  end
end
