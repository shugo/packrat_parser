# Racc grammar for a four-function integer calculator.
class RaccCalc
rule
  target: exp

  exp: exp '+' term   { result = val[0] + val[2] }
     | exp '-' term   { result = val[0] - val[2] }
     | term

  term: term '*' fact { result = val[0] * val[2] }
      | term '/' fact { result = val[0] / val[2] }
      | fact

  fact: '(' exp ')'   { result = val[1] }
      | NUMBER
end

---- header
# generated

---- inner
  def parse(str)
    @tokens = []
    until str.empty?
      case str
      when /\A\s+/
        # skip
      when /\A\d+/
        @tokens << [:NUMBER, $&.to_i]
      when /\A[+\-*\/()]/
        @tokens << [$&, $&]
      else
        raise "unexpected: #{str.inspect}"
      end
      str = $'
    end
    @tokens << [false, false]
    do_parse
  end

  def next_token
    @tokens.shift
  end
