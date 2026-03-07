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
      # Counts retained allocations by class within a block.
      # Returns a Hash mapping each class to an Allocation with
      # count and size. Runs GC after the block to identify
      # objects that survive garbage collection.

      def self.count_retained(&)
        GC.start
        GC.disable
        generation = GC.count
        ObjectSpace.trace_object_allocations(&)
        GC.start
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
    #
    # Use the +:count+ and +:size+ symbol keys to set global limits
    # across all classes. Eg:
    #
    #   assert_allocations(String => 1) { "hello" }
    #   assert_allocations(String => 2..5) { "hello" }
    #   assert_allocations(String => {size: 1024}) { "hello" }
    #   assert_allocations(count: 10) { "hello" }
    #   assert_allocations(String => 1, count: 10) { "hello" }

    def assert_allocations(limits, &)
      actual = AllocationCounter.count(&)
      limits.each { |klass, limit| assert_allocation_entry(klass, limit, actual) }
    end

    ##
    # Fails if any class in +limits+ exceeds its retention limit
    # within a block. Works like +assert_allocations+ but only
    # counts objects that survive garbage collection.
    #
    # *Warning:* Garbage collection is disabled while the block
    # executes. Avoid long-running or memory-intensive code inside
    # the block.
    #
    # Eg:
    #
    #   assert_retentions(String => 0) { "hello" }
    #   assert_retentions(String => {count: 1, size: 1024}) { "hello" }

    def assert_retentions(limits, &)
      actual = AllocationCounter.count_retained(&)

      limits.each do |klass, limit|
        assert_per_class_limit(klass, actual[klass] || AllocationCounter::EMPTY, limit, "retentions", "retained bytes")
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

    ##
    # Fails if any of the given +classes+ are retained within a
    # block. Eg:
    #
    #   refute_retentions(String, Array) { 1 + 1 }

    def refute_retentions(*classes, &)
      assert_retentions(classes.product([0]).to_h, &)
    end

    ##
    # Includes +Expectations+ into +Minitest::Expectation+ when
    # +minitest/spec+ is loaded, enabling the +must_*+ / +wont_*+
    # expectation syntax.

    def self.included(base) # :nodoc:
      super
      # :nocov:
      Minitest::Expectation.include(Expectations) if defined?(Minitest::Expectation)
      # :nocov:
    end

    ##
    # Minitest::Spec expectations for memory allocation assertions.
    # These methods are added to +Minitest::Expectation+ when
    # +minitest/spec+ is loaded.
    module Expectations
      ##
      # See Minitest::Memory#assert_allocations.
      #
      #   _ { code }.must_limit_allocations(String => {count: 10})

      def must_limit_allocations(limits)
        ctx.assert_allocations(limits, &target) # steep:ignore
      end

      ##
      # See Minitest::Memory#assert_retentions.
      #
      #   _ { code }.must_limit_retentions(String => 1)

      def must_limit_retentions(limits)
        ctx.assert_retentions(limits, &target) # steep:ignore
      end

      ##
      # See Minitest::Memory#refute_allocations.
      #
      #   _ { code }.wont_allocate(String, Array)

      def wont_allocate(*classes)
        ctx.refute_allocations(*classes, &target) # steep:ignore
      end

      ##
      # See Minitest::Memory#refute_retentions.
      #
      #   _ { code }.wont_retain(String, Array)

      def wont_retain(*classes)
        ctx.refute_retentions(*classes, &target) # steep:ignore
      end
    end

    private

    ##
    # Dispatches a single +limit+ entry for the given +klass+
    # against +actual+ allocations. Routes +:count+ and +:size+
    # to total-limit checks, and everything else to per-class checks.

    def assert_allocation_entry(klass, limit, actual)
      case klass
      when :count
        assert_allocation_limit("total", limit, actual.each_value.sum(&:count)) # steep:ignore
      when :size
        assert_allocation_limit("total", limit, actual.each_value.sum(&:size), "allocation bytes") # steep:ignore
      else
        assert_per_class_limit(klass, actual[klass] || AllocationCounter::EMPTY, limit)
      end
    end

    ##
    # Asserts per-class +limit+ against +allocation+ for the given
    # +klass+. +limit+ may be an Integer, Range, or Hash with
    # +:count+ and/or +:size+ keys.

    def assert_per_class_limit(klass, allocation, limit, metric = "allocations", size_metric = "allocation bytes")
      if limit.is_a?(Hash)
        assert_allocation_limit(klass, limit.fetch(:count), allocation.count, metric) if limit.key?(:count)
        assert_allocation_limit(klass, limit.fetch(:size), allocation.size, size_metric) if limit.key?(:size)
      else
        assert_allocation_limit(klass, limit, allocation.count, metric)
      end
    end

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
