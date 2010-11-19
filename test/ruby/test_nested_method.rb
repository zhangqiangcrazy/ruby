require 'test/unit'

class TestNestedMethod < Test::Unit::TestCase
  def call_nested_method
    def foo
      return "foo"
    end

    return foo
  end

  def test_nested_method
    assert_equal("foo", call_nested_method)
    assert_raise(NoMethodError) { foo() }
  end

  def test_doubly_nested_method
    def call_doubly_nested_method
      def foo
        return "foo"
      end

      return foo
    end

    assert_equal("foo", call_doubly_nested_method)
    assert_raise(NoMethodError) { foo() }
  end
end
