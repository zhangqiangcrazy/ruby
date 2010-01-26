#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

# This do not directly uses make, but mkmf.rb has some handy global variables.
require 'rbconfig'
require 'mkmf'
require 'tempfile'

# This is the assembler, C->object transformation engine.
class YARVAOT::Assembler < YARVAOT::Subcommand

	# Instantiate.  Does nothing yet.
	def initialize
		super
		@opt.separator '    assembler has no option yet.'
	end

	# GCC, at least  version 4.3.3 on Linux, cannot dump  an assembler output to
	# its standard output.  It needs to have some seekable file to write to.
	def run f, n
		b = File.basename n, 'rb'
		g = Tempfile.new b
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
		p = Process.spawn l, in: f
		Process.waitpid p
		return g
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
