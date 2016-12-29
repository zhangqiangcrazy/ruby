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
require_relative 'opt_operand_def'

# Operands unification  is a kind  of specialization  that some operands  to an
# instruction is a constant, and thus be omitted.
#
# This class has only one parent so it is a direct subclass.
#
# See also coressponding optinsn.inc.erb
class RubyVM::OperandsUnifications < RubyVM::BareInstructions
  include RubyVM::CEscape

  attr_reader :preamble, :original

  def initialize location:, signature:
    name             = signature[0]
    template         = RubyVM::InsnsDef.fetch name # Misshit is fatal
    parts            = compose location, signature, template[:signature]
    json             = template.dup
    json[:location]  = location
    json[:signature] = parts[:signature]
    @preamble        = parts[:preamble]
    @spec            = parts[:spec]
    @original        = RubyVM::BareInstructions.fetch name
    super(**json)
  end

  def operand_shift_of var
    before = @original.opes.find_index var
    after  = @opes.find_index var
    raise "no #{var} for #{@name}" unless before and after
    return before - after
  end

  def condition ptr
    # :FIXME: I'm not sure if this method should be in model?
    exprs = @spec.each_with_index.map do |(var, val), i|
      case val when '*' then
        next nil
      else
        type = typeof var
        expr = RubyVM::Typemap.typecast_to_VALUE type, val
        next "#{ptr}[#{i}] == #{expr}"
      end
    end
    exprs.compact!
    if exprs.size == 1 then
      return exprs[0]
    else
      exprs.map! {|i| "(#{i})" }
      return exprs.join ' && '
    end
  end

  private

  def namegen signature
    insn, argv = *signature
    wcary = argv.map do |i|
      case i when '*' then
        'WC'
      else
        i
      end
    end
    as_tr_cpp [insn, *wcary].join(', ')
  end

  def compose location, spec, template
    name    = namegen spec
    *, argv = *spec
    opes    = template[:ope]
    if opes.size != argv.size
      raise sprintf("operand size mismatch for %s (%s's: %d, given: %d)",
                    name, template[:name], opes.size, argv.size)
    else
      src  = []
      mod  = []
      spec = []
      argv.each_index do |i|
        j = argv[i]
        k = opes[i]
        spec[i] = [k, j]
        case j when '*' then
          # operand is from iseq
          mod << k
        else
          # operand is inside C
          src << {
            location: location,
            body: "    #{k} = #{j};"
          }
        end
      end
      src.map! {|i| RubyVM::CExpr.new i }
      return {
        signature: {
          name: name,
          ope: mod,
          pop: template[:pop],
          ret: template[:ret],
        },
        preamble: src,
        spec: spec
      }
    end
  end

  @instances = RubyVM::OptOperandDef.map do |h|
    new(**h)
  end

  def self.to_a
    @instances
  end

  def self.each_group
    to_a.group_by(&:original).each_pair do |k, v|
      yield k, v
    end
  end
end
