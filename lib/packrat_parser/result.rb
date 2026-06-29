class PackratParser
  # The result of running a parser at some position in the input.
  #
  # +Success+ carries the parsed +value+ and +pos+, the index of the next
  # unconsumed character. +Failure+ carries the +pos+ where parsing failed and
  # a human-readable +message+.
  class Success
    attr_reader :value, :pos

    def initialize(value, pos)
      @value = value
      @pos = pos
    end

    def success?
      true
    end

    def to_s
      "Success(#{@value.inspect} @#{@pos})"
    end
    alias inspect to_s
  end

  class Failure
    attr_reader :pos, :message

    def initialize(pos, message)
      @pos = pos
      @message = message
    end

    def success?
      false
    end

    def to_s
      "Failure(#{@message} @#{@pos})"
    end
    alias inspect to_s
  end

  # Raised by PackratParser#parse when the input cannot be parsed, or when the
  # start symbol succeeds but does not consume the whole input.
  class ParseError < StandardError
    attr_reader :pos

    def initialize(message, pos)
      @pos = pos
      super("#{message} (at position #{pos})")
    end
  end
end
