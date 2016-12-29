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

require_relative 'insns_def'
require_relative 'c_expr'
require_relative 'typemap'
require_relative 'attribute'

class RubyVM::BareInstructions
  attr_reader :name, :opes, :pops, :rets, :decls, :impl

  def initialize location:, signature:, declarations:, attributes:, impl:
    # :HACK: indentation fix
    impl[:body].sub!(/^{/, '    {')
    declarations[:body].sub!(/^ *(?=\S)/, '    ')
    declarations[:body].chomp!

    @loc   = location
    @sig   = signature
    @decls = RubyVM::CExpr.new declarations
    @impl  = RubyVM::CExpr.new impl
    @name  = @sig[:name]
    @opes  = @sig[:ope]
    @pops  = @sig[:pop].reject {|i| i == '...'}
    @rets  = @sig[:ret].reject {|i| i == '...'}
    @typemap = split declarations
    @attrs = attributes.transform_values {|i|
      RubyVM::Attribute.new(insn: self, **i)
    }
  end

  def pretty_name
    n = @sig[:name]
    o = @sig[:ope].join ', '
    p = @sig[:pop].join ', '
    r = @sig[:ret].join ', '
    return sprintf "%s(%s)(%s)(%s)", n, o, p, r
  end

  def bin
    return "BIN(#{name})"
  end

  def sp_inc
    return @attrs.fetch "sp_inc" do |k|
      return generate_attribute k, 'rb_num_t', rets.size - pops.size
    end
  end

  def attributes
    # need to generate predefined attribute defaults
    sp_inc
    # other_attribute
    # ...
    return @attrs.values
  end

  def width
    return 1 + opes.size
  end

  def macros
    return {}
  end

  def preamble
    # preamble makes sense for operand unifications
    return []
  end

  def sc?
    # sc stands for stack caching.
    return false
  end

  def typeof var
    @typemap.fetch var
  end

  def cast_to_VALUE var, expr = var
    t = typeof var
    RubyVM::Typemap.typecast_to_VALUE t, expr
  end

  def cast_from_VALUE var, expr = var
    t = typeof var
    RubyVM::Typemap.typecast_from_VALUE t, expr
  end

  def operands_info
    opes.map {|o|
      k = typeof o
      c, _ = RubyVM::Typemap.fetch k
      next c
    }.join
  end

  private

  def split decls
    decls[:body].each_line.each_with_object Hash.new do |d, h|
      dd = d.chomp.chomp ";"
      type, va = dd.split ' ', 2
      vars = va.split ', '
      vars.each do |v|
        h[v] = type
      end
    end
  end

  def generate_attribute k, t, v
    expr = sprintf "{\n    return %s;\n}", v
    attr = RubyVM::Attribute.new \
      insn: self, \
      name: k, \
      type: t, \
      location: [], \
      body: expr
    return @attrs[k] = attr
  end

  @instances = RubyVM::InsnsDef.transform_values {|h| new(**h) }

  def self.fetch name
    @instances.fetch name
  end

  def self.to_h
    @instances
  end

  def self.to_a
    @instances.values
  end
end
