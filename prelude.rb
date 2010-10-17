class Mutex
  # call-seq:
  #    mutex.synchronize { ... }
  #
  # Obtains a lock, runs the block, and releases the lock when the
  # block completes.  See the example under Mutex.
  def synchronize
    self.lock
    begin
      yield
    ensure
      self.unlock rescue nil
    end
  end
end

class Thread
  MUTEX_FOR_THREAD_EXCLUSIVE = Mutex.new # :nodoc:

  # call-seq:
  #    Thread.exclusive { block }   => obj
  #  
  # Wraps a block in Thread.critical, restoring the original value
  # upon exit from the critical section, and returns the value of the
  # block.
  def self.exclusive
    MUTEX_FOR_THREAD_EXCLUSIVE.synchronize{
      yield
    }
  end
end

class Classbox
  def import_to(binding)
    return unless @__overlayed_modules__
    @__overlayed_modules__.each do |klass, modules|
      modules.each do |mod|
        overlay_module(klass, mod, binding)
      end
    end
  end

  private

  @@__optimized_methods__ = [
    :+, :-, :*, :/, :%, :==, :===, :<, :<=, :<<, :[], :[]=, :>, :>=, :!, :!=,
    :length, :size, :succ
  ]

  def refine(klass, &block)
    @__overlayed_modules__ ||= {}
    mod = Module.new
    modules = @__overlayed_modules__[klass] ||= []
    modules.push(mod)
    overlay_module(klass, mod, binding(1))
    mod.singleton_class.send(:define_method, :method_added) do |mid|
      if @@__optimized_methods__.include?(mid)
        klass.send(:alias_method, :__original_optimized_method__, mid)
        klass.send(:define_method, mid) {}
        klass.send(:alias_method, mid, :__original_optimized_method__)
        klass.send(:remove_method, :__original_optimized_method__)
      end
    end
    mod.module_eval(&block)
  end
end

def classbox(name, &block)
  klassbox = Classbox.new
  Object.const_set(name, klassbox)
  klassbox.module_eval(&block)
end

def import(klassbox)
  klassbox.import_to(binding(1))
end

class Module
  def import(klassbox)
    @__imported_classboxes__ ||= {}
    @__imported_classboxes__[klassbox] = true
    klassbox.import_to(binding(1))
  end

  def __opened__(b = binding(1))
    return unless @__imported_classboxes__
    @__imported_classboxes__.each_key do |klassbox|
      klassbox.import_to(b)
    end
  end
end

class Class
  def __opened__
    unless @__imported_classboxes__
      @__imported_classboxes__ =
        self.superclass.instance_variable_get(:@__imported_classboxes__)
    end
    super(binding(1))
  end
end

class Classbox
  def __opened__
    b = binding(1)
    import_to(b)
    super(b)
  end
end
