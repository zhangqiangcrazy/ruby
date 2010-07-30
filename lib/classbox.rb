class Classbox < Module
  def import_to(binding)
    @__overlayed_modules__.each do |klass, modules|
      modules.each do |mod|
        overlay_module(klass, mod, binding)
      end
    end
  end

  private

  def initialize
    super
    @__overlayed_modules__ = {}
  end

  def refine(klass, &block)
    mod = Module.new
    modules = @__overlayed_modules__[klass] ||= []
    modules.push(mod)
    overlay_module(klass, mod, binding(1))
    # TODO: Why isn't the following code necessary?
    # import_to(block.binding)
    mod.module_eval(&block)
  end
end

def classbox(name, &block)
  begin
    mod = Object.const_get(name)
  rescue NameError
    mod = Classbox.new
    Object.const_set(name, mod)
  end
  mod.module_eval(&block)
end

def import_classbox(classbox)
  classbox.import_to(binding(1))
end
