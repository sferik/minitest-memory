require "objspace"
require "minitest/strict"
require_relative "memory/version"

##
# Minitest extensions for memory allocation assertions.

module Minitest
  ##
  # Provides assertions for tracking memory allocations in tests.
  # Include this module in your test class to use +assert_allocations+.
  module Memory
    ##
    # Counts object allocations within a block using ObjectSpace.
    class AllocationCounter
      ##
      # Counts allocations by class within a block. Returns a Hash
      # mapping each class to its allocation count. Temporarily
      # disables GC during counting.

      def self.count(&)
        GC.start
        GC.disable
        generation = GC.count
        ObjectSpace.trace_object_allocations(&)
        count_allocations generation
      ensure
        GC.enable
      end

      ##
      # Returns a Hash of allocations from the given +generation+.

      def self.count_allocations generation
        allocations = Hash.new(0)
        ObjectSpace.each_object do |obj|
          allocations[obj.class] += 1 if ObjectSpace.allocation_generation(obj) == generation
        end
        allocations
      end
    end

    ##
    # Fails if any class in +limits+ exceeds its allocation count
    # within a block. +limits+ is a Hash mapping classes to maximum
    # allowed allocations. Eg:
    #
    #   assert_allocations(String => 1) { "hello" }

    def assert_allocations(limits, &)
      actual = AllocationCounter.count(&)

      limits.each do |klass, max_count|
        count = actual[klass]
        limit = max_count.zero? ? "no" : "at most #{max_count}"
        msg = "Expected #{limit} #{klass} allocations, got #{count}"
        assert_operator max_count, :>=, count, msg
      end
    end

    ##
    # Fails if any of the given +classes+ are allocated within a
    # block. Eg:
    #
    #   refute_allocations(String, Array) { 1 + 1 }

    def refute_allocations(*classes, &)
      assert_allocations(classes.product([0]).to_h, &)
    end
  end
end
