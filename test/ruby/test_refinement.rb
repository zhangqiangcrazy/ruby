require 'test/unit'

class TestRefinement < Test::Unit::TestCase
  class Foo
    def x
      return "Foo#x"
    end

    def y
      return "Foo#y"
    end

    def call_x
      return x
    end
  end

  module FooExt
    refine Foo do
      def x
        return "FooExt#x"
      end

      def y
        return "FooExt#y " + super
      end

      def z
        return "FooExt#z"
      end
    end
  end

  module FooExt2
    refine Foo do
      def x
        return "FooExt2#x"
      end

      def y
        return "FooExt2#y " + super
      end

      def z
        return "FooExt2#z"
      end
    end
  end

  class FooSub < Foo
    def x
      return "FooSub#x"
    end

    def y
      return "FooSub#y " + super
    end
  end

  class FooExtClient
    using FooExt

    def self.invoke_x_on(foo)
      return foo.x
    end

    def self.invoke_y_on(foo)
      return foo.y
    end

    def self.invoke_z_on(foo)
      return foo.z
    end

    def self.invoke_call_x_on(foo)
      return foo.call_x
    end
  end

  class FooExtClient2
    using FooExt
    using FooExt2

    def self.invoke_y_on(foo)
      return foo.y
    end
  end

  def test_override
    foo = Foo.new
    assert_equal("Foo#x", foo.x)
    assert_equal("FooExt#x", FooExtClient.invoke_x_on(foo))
    assert_equal("Foo#x", foo.x)
  end

  def test_super
    foo = Foo.new
    assert_equal("Foo#y", foo.y)
    assert_equal("FooExt#y Foo#y", FooExtClient.invoke_y_on(foo))
    assert_equal("Foo#y", foo.y)
  end

  def test_super_chain
    foo = Foo.new
    assert_equal("Foo#y", foo.y)
    assert_equal("FooExt2#y FooExt#y Foo#y", FooExtClient2.invoke_y_on(foo))
    assert_equal("Foo#y", foo.y)
  end

  def test_new_method
    foo = Foo.new
    assert_raise(NoMethodError) { foo.z }
    assert_equal("FooExt#z", FooExtClient.invoke_z_on(foo))
    assert_raise(NoMethodError) { foo.z }
  end

  def test_no_local_rebinding
    foo = Foo.new
    assert_equal("Foo#x", foo.call_x)
    assert_equal("Foo#x", FooExtClient.invoke_call_x_on(foo))
    assert_equal("Foo#x", foo.call_x)
  end

  def test_subclass_is_prior
    sub = FooSub.new
    assert_equal("FooSub#x", sub.x)
    assert_equal("FooSub#x", FooExtClient.invoke_x_on(sub))
    assert_equal("FooSub#x", sub.x)
  end

  def test_subclass_is_prior
    sub = FooSub.new
    assert_equal("FooSub#x", sub.x)
    assert_equal("FooSub#x", FooExtClient.invoke_x_on(sub))
    assert_equal("FooSub#x", sub.x)
  end

  def test_super_in_subclass
    sub = FooSub.new
    assert_equal("FooSub#y Foo#y", sub.y)
    # not "FooSub#y FooExt#y Foo#y"
    assert_equal("FooSub#y Foo#y", FooExtClient.invoke_y_on(sub))
    assert_equal("FooSub#y Foo#y", sub.y)
  end

  def test_new_method_on_subclass
    sub = FooSub.new
    assert_raise(NoMethodError) { sub.z }
    assert_equal("FooExt#z", FooExtClient.invoke_z_on(sub))
    assert_raise(NoMethodError) { sub.z }
  end

  def test_module_eval
    foo = Foo.new
    assert_equal("Foo#x", foo.x)
    assert_equal("FooExt#x", FooExt.module_eval { foo.x })
    assert_equal("Foo#x", foo.x)
  end

  def test_instance_eval
    foo = Foo.new
    ext_client = FooExtClient.new
    assert_equal("Foo#x", foo.x)
    assert_equal("FooExt#x", ext_client.instance_eval { foo.x })
    assert_equal("Foo#x", foo.x)
  end

  def test_override_builtin_method
    m = Module.new {
      refine Fixnum do
        def /(other) quo(other) end
      end
    }
    assert_equal(0, 1 / 2)
    assert_equal(Rational(1, 2), m.module_eval { 1 / 2 })
    assert_equal(0, 1 / 2)
  end
end
