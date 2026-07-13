require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  skip "/test/"
  minimum_coverage line: 100, branch: 100
end

require "minitest/autorun"
require "minitest/memory"
require "mutant/minitest/coverage"
