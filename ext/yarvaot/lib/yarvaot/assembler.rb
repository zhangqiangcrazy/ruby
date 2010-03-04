#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

# This do not directly uses make, but mkmf.rb has some handy global variables.
require 'rbconfig'
require 'mkmf'
require 'tmpdir'

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
		run_in_tempfile n do |g|
			c = RbConfig::CONFIG.merge 'hdrdir' => $hdrdir.quote,
												'arch_hdrdir' => $arch_hdrdir
			# This if-branch is  theoretically not needed, but a  file path can be
			# handy when you debug a compiler-outputted binary using a C debugger.
			if f.is_a? File
				p = f.path
				h = {}
			else
				p = '-'
				h = { in: f }
			end
			t = File.basename n, '.*'
			with_header_files t do |inc|
				l = sprintf "$(CC) %s -I %s %s %s %s -c %s%s -xc %s",
								$INCFLAGS,
								inc,
								$CPPFLAGS,
								$CFLAGS,
								$ARCH_FLAG,
								COUTFLAG,
								g.path,
								p
				l = RbConfig.expand l, c
				verbose_out "running C compiler: %s", l
				p = Process.spawn l, h
				# should wait this process, or  the linker which follows this stage
				# can read corrupted tempfile before CC finishes to write to.
				Process.waitpid p
			end
		end
	end

	private

	# Creates a temporary directory, put neccesary header files in it, and yield
	# the given block.  Does neccesary finishing up.
	def with_header_files template
		Dir.mktmpdir template do |tmp|
			Dir.chdir tmp do
				YARVAOT::HEADERS.each_pair do |k, v|
					File.open k, 'wb:binary' do |f|
						f.write v
					end
				end
			end
			yield tmp
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
