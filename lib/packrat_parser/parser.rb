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
      flat_map { |x| other.map { |_| x } }
    end

    # Sequence, keeping the *right* result (Scala's `~>`). Run this parser, then
    # +other+, and on success return +other+'s value, discarding this one's.
    #
    #   term("(") >> additive   # skip "(", yield whatever additive produces
    def >>(other)
      flat_map { |_| other }
    end

    # Sequence, keeping *both* results (Scala's `~`). Run this parser, then
    # +other+, and on success return the pair +[left, right]+. Like Scala's `~`
    # this is left-associative and nests, so `p + q + r` yields `[[a, b], c]`;
    # Ruby's block-parameter destructuring takes them apart the way Scala's
    # `case a ~ b ~ c` does:
    #
    #   (p + q + r).map { |(a, b), c| ... }
    def +(other)
      flat_map { |x| other.map { |y| [x, y] } }
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
  # The combinator graph is rebuilt on every (memo-missed) entry rather than
  # cached, and that is deliberate. The `for ... then` comprehension's loop
  # variables currently leak into the enclosing rule-method scope instead of
  # being block-local, so a single built closure shares those slots. If the same
  # closure were reused for a recursive activation (e.g. additive calling
  # additive), the inner activation would clobber the outer's leaked variables.
  # Building fresh gives each activation its own scope. The rebuild is bounded:
  # result memoization means a build happens at most once per (rule, pos).
  #
  # NOTE: this rebuild is a workaround for the loop-variable leak in the fork's
  # comprehension (parse.y: new_for_comp_gen leaves the loop var in the
  # surrounding scope, like the legacy `for`). If the comprehension is changed to
  # make loop variables block-local, this clobbering goes away and `built` can be
  # cached once per (owner, name) again -- e.g. `@owner.__built[@name] ||= ...`.
  class Rule < Parser
    def initialize(owner, name, body)
      @owner = owner
      @name = name
      @body = body
    end

    def call(input, pos)
      memo = @owner.__memo
      key = [@name, pos]
      return memo[key] if memo.key?(key)
      combinator = @body.bind(@owner).call
      memo[key] = combinator.call(input, pos)
    end
  end
end
