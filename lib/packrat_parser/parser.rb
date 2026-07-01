class PackratParser
  # A parser combinator. Wraps a function (input, pos) -> Success | Failure.
  #
  # The four monadic operations (+flat_map+, +map+, +filter+, +pure+) are what
  # the `for ... then` comprehension in the Ruby fork desugars to, so grammar
  # rules can be written with comprehension syntax:
  #
  #   for x in multitive, _ in term("+"), y in additive then x + y end
  #     # => multitive.flat_map { |x| term("+").flat_map { |_| additive.map { |y| x + y } } }
  class Parser
    def initialize(&fn)
      @fn = fn
    end

    # Run this parser against +input+ starting at +pos+.
    def call(input, pos)
      @fn.call(input, pos)
    end

    # Sequencing / monadic bind. On success, +yield+ the value to obtain the
    # next parser and run it where this one stopped. Failures short-circuit.
    def flat_map
      Parser.new do |input, pos|
        result = call(input, pos)
        if result.success?
          next_parser = yield(result.value)
          next_parser.call(input, result.pos)
        else
          result
        end
      end
    end

    # Transform the successful value without consuming further input.
    def map
      Parser.new do |input, pos|
        result = call(input, pos)
        result.success? ? Success.new(yield(result.value), result.pos) : result
      end
    end

    # Succeed only when the block returns a truthy value for the parsed result;
    # otherwise fail at the position where this parser started. This is what a
    # `when` guard in a comprehension desugars to.
    def filter
      Parser.new do |input, pos|
        result = call(input, pos)
        if result.success? && yield(result.value)
          result
        else
          Failure.new(pos, "guard failed")
        end
      end
    end

    # Ordered choice (PEG `/`). Try this parser; if it fails, try +other+ at the
    # same position. Reports whichever failure reached furthest into the input.
    def |(other)
      Parser.new do |input, pos|
        result = call(input, pos)
        if result.success?
          result
        else
          alt = other.call(input, pos)
          if alt.success?
            alt
          else
            alt.pos >= result.pos ? alt : result
          end
        end
      end
    end

    # Sequence, keeping the *left* result (Scala's `<~`). Run this parser, then
    # +other+, and on success return this parser's value, discarding +other+'s.
    #
    #   number << term(";")   # parse a number followed by ";", yield the number
    def <<(other)
      # Equivalent to flat_map { |x| other.map { |_| x } }, but written directly
      # so the combinator graph is built once (at bind time) instead of
      # allocating a fresh `map` parser on every successful match.
      Parser.new do |input, pos|
        a = call(input, pos)
        if a.success?
          b = other.call(input, a.pos)
          b.success? ? Success.new(a.value, b.pos) : b
        else
          a
        end
      end
    end

    # Sequence, keeping the *right* result (Scala's `~>`). Run this parser, then
    # +other+, and on success return +other+'s value, discarding this one's.
    #
    #   term("(") >> additive   # skip "(", yield whatever additive produces
    def >>(other)
      # Equivalent to flat_map { |_| other }, written directly to avoid the
      # per-call block dispatch.
      Parser.new do |input, pos|
        a = call(input, pos)
        a.success? ? other.call(input, a.pos) : a
      end
    end

    # Sequence, keeping *both* results (Scala's `~`). Run this parser, then
    # +other+, and on success return the pair +[left, right]+. The result type is
    # the product of the operands' types, so `*` (product) is the natural
    # spelling -- and it dovetails with `|` for choice, mirroring how a regular
    # language is a semiring with choice as the sum and sequence as the product.
    #
    # Like Scala's `~` this is left-associative and nests, so `p * q * r` yields
    # `[[a, b], c]`; Ruby's block-parameter destructuring takes them apart the
    # way Scala's `case a ~ b ~ c` does:
    #
    #   (p * q * r).map { |(a, b), c| ... }
    def *(other)
      # Equivalent to flat_map { |x| other.map { |y| [x, y] } }, written directly
      # so only the result pair (and its Success) is allocated per match, not a
      # fresh intermediate `map` parser.
      Parser.new do |input, pos|
        a = call(input, pos)
        if a.success?
          b = other.call(input, a.pos)
          b.success? ? Success.new([a.value, b.value], b.pos) : b
        else
          a
        end
      end
    end

    # Zero or more repetitions (Scala's `rep` / `p.*`). Always succeeds, yielding
    # an array of the collected values (empty when there are no matches). A match
    # that consumes no input stops the loop, so a nullable parser can't spin
    # forever.
    def rep
      Parser.new do |input, pos|
        values = []
        cur = pos
        loop do
          result = call(input, cur)
          break if !result.success? || result.pos == cur
          values << result.value
          cur = result.pos
        end
        Success.new(values, cur)
      end
    end

    # One or more repetitions (Scala's `rep1` / `p.+`). Fails if the first match
    # fails; otherwise yields a non-empty array of values.
    def rep1
      flat_map { |first| rep.map { |rest| [first, *rest] } }
    end

    # Optional (Scala's `opt` / `p.?`). Yields the parsed value, or nil (consuming
    # nothing) when this parser does not match.
    def opt
      Parser.new do |input, pos|
        result = call(input, pos)
        result.success? ? result : Success.new(nil, pos)
      end
    end
  end

  # A lazy, memoizing reference to a named grammar rule.
  #
  # Rule methods on a PackratParser subclass return a Rule instead of building
  # their combinator immediately. This is essential: a comprehension evaluates
  # its generator *receivers* eagerly (to call flat_map/map on them), so a
  # self-referential rule like `additive` would recurse forever at build time if
  # the body ran on every reference. Returning a lazy Rule breaks that cycle.
  #
  # Memoizing the *result* per (rule, pos) gives the packrat property: each rule
  # is evaluated at most once per input position, so parsing stays linear.
  #
  # The combinator graph is built once per rule and cached on the owner. This
  # relies on the comprehension's loop variables being block-local: each closure
  # built from the rule body owns its loop-variable bindings, so reusing one
  # cached closure across recursive activations (e.g. additive calling additive)
  # is safe. (An earlier fork leaked the loop variables into the rule-method
  # scope, which forced a rebuild per entry so activations would not clobber each
  # other's bindings; that workaround is no longer needed now that the
  # comprehension scopes them.)
  class Rule < Parser
    def initialize(owner, name, body)
      @owner = owner
      @name = name
      @body = body
    end

    def call(input, pos)
      # Two-level memo table (rule -> pos -> result). Keying on a single [name,
      # pos] Array would allocate one Array per rule invocation and hash it;
      # nesting keeps the per-call key a bare Integer.
      memo = (@owner.__memo[@name] ||= {})
      return memo[pos] if memo.key?(pos)
      combinator = (@owner.__built[@name] ||= @body.bind(@owner).call)
      memo[pos] = combinator.call(input, pos)
    end

    # Parse +input+ starting from this rule, e.g. +parser.number.parse("123")+.
    # Delegates to the owner so memo reset, whitespace handling, and the
    # full-consumption check are applied exactly as for the start symbol.
    def parse(input)
      @owner.parse(input, @name)
    end
  end
end
