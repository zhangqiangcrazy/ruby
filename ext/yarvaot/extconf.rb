#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

require 'mkmf'
require 'rbconfig'

raise <<END unless RbConfig::CONFIG['EXTSTATIC'].empty?
Sorry,  YARVAOT feature  needs an  explicit dynamic  loading of  this extension
library.  You cannot compile this lib without dynamic loadings.
END

$VPATH << '$(top_srcdir)' << '$(topdir)'
$INCFLAGS << ' -I$(top_srcdir) -I$(topdir)'
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
