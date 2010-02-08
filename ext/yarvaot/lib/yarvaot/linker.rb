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
		@shared = false

		@opt.on '--shared', <<-'begin'.strip do |optarg|
                                   Invokes a linker,  instead of a compiler, to
                                   create an extension  library (which can then
                                   be  loaded   from  other  ruby   scripts  by
                                   requireing that shared object).
		begin
			@shared = optarg
		end
	end

	# attribute reader needed from driver
	attr_reader :shared

	def run f, n
		run_in_tempfile n do |h|
			c = RbConfig::CONFIG.merge 'hdrdir' => $hdrdir.quote,
												'arch_hdrdir' => $arch_hdrdir
			l = if @shared
					 linker_line f, h
				 else
					 aout_line f, n, h
				 end
			l = RbConfig.expand l, c
			verbose_out "running Linker: %s", l
			p = Process.spawn l
			Process.waitpid p
		end
	end

	private

	def linker_line f, h
		sprintf "$(LDSHARED) %s%s %s -L$(archdir) -l:yarvaot.$(DLEXT)" \
				  " %s %s %s %s %s",
				  COUTFLAG,
				  h.path,
				  f.path,
				  $LIBPATH.join,
				  $DLDFLAGS,
				  $LOCAL_LIBS,
				  $LIBRUBYARG_SHARED,
				  $LIBS
	end

	def aout_line f, n, h
		g = create_mainobj n
		sprintf "$(CC) %s%s %s %s -L$(archdir) -l:yarvaot.$(DLEXT)" \
				  " %s %s %s %s %s",
				  COUTFLAG,
				  h.path,
				  f.path,
				  g.path,
				  $LIBPATH.join,
				  $DLDFLAGS,
				  $LOCAL_LIBS,
				  $LIBRUBYARG_SHARED,
				  $LIBS
	end

	def create_mainobj n
		run_in_tempfile n do |g|
			r, w = IO.pipe
			c = RbConfig::CONFIG.merge 'hdrdir' => $hdrdir.quote,
												'arch_hdrdir' => $arch_hdrdir
			l = sprintf "$(CC) %s %s %s %s -c %s%s -xc -",
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
		end
	end

	def genmain io, n
		c = canonname n
		io.write <<-end
#include <string.h>
#include <ruby/ruby.h>
extern VALUE Init_#{c}(VALUE);
extern void ruby_init_loadpath_safe(int);
extern void Init_prelude(void);
RUBY_GLOBAL_SETUP
int
main(int argc, char** argv)
{
    int state = 0;
    RUBY_INIT_STACK;
    ruby_sysinit(&argc, &argv);
    ruby_init();
    ruby_init_loadpath_safe(0);
    rb_protect(Init_#{c}, Qnil, &state);
    return state;
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
