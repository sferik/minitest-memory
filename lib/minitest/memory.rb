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
      # Tracks allocation count and total byte size for a class.
      Allocation = Struct.new(:count, :size) # rubocop:disable Lint/StructNewOverride

      ##
      # Base memory size of an empty Ruby object slot.
      SLOT_SIZE = ObjectSpace.memsize_of(Object.new)

      ##
      # An empty allocation with zero count and size.
      EMPTY = Allocation.new(0, 0).freeze

      ##
      # Counts allocations by class within a block. Returns a Hash
      # mapping each class to an Allocation with count and size.
      # Temporarily disables GC during counting.

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
        allocations = {} # steep:ignore
        ObjectSpace.each_object do |obj|
          next unless ObjectSpace.allocation_generation(obj) == generation

          allocation = allocations[obj.class] ||= Allocation.new(0, 0)
          allocation.count += 1
          allocation.size += ObjectSpace.memsize_of(obj) - SLOT_SIZE
        end
        allocations
      end
    end

    ##
    # Fails if any class in +limits+ exceeds its allocation limit
    # within a block. +limits+ is a Hash mapping classes to an
    # Integer (maximum count), a Range (required range), or a Hash
    # with +:count+ and/or +:size+ keys (each an Integer or Range).
    # Eg:
    #
    #   assert_allocations(String => 1) { "hello" }
    #   assert_allocations(String => 2..5) { "hello" }
    #   assert_allocations(String => {size: 1024}) { "hello" }
    #   assert_allocations(String => {count: 1..5, size: 1024}) { "hello" }

    def assert_allocations(limits, &)
      actual = AllocationCounter.count(&)

      limits.each do |klass, limit|
        allocation = actual[klass] || AllocationCounter::EMPTY

        if limit.is_a?(Hash)
          assert_allocation_limit(klass, limit.fetch(:count), allocation.count) if limit.key?(:count)
          assert_allocation_limit(klass, limit.fetch(:size), allocation.size, "allocation bytes") if limit.key?(:size)
        else
          assert_allocation_limit(klass, limit, allocation.count)
        end
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

    private

    ##
    # Asserts that +actual+ falls within +limit+ for the given
    # +klass+ and +metric+. +limit+ may be an Integer (maximum)
    # or a Range.

    def assert_allocation_limit(klass, limit, actual, metric = "allocations")
      if limit.is_a?(Range) # steep:ignore
        msg = "Expected within #{limit} #{klass} #{metric}, got #{actual}"
        assert_includes limit, actual, msg
      else
        desc = limit.zero? ? "no" : "at most #{limit}"
        msg = "Expected #{desc} #{klass} #{metric}, got #{actual}"
        assert_operator limit, :>=, actual, msg
      end
    end
  end
end
