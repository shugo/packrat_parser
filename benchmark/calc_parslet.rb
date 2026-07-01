require "parslet"

# Four-function integer calculator built with parslet, for benchmarking against
# packrat_parser and racc. Right-recursive so its associativity matches
# packrat_parser (classic packrat has no left recursion).
class ParsletCalc < Parslet::Parser
  rule(:number) { match('[0-9]').repeat(1).as(:num) }
  rule(:lparen) { str('(') }
  rule(:rparen) { str(')') }

  rule(:primary) {
    (lparen >> additive >> rparen) | number
  }

  rule(:multitive) {
    (primary.as(:l) >> match('[*/]').as(:op) >> multitive.as(:r)) | primary
  }

  rule(:additive) {
    (multitive.as(:l) >> match('[+\-]').as(:op) >> additive.as(:r)) | multitive
  }

  root(:additive)
end

class ParsletCalcTransform < Parslet::Transform
  rule(num: simple(:n)) { Integer(n) }
  rule(l: simple(:l), op: simple(:op), r: simple(:r)) {
    case op.to_s
    when "+" then l + r
    when "-" then l - r
    when "*" then l * r
    when "/" then l / r
    end
  }
end

def parslet_eval(src)
  tree = ParsletCalc.new.parse(src)
  ParsletCalcTransform.new.apply(tree)
end

if __FILE__ == $PROGRAM_NAME
  %w[1+2*3 (1+2)*3 12/4/3 2*3+4].each { |s| puts "#{s} => #{parslet_eval(s)}" }
end
