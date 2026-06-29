class PackratParser
  # Subclass this and define grammar rules as plain methods that return parsers.
  # Every method defined in a subclass is automatically treated as a rule: it is
  # rewritten to return a lazy, memoizing Rule (see Rule), so rules may reference
  # each other (and themselves) without infinitely recursing while the combinator
  # graph is built.
  #
  #   class SimpleCalcParser < PackratParser
  #     start_symbol :additive
  #     def additive
  #       (for x in multitive, _ in term("+"), y in additive then x + y end) | multitive
  #     end
  #     ...
  #   end
  #
  #   SimpleCalcParser.parse("1+2*3")  # => 7

  # Set (or read) the rule the parser starts from.
  def self.start_symbol(name = nil)
    if name
      @start_symbol = name
    else
      @start_symbol
    end
  end

  # Convenience: parse +input+ with a fresh instance.
  def self.parse(input)
    new.parse(input)
  end

  # Rewrite every method defined on a subclass into a rule that returns a lazy
  # Rule. Guards against rewriting the base class's own infrastructure and
  # against re-entering while we install the replacement (define_method itself
  # fires method_added).
  def self.method_added(name)
    return if self == PackratParser
    return if name == :initialize
    return if @__defining_rule

    @__defining_rule = true
    begin
      body = instance_method(name)
      define_method(name) do
        Rule.new(self, name, body)
      end
    ensure
      @__defining_rule = false
    end
  end

  # Per-input packrat memo table, keyed by [rule_name, pos].
  def __memo
    @__memo ||= {}
  end

  # A terminal parser. A String matches that exact literal at the current
  # position; a Regexp is matched anchored at the current position. The matched
  # substring is the parser's value.
  def term(pattern)
    case pattern
    when String
      Parser.new do |input, pos|
        if input[pos, pattern.length] == pattern
          Success.new(pattern, pos + pattern.length)
        else
          Failure.new(pos, "expected #{pattern.inspect}")
        end
      end
    when Regexp
      anchored = /\G(?:#{pattern})/
      Parser.new do |input, pos|
        if (m = anchored.match(input, pos))
          Success.new(m[0], pos + m[0].length)
        else
          Failure.new(pos, "expected #{pattern.inspect}")
        end
      end
    else
      raise ArgumentError, "term expects a String or Regexp, got #{pattern.class}"
    end
  end

  # A parser that succeeds with +value+ without consuming any input (monadic
  # unit / Scala's `success`).
  def pure(value)
    Parser.new { |_input, pos| Success.new(value, pos) }
  end

  # Parse +input+ starting from the configured start symbol. Returns the parsed
  # value on success; raises ParseError on failure or on leftover input.
  def parse(input)
    @__memo = {}
    name = self.class.start_symbol
    raise ParseError.new("no start symbol defined", 0) unless name

    result = send(name).call(input, 0)
    unless result.success?
      raise ParseError.new(result.message, result.pos)
    end
    if result.pos < input.length
      raise ParseError.new("unexpected trailing input", result.pos)
    end
    result.value
  end
end
