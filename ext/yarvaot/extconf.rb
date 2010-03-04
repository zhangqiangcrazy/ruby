#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

require 'mkmf'
require 'rbconfig'
extend RbConfig

exit true unless enable_config 'yarvaot', true

if CONFIG['ENABLE_SHARED'] != 'yes' or !CONFIG['EXTSTATIC'].empty?
	message <<END
Sorry, YARVAOT feature needs an explicit dynamic loading of both this extension
library and the libruby.#{CONFIG['DLEXT']}.
You cannot compile this lib without dynamic loadings.
END
	exit
end

$defs.push '-DCABI_OPERANDS' if enable_config 'cabi-operands', true

$VPATH << '$(top_srcdir)' << '$(topdir)'
$INCFLAGS << ' -I$(top_srcdir) -I$(topdir)'
$objs = %w'yarvaot.o'
$srcs = %w'yarvaot.c.rb yarvaot.h.rb'
create_header
create_makefile 'yarvaot'

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
