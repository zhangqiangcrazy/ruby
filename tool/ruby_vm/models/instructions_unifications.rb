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
require_relative 'bare_instructions'
require_relative 'opt_insn_unif_def'

# Instruction unification is a kind of specialization that two or more adjacent
# instructions are merged into one.
class RubyVM::InstructionsUnifications
  include RubyVM::CEscape

  attr_reader :name

  def initialize location:, signature:
    @location = location
    @name     = namegen signature
    @series   = signature.map do |i|
      RubyVM::BareInstructions.to_h.fetch i # Misshit is fatal
    end
  end

  private

  def namegen signature
    as_tr_cpp ['UNIFIED', *signature].join('_')
  end

  @instances = RubyVM::OptInsnUnifDef.map do |h|
    new(**h)
  end

  def self.to_a
    @instances
  end
end
