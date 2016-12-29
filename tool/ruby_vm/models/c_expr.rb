#! /your/favourite/path/to/ruby
# -*- mode: ruby; coding: utf-8; indent-tabs-mode: nil; ruby-indent-level: 2 -*-
# -*- warn_indent: true; frozen_string_literal: true -*-
#
# Copyright (c) 2016 Urabe, Shyouhei.  All rights reserved.
#
# This file is  a part of the programming language  Ruby.  Permission is hereby
# granted, to  either redistribute and/or  modify this file, provided  that the
# conditions  mentioned in  the file  COPYING are  met.  Consult  the file  for
# details.

# This class represents  a snippet of C source code,  expected to be verbatimly
# copied into the output.  Because C  has #line preprocessor directive, we must
# retain where the source code was from.
#
# See also the corresponding _c_expr.erb
class RubyVM::CExpr
  attr_reader :__FILE__, :__LINE__, :body

  def initialize location:, body:
    @__FILE__  = location[0]
    @__LINE__  = location[1]
    @body = body
  end
end
