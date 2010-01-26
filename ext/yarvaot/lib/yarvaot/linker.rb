#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.
require 'rbconfig'
require 'mkmf'
require 'tempfile'

# This is the linker, generates an executable.
class YARVAOT::Linker < YARVAOT::Subcommand

	# Instantiate.  Does nothing yet.
	def initialize
		super
		@opt.separator '    linker has no option yet.'
	end

	def run f, n
		g = create_mainobj n
		b = File.basename n, 'rb'
		h = Tempfile.new b
		c = RbConfig::CONFIG.merge 'hdrdir' => $hdrdir.quote,
											'arch_hdrdir' => $arch_hdrdir
		l = sprintf "%s %s %s %s %s %s%s %s %s %s %s",
			RbConfig::CONFIG['CC'],
			$CFLAGS,
			$ARCH_FLAG,
			$LIBPATH.join,
			$LDFLAGS,
			COUTFLAG,
			h.path,
			f.path,
			g.path,
			$LIBRUBYARG_STATIC,
			$LIBS
		l = RbConfig.expand l, c
		verbose_out "running C compiler: %s", l
		p = Process.spawn l
		Process.waitpid p
		return h		
	end

	def create_mainobj n
		b = File.basename n, 'rb'
		g = Tempfile.new b
		r, w = IO.pipe
		c = RbConfig::CONFIG.merge 'hdrdir' => $hdrdir.quote,
											'arch_hdrdir' => $arch_hdrdir
		l = sprintf "%s %s %s %s %s -c %s%s -xc -",
			RbConfig::CONFIG['CC'],
			$INCFLAGS,
			$CPPFLAGS,
			$CFLAGS,
			$ARCH_FLAG,
			COUTFLAG,
			g.path
		l = RbConfig.expand l, c
		verbose_out "running C compiler: %s", l
		p = Process.spawn l, in: r
		genmain w, n
		w.close
		Process.waitpid p
		g.close
		g.open
		return g
	end

	private
	def genmain io, n
		b = File.basename n, '.rb'
		q = as_tr_cpp b
		io.write <<-end
#include <string.h>
#include <ruby/ruby.h>
extern struct RString* #{q};
extern VALUE rb_iseq_load(VALUE, VALUE, VALUE);
static VALUE
load_insns(VALUE ign)
{
    VALUE ary;
    VALUE str = (VALUE)#{q};
    #{q}->basic.klass = rb_cString;
    ary = rb_marshal_load((VALUE)#{q});
    return rb_iseq_load(ary, 0, 0);
}
int
main(int argc, char** argv)
{
    RUBY_INIT_STACK;
    ruby_sysinit(&argc, &argv);
    ruby_init();
    ruby_init_loadpath_safe(0);
ruby_debug = Qtrue;
ruby_verbose = Qtrue;
    return ruby_run_node((void*)rb_protect(load_insns, Qnil, 0));
}
		end
	end
end

# 
# Local Variables:
# mode: ruby
# coding: utf-8
# indent-tabs-mode: t
# tab-width: 3
# ruby-indent-level: 3
# fill-column: 79
# default-justification: full
# End:
# vi: ts=3 sw=3
