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

require_relative '../helpers/c_escape'

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
    @name = as_tr_cpp "attr #{name} @ #{insn.name}"
    @disp = "attr #{type} #{name} @ #{insn.pretty_name}"
    @expr = RubyVM::CExpr.new location: location, body: body
    @type = type
  end

  # methods used in view:

  def pretty_name
    @disp
  end

  def prototype_declaration
    args = argv.join ', '
    sprintf "PUREFUNC(MAYBE_UNUSED(static %s %s(%s)));", @type, @name, args
  end

  def argv_maybe_unused
    return argv.map {|o| "MAYBE_UNUSED(#{o})" }
  end

  private
  def argv
    return @insn.opes.map {|o| "#{@insn.typeof o} #{o}" }
  end
end
