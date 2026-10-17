require "simplecov"
SimpleCov.start do
  if RUBY_ENGINE == "ruby"
    enable_coverage :branch
    minimum_coverage line: 100, branch: 100
  else
    minimum_coverage line: 51
  end
  skip "/test/"
end

require "minitest/autorun"
require "minitest/memory"
require "mutant/minitest/coverage"
