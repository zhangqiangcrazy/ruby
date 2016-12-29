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

require_relative 'c_expr'

# An attribute  is a  (possibly inlined) function  attached to  an instruction.
# Its body is normally somewhere inside  of insns.def but its name and function
# prototype is generated automatically.
#
# See also corresponding _attributes.erb
class RubyVM::Attribute
  include RubyVM::CEscape
  attr_reader :insn, :name, :type, :expr

  def initialize insn:, name:, type:, location:, body:
    # :HACK: indentation fix
    body.sub!(/^\s*}\s*\z/, '}')

    @insn = insn
    @name = "#{name} @ #{insn.name}"
    @disp = "attr #{type} #{name} @ #{insn.pretty_name}"
    json  = {
      location: location,
      body: body,
    }
    @expr = RubyVM::CExpr.new json
    @type = type
  end

  def pretty_name
    @disp
  end

  def signature
    type = @type
    name = as_tr_cpp @name
    argv = @insn.opes.map do |o|
      t = @insn.typeof o
      next [t, o]
    end
    return [type, name, argv]
  end
end
