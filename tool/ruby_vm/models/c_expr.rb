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

require_relative '../helpers/c_escape.rb'

class RubyVM::CExpr
  include RubyVM::CEscape

  attr_reader :__FILE__, :__LINE__, :body

  def initialize location:, body:, name: '(null)'
    @__FILE__  = location[0]
    @__LINE__  = location[1]
    @name = name
    @body = body
  end

  def inspect
    sprintf "#<%s:%#016x %s@%s:%d>",\
            self.class, self.object_id << 1, \
            @name, @__FILE__, @__LINE__
  end
end
