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

# This script was needed only once when I converted the old insns.def.
# Consider historical.
#
# ruby converter.rb insns.def | sponge insns.def
#
# I had to touch e.g. comments, so the generated output is not identical to
# what was added to the repo.

str = ARGF.read

str.gsub! /\n\n+/, "\n\n"
str.gsub! /@c.*?@e/m, ''
str.gsub! /@j.*?\*\//m, '*/'
str.gsub! /^DEFINE_INSN$/, 'insn'
str.gsub! /^\t+/ do |m|
  ' ' * (m.size * 8)
end
str.gsub! /^(\w+)\n\((.*)\)\n\((.*)\)\n\((.*)\)/ do
  dh = {}
  insn = $1
  a = [$2, $3, $4].map do |m|
    b = m.split(', ').map do |d|
      case d when /\A\w+ /
        t, v = d.split ' ', 2
        dh[t] ||= []
        dh[t] << v
        next v
      else
        next d
      end
    end
    next sprintf "(%s)", b.join(', ')
  end
  da = dh.each_pair.map do |k, a|
    s = a.uniq.join(', ')
    sprintf "%s %s",  k, s
  end

  sprintf "%s%s\n    %s;", insn, a.join, da.join(";\n    ")
end
str.gsub! /^\{$(.*?)^\}$/m do |m|
  mm = m.gsub /\n/, "\n    "
  sprintf "{\n    impl %s\n}", mm
end
str.gsub! /^    ;\n/, ''
str.gsub! %r"^/\*\*\n(.*?)^  \*/$"m do
  mm = $1.gsub(/^   /, '').chomp.lines.join ' * '
  sprintf "/* %s */", mm
end
str.gsub! %r'; // inc \+= (.+)\n{', <<'end'
;
{
    attr sp_inc = { return \1 };
end

str.gsub! %r/ +$/, ''
str.gsub! /^ +#/, '#'
puts str
