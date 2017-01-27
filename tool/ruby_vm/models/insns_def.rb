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

json    = {}
scanner = RubyVM::Scanner.new '../../../insns.def'
path    = scanner.__FILE__
grammer = %r'
    (?<C-comment> /\* (?> .*? \*/ )                                        ){0}
    (?<ws>        \g<C-comment> | \s                                       ){0}
    (?<ident>     \w+                                                      ){0}
    (?<C-expr>    \{ (?: \g<C-expr> | [^{}]+ )* \}                         ){0}
    (?<impl>      impl \g<ws>+ \g<C-expr>                                  ){0}
    (?<typekw>    struct | union | enum | const | volatile                 ){0}
    (?<type>      (?: \g<typekw> \g<ws>+ )* \g<ident>                      ){0}
    (?<attr>      attr \g<ws>+ \g<type> \g<ws>+
                      \g<ident> \g<ws>* = \g<ws>* \g<C-expr> ;             ){0}
    (?<vars>      (?: \w+ | \.\.\. ) (?: , \g<ws>* \g<vars> )?             ){0}
    (?<decl>      \g<type> \g<ws>+ \g<vars> \g<ws>* ;                      ){0}
    (?<K&R>       (?: \g<ws>* \g<decl> )* \g<ws>*                          ){0}
    (?<attrs>     (?: \g<ws>* \g<attr> )* \g<ws>*                          ){0}
    (?<ope>       \g<vars>?                                                ){0}
    (?<pop>       \g<vars>?                                                ){0}
    (?<ret>       \g<vars>?                                                ){0}
    (?<name>      \g<ident>                                                ){0}
    (?<sig>       \g<name> \( \g<ope> \) \( \g<pop> \) \( \g<ret> \)       ){0}
    (?<insn>      insn \g<ws> \g<sig> \g<K&R>
                  \{
                          \g<attrs> \g<impl> \g<ws>*
                  \}                                                       ){0}
'mx

until scanner.eos? do
  next if scanner.scan(/#{grammer} \g<ws>+ /mx)

  l1   = scanner.scan!(/#{grammer} insn \g<ws> \g<sig> \g<ws>*/mx)
  name = scanner["name"]
  ope  = scanner["ope"].split(/, /)
  pop  = scanner["pop"].split(/, /)
  ret  = scanner["ret"].split(/, /)

  l2    = scanner.scan!(/#{grammer} \g<K&R> \g<ws>* \{ \g<ws>* /mx)
  decls = {
    location: [path, l2],
    body: scanner["K&R"],
  }

  attrs         = {}
  while l3      = scanner.scan(/#{grammer} \g<attr> \g<ws>* /mx) do
    attr        = scanner["ident"]
    attrs[attr] = {
      location: [path, l3],
      name: attr,
      type: scanner["type"].strip,
      body: scanner["C-expr"].strip,
    }
  end

  l4   = scanner.scan!(/#{grammer} \g<impl> \g<ws>* \} /mx)
  body = scanner["C-expr"].strip

  json[name] = {
    location: [path, l1],
    signature: {
      name: name,
      ope: ope,
      pop: pop,
      ret: ret,
    },
    declarations: decls,
    attributes: attrs,
    impl: {
      location: [path, l4],
      name: name,
      body: body,
    },
  }
end

RubyVM::InsnsDef = json

return unless __FILE__ == $0
require 'json' or raise 'miniruby is NG'
JSON.dump RubyVM::InsnsDef, STDOUT
