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

require_relative '../helpers/scanner'

json    = []
scanner = RubyVM::Scanner.new '../../../defs/opt_insn_unif.def'
path    = scanner.__FILE__
until scanner.eos? do
  next  if scanner.scan(/ ^ (?: \#.* )? \n /x)
  break if scanner.scan(/ ^ __END__ $ /x)

  pos = scanner.scan!(/(?<series>  (?: [\ \t]* \w+ )+ ) \n /mx)
  json << {
    location: [path, pos],
    signature: scanner["series"].strip.split
  }
end

RubyVM::OptInsnUnifDef = json

return unless __FILE__ == $0
require 'json' or raise 'miniruby is NG'
JSON.dump RubyVM::OptInsnUnifDef, STDOUT
