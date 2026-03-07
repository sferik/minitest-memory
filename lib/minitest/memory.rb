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
      Allocation = Struct.new(:count, :size, :sources) # rubocop:disable Lint/StructNewOverride

      ##
      # Holds allocation counting results: +allocated+ maps matched
      # classes to Allocations, +ignored+ maps unmatched classes,
      # and +total+ is the aggregate Allocation across all objects.
      Result = Struct.new(:allocated, :ignored, :total)

      ##
      # Base memory size of an empty Ruby object slot.
      SLOT_SIZE = ObjectSpace.memsize_of(Object.new)

      empty_sources = {} #: Hash[String, Integer]

      ##
      # An empty allocation with zero count and size.
      EMPTY = Allocation.new(0, 0, empty_sources.freeze).freeze

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
        trace(klasses, &)
      end

      ##
      # Counts retained allocations by class within a block.
      # Returns a Result. Runs GC after the block to identify
      # objects that survive garbage collection.

      def self.count_retained(klasses = [], &)
        trace(klasses, retain: true, &)
      end

      ##
      # Returns a Result of allocations from the given +generation+.
      # When +klasses+ are given, objects are matched via +is_a?+
      # and unmatched objects are tracked separately in +ignored+.

      def self.count_allocations(generation, klasses = [])
        allocated = {} #: Hash[untyped, Allocation]
        ignored = {} #: Hash[untyped, Allocation]
        total = new_allocation

        ObjectSpace.each_object do |obj|
          next unless ObjectSpace.allocation_generation(obj) == generation

          tally(obj, total, bucket_for(obj, klasses, allocated, ignored))
        end

        Result.new(allocated, ignored, total)
      end

      ##
      # Traces object allocations within a block, optionally
      # running GC to identify retained objects. Returns a Result.

      def self.trace(klasses, retain: false, &)
        # :nocov:
        return Result.new({}, {}, EMPTY) unless supported?
        # :nocov:

        GC.start
        GC.disable
        generation = GC.count
        ObjectSpace.trace_object_allocations(&)
        GC.start if retain
        count_allocations(generation, klasses)
      ensure
        GC.enable
      end
      private_class_method :trace

      ##
      # Tallies one object's count and byte size into both the
      # +total+ and per-class +bucket+ entries.

      def self.tally(obj, total, bucket)
        size = ObjectSpace.memsize_of(obj) - SLOT_SIZE
        total.count += 1
        total.size += size
        bucket.count += 1
        bucket.size += size
        record_source(obj, total, bucket)
      end
      private_class_method :tally

      ##
      # Records the source location of +obj+ into +total+ and
      # +bucket+ source hashes. Skips objects without source info.

      def self.record_source(obj, total, bucket)
        file = ObjectSpace.allocation_sourcefile(obj)
        # :nocov:
        return unless file
        # :nocov:

        source = "#{file}:#{ObjectSpace.allocation_sourceline(obj)}"
        total.sources[source] += 1
        bucket.sources[source] += 1
      end
      private_class_method :record_source

      ##
      # Finds or creates the Allocation entry for +obj+. When
      # +klasses+ are given, matches via +is_a?+ into +allocated+
      # or files into +ignored+.

      def self.bucket_for(obj, klasses, allocated, ignored)
        return allocated[obj.class] ||= new_allocation if klasses.empty?

        klass = klasses.find { |k| obj.is_a?(k) }
        return allocated[klass] ||= new_allocation if klass

        ignored[obj.class] ||= new_allocation
      end
      private_class_method :bucket_for

      ##
      # Creates a new zeroed Allocation with a default-value sources hash.

      def self.new_allocation
        Allocation.new(0, 0, Hash.new(0))
      end
      private_class_method :new_allocation
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

      check_limits(limits, result)

      return if has_total_limit

      result.ignored.each do |klass, alloc|
        msg = "Allocated #{alloc.count} #{klass} instances, #{alloc.size} bytes, " \
              "but it was not specified#{format_sources(alloc.sources)}"
        flunk msg
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
    #   assert_retentions(String => 0) { "hello" }
    #   assert_retentions(String => {count: 1, size: 1024}) { "hello" }

    def assert_retentions(limits, &)
      klasses = limits.keys.select { |k| k.is_a?(Module) }
      result = AllocationCounter.count_retained(klasses, &)

      check_limits(limits, result, metric: "retentions", size_metric: "retained bytes")
    end

    ##
    # Fails if any of the given +classes+ are allocated within a
    # block.
    #
    #   refute_allocations(String, Array) { 1 + 1 }

    def refute_allocations(*classes, &)
      check_zero(AllocationCounter.count(classes, &), classes)
    end

    ##
    # Fails if any of the given +classes+ are retained within a
    # block.
    #
    #   refute_retentions(String, Array) { 1 + 1 }

    def refute_retentions(*classes, &)
      check_zero(AllocationCounter.count_retained(classes, &), classes, metric: "retentions")
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
        ctx.assert_allocations(limits, &target)
      end

      ##
      # See Minitest::Memory#assert_retentions.
      #
      #   _ { code }.must_limit_retentions(String => 1)

      def must_limit_retentions(limits)
        ctx.assert_retentions(limits, &target)
      end

      ##
      # See Minitest::Memory#refute_allocations.
      #
      #   _ { code }.wont_allocate(String, Array)

      def wont_allocate(*classes)
        ctx.refute_allocations(*classes, &target)
      end

      ##
      # See Minitest::Memory#refute_retentions.
      #
      #   _ { code }.wont_retain(String, Array)

      def wont_retain(*classes)
        ctx.refute_retentions(*classes, &target)
      end
    end

    private

    ##
    # Checks all +limits+ entries against +result+. Routes +:count+
    # and +:size+ to total-limit checks, and Module keys to
    # per-class checks.

    def check_limits(limits, result, metric: "allocations", size_metric: "allocation bytes")
      limits.each do |klass, limit|
        check_limit_entry(klass, limit, result, metric: metric, size_metric: size_metric)
      end
    end

    ##
    # Dispatches a single +limit+ entry for the given +klass+
    # against the +result+. Routes symbols to total-limit checks
    # and Module keys to per-class checks.

    def check_limit_entry(klass, limit, result, metric:, size_metric:)
      case klass
      when :count, :size
        total_limit = limit #: Integer | Range[Integer]
        check_total_limit(klass, total_limit, result.total, size_metric: size_metric)
      when Module
        alloc = result.allocated[klass] || AllocationCounter::EMPTY
        check_class_limit(klass, alloc, limit, metric: metric, size_metric: size_metric)
      end
    end

    ##
    # Checks a total +:count+ or +:size+ limit against the
    # aggregate +total+ allocation.

    def check_total_limit(klass, limit, total, size_metric:)
      if klass == :count
        check_limit("total", limit, total.count, sources: total.sources)
      else
        check_limit("total", limit, total.size, metric: size_metric, sources: total.sources)
      end
    end

    ##
    # Checks per-class +limit+ against +allocation+ for the given
    # +klass+. +limit+ may be an Integer, Range, or Hash with
    # +:count+ and/or +:size+ keys.

    def check_class_limit(klass, allocation, limit, metric:, size_metric:)
      srcs = allocation.sources
      if limit.is_a?(Hash)
        check_limit(klass, limit.fetch(:count), allocation.count, metric: metric, sources: srcs) if limit.key?(:count)
        check_limit(klass, limit.fetch(:size), allocation.size, metric: size_metric, sources: srcs) if limit.key?(:size)
      else
        check_limit(klass, limit, allocation.count, metric: metric, sources: srcs)
      end
    end

    ##
    # Asserts that +actual+ matches +limit+ for the given +klass+
    # and +metric+. +limit+ may be an Integer (exact match) or a
    # Range (inclusion check).

    def check_limit(klass, limit, actual, sources:, metric: "allocations")
      if limit.is_a?(Range)
        msg = "Expected within #{limit} #{klass} #{metric}, got #{actual}#{format_sources(sources)}"
        assert_includes limit, actual, msg
      else
        desc = limit.zero? ? "no" : "exactly #{limit}"
        msg = "Expected #{desc} #{klass} #{metric}, got #{actual}#{format_sources(sources)}"
        assert_equal limit, actual, msg
      end
    end

    ##
    # Asserts zero allocations for each class in +classes+.

    def check_zero(result, classes, metric: "allocations")
      classes.each do |klass|
        alloc = result.allocated[klass] || AllocationCounter::EMPTY
        check_limit(klass, 0, alloc.count, metric: metric, sources: alloc.sources)
      end
    end

    ##
    # Formats allocation +sources+ as a newline-separated list
    # of source locations with counts, sorted by frequency.

    def format_sources(sources)
      return "" if sources.empty?

      entries = sources.sort_by { |_, count| -count }.map do |source, count|
        "  #{count}× at #{source}"
      end

      "\n#{entries.join("\n")}"
    end
  end
end
