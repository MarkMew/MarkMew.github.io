# Load Rouge lexers that are not auto-loaded by the Jekyll pipeline.
require "rouge"
require "rouge/regex_lexer" unless defined?(Rouge::RegexLexer)
require "rouge/lexers/hcl"
require "rouge/lexers/terraform"
