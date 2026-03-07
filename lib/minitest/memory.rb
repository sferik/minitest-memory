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
      # Holds allocation counting results: +allocated+ maps matched
      # classes to Allocations, +ignored+ maps unmatched classes,
      # and +total+ is the aggregate Allocation across all objects.
      Result = Struct.new(:allocated, :ignored, :total)

      ##
      # Base memory size of an empty Ruby object slot.
      SLOT_SIZE = ObjectSpace.memsize_of(Object.new)

      ##
      # An empty allocation with zero count and size.
      EMPTY = Allocation.new(0, 0).freeze

      ##
      # Returns +false+ on TruffleRuby where ObjectSpace tracing
      # is not supported, +true+ otherwise.

      def self.supported?
        # :nocov:
        return false if RUBY_ENGINE == "truffleruby"
        # :nocov:

        ObjectSpace.respond_to?(:trace_object_allocations)
      end

      ##
      # Counts allocations by class within a block. Returns a
      # Result. When +klasses+ are given, objects are matched via
      # +is_a?+; unmatched objects go to +ignored+. Temporarily
      # disables GC during counting.

      def self.count(klasses = [], &)
        # :nocov:
        return Result.new({}, {}, EMPTY) unless supported?
        # :nocov:

        GC.start
        GC.disable
        generation = GC.count
        ObjectSpace.trace_object_allocations(&)
        count_allocations(generation, klasses)
      ensure
        GC.enable
      end

      ##
      # Counts retained allocations by class within a block.
      # Returns a Result. Runs GC after the block to identify
      # objects that survive garbage collection.

      def self.count_retained(klasses = [], &)
        # :nocov:
        return Result.new({}, {}, EMPTY) unless supported?
        # :nocov:

        GC.start
        GC.disable
        generation = GC.count
        ObjectSpace.trace_object_allocations(&)
        GC.start
        count_allocations(generation, klasses)
      ensure
        GC.enable
      end

      ##
      # Returns a Result of allocations from the given +generation+.
      # When +klasses+ are given, objects are matched via +is_a?+
      # and unmatched objects are tracked separately in +ignored+
      # with a warning emitted for each.

      def self.count_allocations(generation, klasses = [])
        allocated = {} # steep:ignore
        ignored = {} # steep:ignore
        total = Allocation.new(0, 0)

        ObjectSpace.each_object do |obj|
          next unless ObjectSpace.allocation_generation(obj) == generation

          tally_object(obj, total, find_allocation(obj, klasses, allocated, ignored))
        end

        Result.new(allocated, ignored, total)
      end

      ##
      # Tallies one object's count and byte size into both the
      # +total+ and per-class +allocation+ entries.

      def self.tally_object(obj, total, allocation)
        size = ObjectSpace.memsize_of(obj) - SLOT_SIZE
        total.count += 1
        total.size += size
        allocation.count += 1
        allocation.size += size
      end
      private_class_method :tally_object

      ##
      # Finds or creates the Allocation entry for +obj+. When
      # +klasses+ are given, matches via +is_a?+ into +allocated+
      # or warns and files into +ignored+.

      def self.find_allocation(obj, klasses, allocated, ignored)
        return allocated[obj.class] ||= Allocation.new(0, 0) if klasses.empty?

        klass = klasses.find { |k| obj.is_a?(k) }
        return allocated[klass] ||= Allocation.new(0, 0) if klass

        ignored[obj.class] ||= Allocation.new(0, 0)
      end
      private_class_method :find_allocation
    end

    ##
    # Fails if any class in +limits+ does not match its allocation
    # limit within a block. +limits+ is a Hash mapping classes to
    # an Integer (exact count), a Range (required range), or a Hash
    # with +:count+ and/or +:size+ keys (each an Integer or Range).
    #
    # Objects are matched to classes via +is_a?+, so specifying
    # +Numeric+ captures +Integer+, +Float+, etc.
    #
    # Use the +:count+ and +:size+ symbol keys to set global limits
    # across all classes. When no global limit is set, allocations
    # of unspecified classes cause a failure (strict mode).
    #
    #   assert_allocations(String => 1) { "hello" }
    #   assert_allocations(String => 2..5) { "hello" }
    #   assert_allocations(String => {size: 1024}) { "hello" }
    #   assert_allocations(count: 10) { "hello" }
    #   assert_allocations(String => 1, count: 10) { "hello" }

    def assert_allocations(limits, &)
      klasses = limits.keys.select { |k| k.is_a?(Module) }
      has_total_limit = limits.key?(:count) || limits.key?(:size)
      result = AllocationCounter.count(klasses, &)

      limits.each { |klass, limit| assert_allocation_entry(klass, limit, result) }

      return if has_total_limit

      result.ignored.each do |klass, allocation|
        flunk "Allocated #{allocation.count} #{klass} instances, #{allocation.size} bytes, but it was not specified"
      end
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
      klasses = limits.keys.select { |k| k.is_a?(Module) }
      result = AllocationCounter.count_retained(klasses, &)

      limits.each do |klass, limit|
        assert_per_class_limit(klass, result.allocated[klass] ||
          AllocationCounter::EMPTY, limit, "retentions", "retained bytes")
      end
    end

    ##
    # Fails if any of the given +classes+ are allocated within a
    # block. Eg:
    #
    #   refute_allocations(String, Array) { 1 + 1 }

    def refute_allocations(*classes, &)
      result = AllocationCounter.count(classes, &)

      classes.each do |klass|
        allocation = result.allocated[klass] || AllocationCounter::EMPTY
        assert_allocation_limit(klass, 0, allocation.count)
      end
    end

    ##
    # Fails if any of the given +classes+ are retained within a
    # block. Eg:
    #
    #   refute_retentions(String, Array) { 1 + 1 }

    def refute_retentions(*classes, &)
      result = AllocationCounter.count_retained(classes, &)

      classes.each do |klass|
        allocation = result.allocated[klass] || AllocationCounter::EMPTY
        assert_allocation_limit(klass, 0, allocation.count, "retentions")
      end
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
    # against the +result+. Routes +:count+ and +:size+ to
    # total-limit checks, and everything else to per-class checks.

    def assert_allocation_entry(klass, limit, result)
      case klass
      when :count
        assert_allocation_limit("total", limit, result.total.count) # steep:ignore
      when :size
        assert_allocation_limit("total", limit, result.total.size, "allocation bytes") # steep:ignore
      else
        assert_per_class_limit(klass, result.allocated[klass] || AllocationCounter::EMPTY, limit)
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
    # Asserts that +actual+ matches +limit+ for the given +klass+
    # and +metric+. +limit+ may be an Integer (exact match) or a
    # Range (inclusion check).

    def assert_allocation_limit(klass, limit, actual, metric = "allocations")
      if limit.is_a?(Range) # steep:ignore
        msg = "Expected within #{limit} #{klass} #{metric}, got #{actual}"
        assert_includes limit, actual, msg
      else
        desc = limit.zero? ? "no" : "exactly #{limit}"
        msg = "Expected #{desc} #{klass} #{metric}, got #{actual}"
        assert_equal limit, actual, msg
      end
    end
  end
end
