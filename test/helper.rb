# A tiny dependency-free assertion harness. The Ruby fork's in-tree binary can't
# load minitest/test-unit (bundled gems are absent), but plain assertions run
# fine, so the suite uses these helpers instead.
module TinyTest
  @passed = 0
  @failed = 0

  class << self
    attr_accessor :passed, :failed
  end

  module_function

  def assert_equal(expected, actual, msg = nil)
    if expected == actual
      TinyTest.passed += 1
    else
      TinyTest.failed += 1
      warn "FAIL: #{msg || "assert_equal"}: expected #{expected.inspect}, got #{actual.inspect}"
    end
  end

  def assert(cond, msg = nil)
    if cond
      TinyTest.passed += 1
    else
      TinyTest.failed += 1
      warn "FAIL: #{msg || "assert"}: expected truthy, got #{cond.inspect}"
    end
  end

  def assert_raise(klass, msg = nil)
    yield
    TinyTest.failed += 1
    warn "FAIL: #{msg || "assert_raise"}: expected #{klass} but nothing was raised"
  rescue klass
    TinyTest.passed += 1
  rescue => e
    TinyTest.failed += 1
    warn "FAIL: #{msg || "assert_raise"}: expected #{klass} but got #{e.class}: #{e.message}"
  end

  def report!
    puts "#{TinyTest.passed} passed, #{TinyTest.failed} failed"
    exit(TinyTest.failed.zero? ? 0 : 1)
  end
end
