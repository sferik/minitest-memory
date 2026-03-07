require "test_helper"

class TestMinitestMemory < Minitest::Test
  cover "Minitest::Memory*"

  AC = Minitest::Memory::AllocationCounter

  class DummyTest
    include Minitest::Assertions
    include Minitest::Memory

    attr_accessor :assertions

    def initialize
      self.assertions = 0
    end
  end

  class Canary; end # rubocop:disable Lint/EmptyClass
  class CanarySubclass < Canary; end
  class RangeSubclass < Range; end
  class HashSubclass < Hash; end

  TOTAL = {count: 0..10_000}.freeze

  def setup
    super

    @tc = DummyTest.new
  end

  # AllocationCounter::Allocation

  def test_allocation_has_count_and_size
    alloc = AC::Allocation.new(1, 100, {})

    assert_equal 1, alloc.count
    assert_equal 100, alloc.size
  end

  def test_allocation_has_sources
    sources = {"foo.rb:1" => 2}
    alloc = AC::Allocation.new(2, 100, sources)

    assert_equal sources, alloc.sources
  end

  # AllocationCounter constants

  def test_slot_size_is_positive
    assert_operator AC::SLOT_SIZE, :>, 0
  end

  def test_empty_allocation_is_zero
    empty = AC::EMPTY

    assert_equal 0, empty.count
    assert_equal 0, empty.size
    assert_equal({}, empty.sources)
  end

  # AllocationCounter::Result

  def test_result_has_allocated_ignored_and_total
    result = AC.count { nil }

    assert_respond_to result, :allocated
    assert_respond_to result, :ignored
    assert_respond_to result, :total
  end

  # AllocationCounter.supported?

  def test_supported_returns_true_on_cruby
    assert_predicate AC, :supported?
  end

  # AllocationCounter.count

  def test_count_returns_result_with_allocations
    result = AC.count { +"hello" }

    assert_instance_of AC::Result, result
    assert_instance_of AC::Allocation, result.allocated[String]
    assert_operator result.allocated[String].count, :>=, 1
  end

  def test_count_tracks_array_allocations
    result = AC.count { [1, 2, 3] }

    assert_operator result.allocated[Array].count, :>=, 1
  end

  def test_count_returns_nil_for_unallocated_classes
    result = AC.count { nil }

    assert_nil result.allocated[Float]
  end

  def test_count_tracks_allocation_size
    result = AC.count { +"a" * 10_000 }

    assert_operator result.allocated[String].size, :>, 0
  end

  def test_count_subtracts_slot_size_from_allocation
    result = AC.count { Canary.new }

    assert_equal 0, result.allocated[Canary].size
  end

  def test_count_increments_by_one_per_allocation
    result = AC.count { Canary.new }

    assert_equal 1, result.allocated[Canary].count
  end

  def test_count_tracks_allocation_sources
    result = AC.count { +"hello" }

    sources = result.allocated[String].sources

    assert_instance_of Hash, sources
    assert_predicate sources, :any?, "Expected allocation sources"
    assert sources.keys.all? { |k| k.match?(/\A.+:\d+\z/) }, "Expected file:line format"
  end

  def test_count_tracks_total_sources
    result = AC.count { Canary.new }

    assert_predicate result.total.sources, :any?, "Expected total allocation sources"
  end

  def test_count_disables_gc_during_block
    gc_disabled_in_block = nil

    AC.count do
      gc_disabled_in_block = GC.disable
    end

    assert gc_disabled_in_block
    GC.enable
  end

  def test_count_reenables_gc_after_block
    AC.count { nil }

    refute GC.disable
    GC.enable
  end

  def test_count_reenables_gc_on_error
    error = assert_raises(RuntimeError) do
      AC.count { raise "boom" } # rubocop:disable Lint/UnreachableLoop
    end

    assert_equal "boom", error.message
    refute GC.disable
    GC.enable
  end

  def test_count_runs_gc_before_counting
    gc_count_in_block = nil

    before = GC.count
    AC.count { gc_count_in_block = GC.count }

    assert_operator gc_count_in_block, :>, before
  end

  # AllocationCounter.count with klasses

  def test_count_with_klasses_groups_by_base_class
    result = AC.count([Canary]) { CanarySubclass.new }

    assert_equal 1, result.allocated[Canary].count
  end

  def test_count_with_klasses_puts_unmatched_in_ignored
    result = AC.count([Float]) { +"hello" }

    assert_predicate result.ignored, :any?, "Expected ignored allocations"
    assert_nil result.allocated[Float]
  end

  def test_count_with_klasses_tracks_total
    result = AC.count([Canary]) { Canary.new }

    assert_operator result.total.count, :>=, 1
  end

  # AllocationCounter.count_allocations

  def test_count_allocations_returns_empty_for_unknown_generation
    result = AC.count_allocations(-1)

    assert_instance_of AC::Result, result
    assert_empty result.allocated
    assert_equal 0, result.total.count
    assert_equal 0, result.total.size
  end

  def test_count_allocations_defaults_klasses_to_empty
    GC.start
    generation = GC.count
    ObjectSpace.trace_object_allocations { Canary.new }
    result = AC.count_allocations(generation)

    assert_operator result.total.count, :>=, 1
  end

  # AllocationCounter.count when unsupported

  def test_count_returns_empty_result_when_unsupported
    stub_unsupported do
      assert_empty_counter_result(AC.count { +"hello" })
    end
  end

  # AllocationCounter.count_retained

  def test_count_retained_returns_result_with_retained_objects
    _holder = nil
    result = AC.count_retained { _holder = Canary.new }

    assert_instance_of AC::Result, result
    assert_instance_of AC::Allocation, result.allocated[Canary]
    assert_equal 1, result.allocated[Canary].count
  end

  def test_count_retained_excludes_unreferenced_objects
    result = AC.count_retained do
      Canary.new
      nil
    end

    assert_nil result.allocated[Canary]
  end

  def test_count_retained_tracks_retained_size
    _holder = nil
    result = AC.count_retained { _holder = +"a" * 10_000 }

    assert_operator result.allocated[String].size, :>, 0
  end

  def test_count_retained_disables_gc_during_block
    gc_disabled_in_block = nil

    AC.count_retained do
      gc_disabled_in_block = GC.disable
    end

    assert gc_disabled_in_block
    GC.enable
  end

  def test_count_retained_reenables_gc_after_block
    AC.count_retained { nil }

    refute GC.disable
    GC.enable
  end

  def test_count_retained_reenables_gc_on_error
    error = assert_raises(RuntimeError) do
      AC.count_retained { raise "boom" }
    end

    assert_equal "boom", error.message
    refute GC.disable
    GC.enable
  end

  def test_count_retained_runs_gc_before_block
    gc_count_in_block = nil

    before = GC.count
    AC.count_retained { gc_count_in_block = GC.count }

    assert_operator gc_count_in_block, :>, before
  end

  # AllocationCounter.count_retained when unsupported

  def test_count_retained_returns_empty_result_when_unsupported
    stub_unsupported do
      assert_empty_counter_result(AC.count_retained { +"hello" })
    end
  end

  # assert_allocations (integer limit)

  def test_assert_allocations_passes_within_limits
    @tc.assert_allocations(String => 1..10, **TOTAL) { +"hello" }
  end

  def test_assert_allocations_passes_with_zero_limit
    @tc.assert_allocations(Float => 0, **TOTAL) { nil }
  end

  def test_assert_allocations_fails_when_exceeding
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => 0, **TOTAL) { +"hello" }
    end

    assert_match(/Expected no String allocations, got \d+/, err.message)
  end

  def test_assert_allocations_failure_includes_source_location
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => 0, **TOTAL) { +"hello" }
    end

    assert_match(/\d+× at .+:\d+/, err.message)
  end

  def test_assert_allocations_checks_multiple_classes
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => 0, Array => 0..100, **TOTAL) { [+"hello"] }
    end

    assert_match(/String/, err.message)
  end

  def test_assert_allocations_reports_limit_in_message
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 1, **TOTAL) { 2.times { Canary.new } }
    end

    assert_match(/Expected exactly 1 .* allocations/, err.message)
  end

  # assert_allocations (hash limit with size)

  def test_assert_allocations_passes_within_size_limit
    @tc.assert_allocations(String => {size: 0..100_000}, **TOTAL) { +"a" * 10_000 }
  end

  def test_assert_allocations_fails_when_exceeding_size_limit
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0}, **TOTAL) { +"a" * 10_000 }
    end

    assert_match(/Expected no String allocation bytes, got \d+/, err.message)
  end

  def test_assert_allocations_size_hash_failure_includes_source_location
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0}, **TOTAL) { +"a" * 10_000 }
    end

    assert_match(/\d+× at .+:\d+/, err.message)
  end

  def test_assert_allocations_size_reports_limit
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 1}, **TOTAL) { +"a" * 10_000 }
    end

    assert_match(/Expected exactly 1 .* allocation bytes, got \d+/, err.message)
  end

  # assert_allocations (hash limit with count)

  def test_assert_allocations_with_count_hash
    @tc.assert_allocations(String => {count: 1..10}, **TOTAL) { +"hello" }
  end

  def test_assert_allocations_fails_count_in_hash
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => {count: 0}, **TOTAL) { Canary.new }
    end

    assert_match(/Expected no .* allocations, got 1/, err.message)
  end

  def test_assert_allocations_count_hash_failure_includes_source_location
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => {count: 0}, **TOTAL) { Canary.new }
    end

    assert_match(/\d+× at .+:\d+/, err.message)
  end

  # assert_allocations (hash limit with both count and size)

  def test_assert_allocations_with_count_and_size
    @tc.assert_allocations(String => {count: 1..10, size: 0..100_000}, **TOTAL) { +"hello" }
  end

  def test_assert_allocations_size_only_does_not_check_count
    @tc.assert_allocations(Canary => {size: 0..100_000}, **TOTAL) { 10.times { Canary.new } }
  end

  def test_assert_allocations_count_only_hash_does_not_check_size
    @tc.assert_allocations(String => {count: 1..100}, **TOTAL) { +"a" * 10_000 }
  end

  # assert_allocations (range limit)

  def test_assert_allocations_passes_within_range
    @tc.assert_allocations(Canary => 1..3, **TOTAL) { 2.times { Canary.new } }
  end

  def test_assert_allocations_range_fails_below
    assert_raises(Minitest::Assertion) do
      @tc.assert_allocations(Canary => 3..5, **TOTAL) { 2.times { Canary.new } }
    end
  end

  def test_assert_allocations_range_fails_above
    assert_raises(Minitest::Assertion) do
      @tc.assert_allocations(Canary => 0..1, **TOTAL) { 2.times { Canary.new } }
    end
  end

  def test_assert_allocations_range_failure_message
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 3..5, **TOTAL) { 2.times { Canary.new } }
    end

    assert_match(/Expected within 3\.\.5 .*Canary allocations, got 2/, err.message)
  end

  def test_assert_allocations_range_failure_includes_source_location
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 3..5, **TOTAL) { 2.times { Canary.new } }
    end

    assert_match(/\d+× at .+:\d+/, err.message)
  end

  # assert_allocations (range limit in hash)

  def test_assert_allocations_range_count_in_hash
    @tc.assert_allocations(Canary => {count: 1..3}, **TOTAL) { 2.times { Canary.new } }
  end

  def test_assert_allocations_range_count_in_hash_fails
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => {count: 3..5}, **TOTAL) { Canary.new }
    end

    assert_match(/within 3\.\.5 .* allocations/, err.message)
  end

  def test_assert_allocations_range_size_in_hash
    @tc.assert_allocations(String => {size: 100..100_000}, **TOTAL) { +"a" * 10_000 }
  end

  def test_assert_allocations_range_size_in_hash_fails
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0..1}, **TOTAL) { +"a" * 10_000 }
    end

    assert_match(/within 0\.\.1 .* allocation bytes/, err.message)
  end

  # assert_allocations (total count limit)

  def test_assert_allocations_total_count_passes
    @tc.assert_allocations(count: 1..100) { Canary.new }
  end

  def test_assert_allocations_total_count_fails
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(count: 0) { Canary.new }
    end

    assert_match(/Expected no total allocations, got \d+/, err.message)
  end

  def test_assert_allocations_total_count_failure_includes_source_location
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(count: 0) { Canary.new }
    end

    assert_match(/\d+× at .+:\d+/, err.message)
  end

  # assert_allocations (total size limit)

  def test_assert_allocations_total_size_passes
    @tc.assert_allocations(size: 0..100_000) { +"a" * 10_000 }
  end

  def test_assert_allocations_total_size_fails
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(size: 0) { +"a" * 10_000 }
    end

    assert_match(/total allocation bytes/, err.message)
  end

  def test_assert_allocations_total_size_zero_with_zero_size_object
    @tc.assert_allocations(size: 0) { Canary.new }
  end

  # assert_allocations (total independence)

  def test_assert_allocations_total_count_only_skips_size
    @tc.assert_allocations(count: 1..100) { +"a" * 10_000 }
  end

  def test_assert_allocations_total_size_only_skips_count
    @tc.assert_allocations(size: 0..100_000) { 100.times { Canary.new } }
  end

  def test_assert_allocations_total_sums_counts
    @tc.assert_allocations(count: 50..1000) { 100.times { Canary.new } }
  end

  def test_assert_allocations_total_count_and_size
    @tc.assert_allocations(count: 1..100, size: 0..100_000) { +"hello" }
  end

  # assert_allocations (combined per-class and total)

  def test_assert_allocations_combined_per_class_and_total
    @tc.assert_allocations(Canary => 1, :count => 1..100) { Canary.new }
  end

  # assert_allocations (strict mode)

  def test_assert_allocations_strict_mode_fails_on_unspecified
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 0) { +"hello" }
    end

    assert_match(/but it was not specified/, err.message)
  end

  def test_assert_allocations_strict_mode_message_content
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Float => 0) { Canary.new }
    end

    assert_match(/Allocated 1 .*Canary instances, 0 bytes,/, err.message)
  end

  def test_assert_allocations_strict_mode_includes_source_location
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Float => 0) { Canary.new }
    end

    assert_match(/\d+× at .+:\d+/, err.message)
  end

  def test_assert_allocations_strict_mode_suppressed_by_count_limit
    @tc.assert_allocations(Canary => 0, :count => 0..10_000) { +"hello" }
  end

  def test_assert_allocations_strict_mode_suppressed_by_size_limit
    @tc.assert_allocations(Canary => 0, :size => 0..100_000) { +"hello" }
  end

  # assert_allocations (exact match semantics)

  def test_assert_allocations_exact_match_fails_when_below
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 5, **TOTAL) { Canary.new }
    end

    assert_match(/Expected exactly 5 .* allocations, got 1/, err.message)
  end

  # assert_allocations (subclass limits)

  def test_assert_allocations_accepts_range_subclass_limit
    @tc.assert_allocations(Canary => RangeSubclass.new(1, 3), **TOTAL) { 2.times { Canary.new } }
  end

  def test_assert_allocations_accepts_hash_subclass_limit
    @tc.assert_allocations(String => HashSubclass[:count, 1..10], **TOTAL) { +"hello" }
  end

  # assert_allocations (is_a? subclass matching)

  def test_assert_allocations_matches_subclasses_via_is_a
    @tc.assert_allocations(Canary => 1, **TOTAL) { CanarySubclass.new }
  end

  # assert_retentions (integer limit)

  def test_assert_retentions_passes_within_limits
    _holder = nil
    @tc.assert_retentions(Canary => 1) { _holder = Canary.new }
  end

  def test_assert_retentions_passes_zero_when_not_retained
    @tc.assert_retentions(Canary => 0) do
      Canary.new
      nil
    end
  end

  def test_assert_retentions_fails_when_exceeding
    _holder = nil
    err = assert_raises Minitest::Assertion do
      @tc.assert_retentions(Canary => 0) { _holder = Canary.new }
    end

    assert_match(/Expected no .*Canary retentions, got 1/, err.message)
  end

  def test_assert_retentions_failure_includes_source_location
    _holder = nil
    err = assert_raises Minitest::Assertion do
      @tc.assert_retentions(Canary => 0) { _holder = Canary.new }
    end

    assert_match(/\d+× at .+:\d+/, err.message)
  end

  # assert_retentions (per-class count)

  def test_assert_retentions_checks_per_class_count
    holders = []
    @tc.assert_retentions(Canary => 10..100) do
      10.times { holders << Canary.new }
    end
  end

  # assert_retentions (hash limit with count)

  def test_assert_retentions_count_hash
    _holder = nil
    @tc.assert_retentions(Canary => {count: 1}) { _holder = Canary.new }
  end

  def test_assert_retentions_count_hash_fails
    _holder = nil
    err = assert_raises Minitest::Assertion do
      @tc.assert_retentions(Canary => {count: 0}) { _holder = Canary.new }
    end

    assert_match(/Canary/, err.message)
    assert_match(/retentions/, err.message)
  end

  # assert_retentions (hash limit with size)

  def test_assert_retentions_size_hash
    _holder = nil
    @tc.assert_retentions(String => {size: 0..100_000}) { _holder = +"a" * 10_000 }
  end

  def test_assert_retentions_size_hash_fails
    _holder = nil
    err = assert_raises Minitest::Assertion do
      @tc.assert_retentions(String => {size: 0}) { _holder = +"a" * 10_000 }
    end

    assert_match(/String/, err.message)
    assert_match(/retained bytes/, err.message)
  end

  # assert_retentions (range limit)

  def test_assert_retentions_range
    _holder = nil
    @tc.assert_retentions(Canary => 1..5) { _holder = Canary.new }
  end

  # assert_retentions (subclass limits)

  def test_assert_retentions_accepts_hash_subclass_limit
    _holder = nil
    @tc.assert_retentions(Canary => HashSubclass[:count, 1..10]) { _holder = Canary.new }
  end

  # assert_retentions (is_a? subclass matching)

  def test_assert_retentions_matches_subclasses_via_is_a
    _holder = nil
    @tc.assert_retentions(Canary => 1) { _holder = CanarySubclass.new }
  end

  # assert_retentions (non-Module keys)

  def test_assert_retentions_ignores_non_module_keys
    _canary = nil
    _string = nil
    @tc.assert_retentions(Canary => 1, :foo => 0) do
      _canary = Canary.new
      _string = +"retained"
    end
  end

  # refute_allocations

  def test_refute_allocations_passes_with_no_allocations
    @tc.refute_allocations(Float) { +"hello" }
  end

  def test_refute_allocations_fails_when_class_allocated
    err = assert_raises Minitest::Assertion do
      @tc.refute_allocations(String) { +"hello" }
    end

    assert_match(/Expected no String allocations, got \d+/, err.message)
  end

  def test_refute_allocations_failure_includes_source_location
    err = assert_raises Minitest::Assertion do
      @tc.refute_allocations(String) { +"hello" }
    end

    assert_match(/\d+× at .+:\d+/, err.message)
  end

  def test_refute_allocations_checks_multiple_classes
    err = assert_raises Minitest::Assertion do
      @tc.refute_allocations(String, Array) { [+"hello"] }
    end

    assert_match(/String/, err.message)
  end

  def test_refute_allocations_only_fails_for_allocated_class
    err = assert_raises Minitest::Assertion do
      @tc.refute_allocations(Float, String) { +"hello" }
    end

    assert_match(/String/, err.message)
    assert_nil err.message.match(/Float/)
  end

  # refute_allocations (is_a? subclass matching)

  def test_refute_allocations_matches_subclasses_via_is_a
    err = assert_raises Minitest::Assertion do
      @tc.refute_allocations(Canary) { CanarySubclass.new }
    end

    assert_match(/Canary/, err.message)
  end

  # refute_retentions

  def test_refute_retentions_passes_when_not_retained
    @tc.refute_retentions(Canary) do
      Canary.new
      nil
    end
  end

  def test_refute_retentions_fails_when_retained
    _holder = nil
    err = assert_raises Minitest::Assertion do
      @tc.refute_retentions(Canary) { _holder = Canary.new }
    end

    assert_match(/Canary/, err.message)
    assert_match(/retentions/, err.message)
  end

  def test_refute_retentions_failure_includes_source_location
    _holder = nil
    err = assert_raises Minitest::Assertion do
      @tc.refute_retentions(Canary) { _holder = Canary.new }
    end

    assert_match(/\d+× at .+:\d+/, err.message)
  end

  # Expectations

  def expectation(target)
    Minitest::Expectation.new(target, @tc)
  end

  # must_limit_allocations

  def test_must_limit_allocations_passes
    expectation(proc { +"hello" }).must_limit_allocations(String => 1..10, **TOTAL)
  end

  def test_must_limit_allocations_fails
    err = assert_raises Minitest::Assertion do
      expectation(proc { +"hello" }).must_limit_allocations(String => 0, **TOTAL)
    end

    assert_match(/Expected no String allocations/, err.message)
  end

  def test_must_limit_allocations_total_count_passes
    expectation(proc { Canary.new }).must_limit_allocations(count: 1..100)
  end

  def test_must_limit_allocations_total_count_fails
    err = assert_raises Minitest::Assertion do
      expectation(proc { Canary.new }).must_limit_allocations(count: 0)
    end

    assert_match(/total allocations/, err.message)
  end

  # must_limit_retentions

  def test_must_limit_retentions_passes
    _holder = nil
    expectation(proc { _holder = Canary.new }).must_limit_retentions(Canary => 1)
  end

  def test_must_limit_retentions_fails
    _holder = nil
    err = assert_raises Minitest::Assertion do
      expectation(proc { _holder = Canary.new }).must_limit_retentions(Canary => 0)
    end

    assert_match(/Canary/, err.message)
  end

  # wont_allocate

  def test_wont_allocate_passes
    expectation(proc { +"hello" }).wont_allocate(Float)
  end

  def test_wont_allocate_fails
    err = assert_raises Minitest::Assertion do
      expectation(proc { +"hello" }).wont_allocate(String)
    end

    assert_match(/Expected no String allocations/, err.message)
  end

  # wont_retain

  def test_wont_retain_passes
    expectation(proc { Canary.new; nil }).wont_retain(Canary) # rubocop:disable Style/Semicolon
  end

  def test_wont_retain_fails
    _holder = nil
    err = assert_raises Minitest::Assertion do
      expectation(proc { _holder = Canary.new }).wont_retain(Canary)
    end

    assert_match(/Canary/, err.message)
  end

  private

  def stub_unsupported(&)
    original = AC.method(:supported?)
    AC.singleton_class.remove_method(:supported?)
    AC.define_singleton_method(:supported?) { false }
    yield
  ensure
    AC.singleton_class.remove_method(:supported?)
    AC.define_singleton_method(:supported?, &original)
  end

  def assert_empty_counter_result(result)
    assert_instance_of AC::Result, result
    assert_equal({}, result.allocated)
    assert_equal({}, result.ignored)
    assert_equal 0, result.total.count
    assert_equal 0, result.total.size
    assert_equal({}, result.total.sources)
  end
end
