class PackratParser
  # Subclass this and define grammar rules as plain methods that return parsers.
  # Every method defined in a subclass is automatically treated as a rule: it is
  # rewritten to return a lazy, memoizing Rule (see Rule), so rules may reference
  # each other (and themselves) without infinitely recursing while the combinator
  # graph is built.
  #
  #   class SimpleCalcParser < PackratParser
  #     def additive
  #       (for x in multitive, _ in term("+"), y in additive then x + y end) | multitive
  #     end
  #     ...
  #   end
  #
  #   SimpleCalcParser.parse("1+2*3")  # => 7

  # Set (or read) the rule the parser starts from.
  # If omitted, the first defined method is used as the start symbol.
  def self.start_symbol(name = nil)
    if name
      @start_symbol = name
    else
      @start_symbol
    end
  end

  # Enable implicit whitespace skipping (Scala's RegexParsers mode). When set,
  # every +term+ skips leading whitespace matching +pattern+ before attempting
  # its match, and +parse+ also consumes trailing whitespace before requiring
  # full input consumption. Off by default (terminals match exactly).
  #
  #   class CalcParser < PackratParser
  #     skip_whitespace            # default /\s+/
  #     # skip_whitespace(/[ \t]+/)  # or a custom pattern
  #   end
  def self.skip_whitespace(pattern = /\s+/)
    @__whitespace = pattern
  end

  # The configured whitespace pattern, or nil when skipping is disabled.
  # Inherited by subclasses so a base parser can turn the mode on once.
  def self.whitespace
    return @__whitespace if defined?(@__whitespace)
    superclass.respond_to?(:whitespace) ? superclass.whitespace : nil
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
    @start_symbol ||= name
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

  # Cache of built combinators, keyed by rule name. The combinator graph for a
  # rule is stable, so it is built once and reused (loop variables are
  # block-local, so reusing a closure across recursive activations is safe).
  def __built
    @__built ||= {}
  end

  # A terminal parser. A String matches that exact literal at the current
  # position; a Regexp is matched anchored at the current position. The matched
  # substring is the parser's value.
  #
  # Positions are *byte* offsets, not character offsets: indexing a UTF-8 string
  # by character is O(n), so matching by byte (+byteslice+ for literals,
  # +byteindex+ with a `\G` anchor for regexps) keeps each step O(match length)
  # regardless of how far into the input we are.
  #
  # When the class enables +skip_whitespace+, leading whitespace is consumed
  # before the match is attempted, mirroring Scala's RegexParsers.
  def term(pattern)
    ws = self.class.whitespace
    ws = /\G(?:#{ws})/ if ws
    case pattern
    when String
      bytes = pattern.bytesize
      Parser.new do |input, pos|
        pos = __skip_ws(ws, input, pos)
        if input.byteslice(pos, bytes) == pattern
          Success.new(pattern, pos + bytes)
        else
          Failure.new(pos, "expected #{pattern.inspect}")
        end
      end
    when Regexp
      anchored = /\G(?:#{pattern})/
      Parser.new do |input, pos|
        pos = __skip_ws(ws, input, pos)
        if input.byteindex(anchored, pos)
          s = Regexp.last_match[0]
          Success.new(s, pos + s.bytesize)
        else
          Failure.new(pos, "expected #{pattern.inspect}")
        end
      end
    else
      raise ArgumentError, "term expects a String or Regexp, got #{pattern.class}"
    end
  end

  # Advance the byte offset +pos+ past whitespace matched by the anchored regexp
  # +ws+ (nil when skipping is disabled). Returns the new byte offset.
  def __skip_ws(ws, input, pos)
    return pos unless ws
    input.byteindex(ws, pos) ? pos + Regexp.last_match[0].bytesize : pos
  end

  # A parser that succeeds with +value+ without consuming any input (monadic
  # unit / Scala's `success`).
  def pure(value)
    Parser.new { |_input, pos| Success.new(value, pos) }
  end

  # Parse +input+, starting from rule +start+ (defaults to the configured start
  # symbol). Returns the parsed value on success; raises ParseError on failure or
  # on leftover input. Pass +start+ to parse from any rule, e.g.
  # +parser.parse("123", :number)+ or, equivalently, +parser.number.parse("123")+.
  #
  # Positions are byte offsets throughout, including the +pos+ reported on a
  # ParseError (see +term+ for why matching is byte-oriented).
  def parse(input, start = nil)
    @__memo = {}
    name = start || self.class.start_symbol
    raise ParseError.new("no start symbol defined", 0) unless name

    result = send(name).call(input, 0)
    unless result.success?
      raise ParseError.new(result.message, result.pos)
    end
    # The last terminal skips only *leading* whitespace, so trailing whitespace
    # after the final token is left for parse to consume before requiring that
    # all input was used.
    ws = self.class.whitespace
    end_pos = __skip_ws(ws && /\G(?:#{ws})/, input, result.pos)
    if end_pos < input.bytesize
      raise ParseError.new("unexpected trailing input", end_pos)
    end
    result.value
  end
end
