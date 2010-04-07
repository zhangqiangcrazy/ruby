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
		@dir = nil
		@optdir = nil
		@opt.on '--rubysrc DIR', <<-'begin'.strip, String do |optarg|
                                   Supply  a  directory  which has  *identical*
                                   contents to the  source code which this ruby
                                   binary was created, and a compilation gets a
                                   little bit faster.   Note that if you supply
                                   wrong  contents  (e.g.   wrong version  ruby
                                   source  directory), a  compiled  binary gets
                                   broken.  And compilation  san safely be done
                                   without this flag.
		begin
			@optdir = optarg
		end

	end

	def runup n
		if @optdir
			@dir = @optdir
		else
			t = canonname n
			@dir = Dir.mktmpdir t
			prepare_header_files n
		end
		verbose_out 'ruby headers in %s', @dir
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
			l = sprintf "$(CC) %s -I %s %s %s %s -c %s%s -xc %s",
							$INCFLAGS,
							@dir,
							$CPPFLAGS,
							$CFLAGS,
							$ARCH_FLAG,
							COUTFLAG,
							g.path,
							p
			l = RbConfig.expand l, c
			verbose_out "running C compiler: %s", l
			begin
				p = Process.spawn l, h
			ensure
				# should wait this process, or  the linker which follows this stage
				# can read corrupted tempfile before CC finishes to write to.
				n, s = Process.waitpid2 p
				if s.success?
					unless @optdir
						verbose_out 'vanishing %s', @dir
						FileUtils.remove_entry_secure @dir
					end
				else
					# leave header files
					# do not run linker
					raise Errno::ECHILD, s.inspect
				end
			end
		end
	end

	private

	# Creates a temporary directory, put neccesary header files in it.
	def prepare_header_files name
		Dir.chdir @dir do
			YARVAOT::HEADERS.each_pair do |k, v|
				verbose_out 'dumping header file <%s>', k
				File.open k, 'wb:binary' do |f|
					f.write v
				end
				FileUtils.touch "insns.inc"
			end
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
