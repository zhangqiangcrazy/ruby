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
scanner = RubyVM::Scanner.new '../../../defs/opt_operand.def'
path    = scanner.__FILE__
grammer = %r'
    (?<comment> \# .+? \n                      ){0}
    (?<ws>      \g<comment> | \s               ){0}
    (?<insn>    \w+                            ){0}
    (?<paren>   \( (?: \g<paren> | [^()]+)* \) ){0}
    (?<expr>    (?: \g<paren> | [^(),\ \n] )+  ){0}
    (?<remain>  \g<expr>                       ){0}
    (?<arg>     \g<expr>                       ){0}
    (?<extra>   , \g<ws>* \g<remain>           ){0}
    (?<args>    \g<arg> \g<extra>*             ){0}
    (?<decl>    \g<insn> \g<ws>+ \g<args> \n   ){0}
'mx

until scanner.eos? do
  break if scanner.scan(/ ^ __END__ $ /x)
  next  if scanner.scan(/#{grammer} \g<ws>+ /x)

  line = scanner.scan!(/#{grammer} \g<decl> /mx)
  insn = scanner["insn"]
  args = scanner["args"]
  ary  = []
  until args.strip.empty? do
    tmp = StringScanner.new args
    tmp.scan(/#{grammer}\g<args>/mx)
    ary << tmp["arg"]
    args = tmp["remain"]
    break unless args
  end
  json << {
    location: [path, line],
    signature: [insn, ary]
  }
end

RubyVM::OptOperandDef = json

return unless __FILE__ == $0
require 'json' or raise 'miniruby is NG'
JSON.dump RubyVM::OptOperandDef, STDOUT
