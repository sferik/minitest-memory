require "test_helper"

class TestMinitestMemory < Minitest::Test
  cover "Minitest::Memory*"

  class DummyTest
    include Minitest::Assertions
    include Minitest::Memory

    attr_accessor :assertions

    def initialize
      self.assertions = 0
    end
  end

  def setup
    super

    @tc = DummyTest.new
  end

  # AllocationCounter::Allocation

  def test_allocation_has_count_and_size
    alloc = Minitest::Memory::AllocationCounter::Allocation.new(1, 100)

    assert_equal 1, alloc.count
    assert_equal 100, alloc.size
  end

  # AllocationCounter::SLOT_SIZE

  def test_slot_size_is_positive
    assert_operator Minitest::Memory::AllocationCounter::SLOT_SIZE, :>, 0
  end

  # AllocationCounter::EMPTY

  def test_empty_allocation_is_zero
    empty = Minitest::Memory::AllocationCounter::EMPTY

    assert_equal 0, empty.count
    assert_equal 0, empty.size
  end

  # AllocationCounter.count

  def test_count_returns_result
    result = Minitest::Memory::AllocationCounter.count { +"hello" }

    assert_instance_of Minitest::Memory::AllocationCounter::Result, result
  end

  def test_count_returns_allocation_values
    result = Minitest::Memory::AllocationCounter.count { +"hello" }

    assert_instance_of Minitest::Memory::AllocationCounter::Allocation, result.allocated[String]
  end

  def test_count_tracks_string_allocations
    result = Minitest::Memory::AllocationCounter.count { +"hello" }

    assert_operator result.allocated[String].count, :>=, 1
  end

  def test_count_tracks_array_allocations
    result = Minitest::Memory::AllocationCounter.count { [1, 2, 3] }

    assert_operator result.allocated[Array].count, :>=, 1
  end

  def test_count_returns_nil_for_unallocated_classes
    result = Minitest::Memory::AllocationCounter.count { nil }

    assert_nil result.allocated[Float]
  end

  def test_count_tracks_allocation_size
    result = Minitest::Memory::AllocationCounter.count { +"a" * 10_000 }

    assert_operator result.allocated[String].size, :>, 0
  end

  def test_count_subtracts_slot_size_from_allocation
    result = Minitest::Memory::AllocationCounter.count { Canary.new }

    assert_equal 0, result.allocated[Canary].size
  end

  def test_count_disables_gc_during_block
    gc_disabled_in_block = nil

    Minitest::Memory::AllocationCounter.count do
      gc_disabled_in_block = GC.disable
    end

    assert gc_disabled_in_block
    GC.enable
  end

  def test_count_reenables_gc_after_block
    Minitest::Memory::AllocationCounter.count { nil }

    refute GC.disable
    GC.enable
  end

  def test_count_reenables_gc_on_error
    error = assert_raises(RuntimeError) do
      Minitest::Memory::AllocationCounter.count { raise "boom" } # rubocop:disable Lint/UnreachableLoop
    end

    assert_equal "boom", error.message
    refute GC.disable
    GC.enable
  end

  def test_count_runs_gc_before_counting
    gc_count_in_block = nil

    before = GC.count
    Minitest::Memory::AllocationCounter.count do
      gc_count_in_block = GC.count
    end

    assert_operator gc_count_in_block, :>, before
  end

  class Canary; end # rubocop:disable Lint/EmptyClass

  def test_count_increments_by_one_per_allocation
    result = Minitest::Memory::AllocationCounter.count { Canary.new }

    assert_equal 1, result.allocated[Canary].count
  end

  # AllocationCounter.count_allocations

  def test_count_allocations_returns_result
    result = Minitest::Memory::AllocationCounter.count_allocations(-1)

    assert_instance_of Minitest::Memory::AllocationCounter::Result, result
  end

  def test_count_allocations_returns_empty_for_unknown_generation
    result = Minitest::Memory::AllocationCounter.count_allocations(-1)

    assert_empty result.allocated
    assert_equal 0, result.total.count
    assert_equal 0, result.total.size
  end

  def test_count_allocations_defaults_klasses_to_empty
    GC.start
    generation = GC.count
    ObjectSpace.trace_object_allocations { Canary.new }
    result = Minitest::Memory::AllocationCounter.count_allocations(generation)

    assert_operator result.total.count, :>=, 1
  end

  # assert_allocations (integer limit)

  def test_assert_allocations_passes_within_limits
    @tc.assert_allocations(String => 1..10, :count => 0..10_000) { +"hello" }
  end

  def test_assert_allocations_passes_with_zero_limit
    @tc.assert_allocations(Float => 0, :count => 0..10_000) { nil }
  end

  def test_assert_allocations_fails_when_exceeding
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => 0, :count => 0..10_000) { +"hello" }
    end

    assert_match(/Expected no String allocations/, err.message)
  end

  def test_assert_allocations_checks_multiple_classes
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => 0, Array => 0..100, :count => 0..10_000) do
        [+"hello", 1, 2, 3]
      end
    end

    assert_match(/String/, err.message)
  end

  def test_assert_allocations_reports_actual_count
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => 0, :count => 0..10_000) { +"hello" }
    end

    assert_match(/got \d+/, err.message)
  end

  def test_assert_allocations_reports_limit_in_message
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 1, :count => 0..10_000) { 2.times { Canary.new } }
    end

    assert_match(/Expected exactly 1 .* allocations/, err.message)
  end

  # assert_allocations (hash limit with size)

  def test_assert_allocations_passes_within_size_limit
    @tc.assert_allocations(String => {size: 0..100_000}, :count => 0..10_000) { +"a" * 10_000 }
  end

  def test_assert_allocations_fails_when_exceeding_size_limit
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0}, :count => 0..10_000) { +"a" * 10_000 }
    end

    assert_match(/allocation bytes/, err.message)
  end

  def test_assert_allocations_size_zero_message
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0}, :count => 0..10_000) { +"a" * 10_000 }
    end

    assert_match(/Expected no String allocation bytes/, err.message)
  end

  def test_assert_allocations_size_reports_limit
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 1}, :count => 0..10_000) { +"a" * 10_000 }
    end

    assert_match(/Expected exactly 1 .* allocation bytes/, err.message)
  end

  def test_assert_allocations_size_reports_actual
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0}, :count => 0..10_000) { +"a" * 10_000 }
    end

    assert_match(/got \d+/, err.message)
  end

  # assert_allocations (hash limit with count)

  def test_assert_allocations_with_count_hash
    @tc.assert_allocations(String => {count: 1..10}, :count => 0..10_000) { +"hello" }
  end

  def test_assert_allocations_fails_count_in_hash
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {count: 0}, :count => 0..10_000) { +"hello" }
    end

    assert_match(/Expected no String allocations/, err.message)
  end

  def test_assert_allocations_count_hash_reports_actual
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => {count: 0}, :count => 0..10_000) { Canary.new }
    end

    assert_match(/got 1/, err.message)
  end

  # assert_allocations (hash limit with both count and size)

  def test_assert_allocations_with_count_and_size
    @tc.assert_allocations(String => {count: 1..10, size: 0..100_000}, :count => 0..10_000) { +"hello" }
  end

  def test_assert_allocations_size_only_does_not_check_count
    @tc.assert_allocations(Canary => {size: 0..100_000}, :count => 0..10_000) { 10.times { Canary.new } }
  end

  def test_assert_allocations_count_only_hash_does_not_check_size
    @tc.assert_allocations(String => {count: 1..100}, :count => 0..10_000) { +"a" * 10_000 }
  end

  # assert_allocations (range limit)

  def test_assert_allocations_passes_within_range
    @tc.assert_allocations(Canary => 1..3, :count => 0..10_000) { 2.times { Canary.new } }
  end

  def test_assert_allocations_range_fails_below
    assert_raises(Minitest::Assertion) do
      @tc.assert_allocations(Canary => 3..5, :count => 0..10_000) { 2.times { Canary.new } }
    end
  end

  def test_assert_allocations_range_fails_above
    assert_raises(Minitest::Assertion) do
      @tc.assert_allocations(Canary => 0..1, :count => 0..10_000) { 2.times { Canary.new } }
    end
  end

  def test_assert_allocations_range_reports_actual
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 3..5, :count => 0..10_000) { 2.times { Canary.new } }
    end

    assert_match(/got 2/, err.message)
  end

  def test_assert_allocations_range_reports_limit
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 3..5, :count => 0..10_000) { Canary.new }
    end

    assert_match(/within 3\.\.5/, err.message)
  end

  def test_assert_allocations_range_reports_class
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 3..5, :count => 0..10_000) { Canary.new }
    end

    assert_match(/Canary/, err.message)
  end

  # assert_allocations (range limit in hash with count)

  def test_assert_allocations_range_count_in_hash
    @tc.assert_allocations(Canary => {count: 1..3}, :count => 0..10_000) { 2.times { Canary.new } }
  end

  def test_assert_allocations_range_count_in_hash_fails
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => {count: 3..5}, :count => 0..10_000) { Canary.new }
    end

    assert_match(/within 3\.\.5 .* allocations/, err.message)
  end

  # assert_allocations (range limit in hash with size)

  def test_assert_allocations_range_size_in_hash
    @tc.assert_allocations(String => {size: 100..100_000}, :count => 0..10_000) { +"a" * 10_000 }
  end

  def test_assert_allocations_range_size_in_hash_fails
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0..1}, :count => 0..10_000) { +"a" * 10_000 }
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

    assert_match(/total allocations/, err.message)
  end

  def test_assert_allocations_total_count_reports_actual
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(count: 0) { Canary.new }
    end

    assert_match(/got \d+/, err.message)
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

  # assert_allocations (total count only does not check size)

  def test_assert_allocations_total_count_only_skips_size
    @tc.assert_allocations(count: 1..100) { +"a" * 10_000 }
  end

  # assert_allocations (total size only does not check count)

  def test_assert_allocations_total_size_only_skips_count
    @tc.assert_allocations(size: 0..100_000) { 100.times { Canary.new } }
  end

  # assert_allocations (total count sums across instances)

  def test_assert_allocations_total_sums_counts
    @tc.assert_allocations(count: 50..1000) { 100.times { Canary.new } }
  end

  # assert_allocations (total count and size)

  def test_assert_allocations_total_count_and_size
    @tc.assert_allocations(count: 1..100, size: 0..100_000) { +"hello" }
  end

  # assert_allocations (total range limit)

  def test_assert_allocations_total_count_range
    @tc.assert_allocations(count: 1..100) { Canary.new }
  end

  # assert_allocations (combined per-class and total)

  def test_assert_allocations_combined_per_class_and_total
    @tc.assert_allocations(Canary => 1, :count => 1..100) { Canary.new }
  end

  # AllocationCounter.count_retained

  def test_count_retained_returns_result
    result = Minitest::Memory::AllocationCounter.count_retained { nil }

    assert_instance_of Minitest::Memory::AllocationCounter::Result, result
  end

  def test_count_retained_returns_allocation_values
    _holder = nil
    result = Minitest::Memory::AllocationCounter.count_retained { _holder = Canary.new }

    assert_instance_of Minitest::Memory::AllocationCounter::Allocation, result.allocated[Canary]
  end

  def test_count_retained_tracks_retained_objects
    _holder = nil
    result = Minitest::Memory::AllocationCounter.count_retained { _holder = Canary.new }

    assert_equal 1, result.allocated[Canary].count
  end

  def test_count_retained_excludes_unreferenced_objects
    result = Minitest::Memory::AllocationCounter.count_retained do
      Canary.new
      nil
    end

    assert_nil result.allocated[Canary]
  end

  def test_count_retained_tracks_retained_size
    _holder = nil
    result = Minitest::Memory::AllocationCounter.count_retained { _holder = +"a" * 10_000 }

    assert_operator result.allocated[String].size, :>, 0
  end

  def test_count_retained_disables_gc_during_block
    gc_disabled_in_block = nil

    Minitest::Memory::AllocationCounter.count_retained do
      gc_disabled_in_block = GC.disable
    end

    assert gc_disabled_in_block
    GC.enable
  end

  def test_count_retained_reenables_gc_after_block
    Minitest::Memory::AllocationCounter.count_retained { nil }

    refute GC.disable
    GC.enable
  end

  def test_count_retained_reenables_gc_on_error
    error = assert_raises(RuntimeError) do
      Minitest::Memory::AllocationCounter.count_retained { raise "boom" }
    end

    assert_equal "boom", error.message
    refute GC.disable
    GC.enable
  end

  def test_count_retained_runs_gc_before_block
    gc_count_in_block = nil

    before = GC.count
    Minitest::Memory::AllocationCounter.count_retained do
      gc_count_in_block = GC.count
    end

    assert_operator gc_count_in_block, :>, before
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

    assert_match(/retentions/, err.message)
  end

  def test_assert_retentions_reports_class
    _holder = nil
    err = assert_raises Minitest::Assertion do
      @tc.assert_retentions(Canary => 0) { _holder = Canary.new }
    end

    assert_match(/Canary/, err.message)
  end

  def test_assert_retentions_reports_actual
    _holder = nil
    err = assert_raises Minitest::Assertion do
      @tc.assert_retentions(Canary => 0) { _holder = Canary.new }
    end

    assert_match(/got 1/, err.message)
  end

  def test_assert_retentions_zero_limit_message
    _holder = nil
    err = assert_raises Minitest::Assertion do
      @tc.assert_retentions(Canary => 0) { _holder = Canary.new }
    end

    assert_match(/Expected no .* retentions/, err.message)
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

  # assert_retentions with hash subclass limit

  def test_assert_retentions_accepts_hash_subclass_limit
    _holder = nil
    limit = HashSubclass[:count, 1..10]
    @tc.assert_retentions(Canary => limit) { _holder = Canary.new }
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
  end

  # assert_allocations with range subclass limit

  class RangeSubclass < Range; end

  def test_assert_allocations_accepts_range_subclass_limit
    limit = RangeSubclass.new(1, 3)
    @tc.assert_allocations(Canary => limit, :count => 0..10_000) { 2.times { Canary.new } }
  end

  # assert_allocations with hash subclass limit

  class HashSubclass < Hash; end

  def test_assert_allocations_accepts_hash_subclass_limit
    limit = HashSubclass[:count, 1..10]
    @tc.assert_allocations(String => limit, :count => 0..10_000) { +"hello" }
  end

  # refute_allocations

  def test_refute_allocations_passes_with_no_allocations
    @tc.refute_allocations(Float) { +"hello" }
  end

  def test_refute_allocations_fails_when_class_allocated
    err = assert_raises Minitest::Assertion do
      @tc.refute_allocations(String) { +"hello" }
    end

    assert_match(/Expected no String allocations/, err.message)
  end

  def test_refute_allocations_checks_multiple_classes
    err = assert_raises Minitest::Assertion do
      @tc.refute_allocations(String, Array) { [+"hello"] }
    end

    assert_match(/String/, err.message)
  end

  def test_refute_allocations_reports_actual_count
    err = assert_raises Minitest::Assertion do
      @tc.refute_allocations(String) { +"hello" }
    end

    assert_match(/got \d+/, err.message)
  end

  # Expectations

  def expectation(target)
    Minitest::Expectation.new(target, @tc)
  end

  # must_limit_allocations

  def test_must_limit_allocations_passes_within_limits
    expectation(proc { +"hello" }).must_limit_allocations(String => 1..10, :count => 0..10_000)
  end

  def test_must_limit_allocations_fails_when_exceeding
    err = assert_raises Minitest::Assertion do
      expectation(proc { +"hello" }).must_limit_allocations(String => 0, :count => 0..10_000)
    end

    assert_match(/Expected no String allocations/, err.message)
  end

  # must_limit_allocations (total limits)

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

  def test_must_limit_retentions_passes_within_limits
    _holder = nil
    expectation(proc { _holder = Canary.new }).must_limit_retentions(Canary => 1)
  end

  def test_must_limit_retentions_fails_when_exceeding
    _holder = nil
    err = assert_raises Minitest::Assertion do
      expectation(proc { _holder = Canary.new }).must_limit_retentions(Canary => 0)
    end

    assert_match(/Canary/, err.message)
  end

  # wont_allocate

  def test_wont_allocate_passes_with_no_allocations
    expectation(proc { +"hello" }).wont_allocate(Float)
  end

  def test_wont_allocate_fails_when_class_allocated
    err = assert_raises Minitest::Assertion do
      expectation(proc { +"hello" }).wont_allocate(String)
    end

    assert_match(/Expected no String allocations/, err.message)
  end

  # wont_retain

  def test_wont_retain_passes_when_not_retained
    expectation(proc { Canary.new; nil }).wont_retain(Canary) # rubocop:disable Style/Semicolon
  end

  def test_wont_retain_fails_when_retained
    _holder = nil
    err = assert_raises Minitest::Assertion do
      expectation(proc { _holder = Canary.new }).wont_retain(Canary)
    end

    assert_match(/Canary/, err.message)
  end

  # is_a? subclass matching

  class CanarySubclass < Canary; end

  def test_assert_allocations_matches_subclasses_via_is_a
    @tc.assert_allocations(Canary => 1, :count => 0..10_000) { CanarySubclass.new }
  end

  def test_assert_retentions_matches_subclasses_via_is_a
    _holder = nil
    @tc.assert_retentions(Canary => 1) { _holder = CanarySubclass.new }
  end

  def test_refute_allocations_matches_subclasses_via_is_a
    err = assert_raises Minitest::Assertion do
      @tc.refute_allocations(Canary) { CanarySubclass.new }
    end

    assert_match(/Canary/, err.message)
  end

  # strict mode (unspecified allocations)

  def test_assert_allocations_strict_mode_fails_on_unspecified
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 0) { +"hello" }
    end

    assert_match(/but it was not specified/, err.message)
  end

  def test_assert_allocations_strict_mode_suppressed_by_total_limit
    @tc.assert_allocations(Canary => 0, :count => 0..10_000) { +"hello" }
  end

  # exact match semantics

  def test_assert_allocations_exact_match_fails_when_below
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 5, :count => 0..10_000) { Canary.new }
    end

    assert_match(/Expected exactly 5 .* allocations, got 1/, err.message)
  end

  # AllocationCounter::Result

  def test_result_has_allocated_ignored_and_total
    result = Minitest::Memory::AllocationCounter.count { nil }

    assert_respond_to result, :allocated
    assert_respond_to result, :ignored
    assert_respond_to result, :total
  end

  # AllocationCounter.count with klasses

  def test_count_with_klasses_groups_by_base_class
    result = Minitest::Memory::AllocationCounter.count([Canary]) { CanarySubclass.new }

    assert_equal 1, result.allocated[Canary].count
  end

  def test_count_with_klasses_puts_unmatched_in_ignored
    result = Minitest::Memory::AllocationCounter.count([Float]) { +"hello" }

    assert_predicate result.ignored, :any?, "Expected ignored allocations"
    assert_nil result.allocated[Float]
  end

  def test_count_with_klasses_tracks_total
    result = Minitest::Memory::AllocationCounter.count([Canary]) { Canary.new }

    assert_operator result.total.count, :>=, 1
  end

  # AllocationCounter.supported?

  def test_supported_returns_true_on_cruby
    assert_predicate Minitest::Memory::AllocationCounter, :supported?
  end

  # AllocationCounter.count when unsupported

  def test_count_returns_empty_result_when_unsupported
    ac = Minitest::Memory::AllocationCounter
    original = ac.method(:supported?)
    ac.singleton_class.remove_method(:supported?)
    ac.define_singleton_method(:supported?) { false }

    assert_empty_counter_result(ac.count { +"hello" })
  ensure
    ac.singleton_class.remove_method(:supported?)
    ac.define_singleton_method(:supported?, &original)
  end

  # AllocationCounter.count_retained when unsupported

  def test_count_retained_returns_empty_result_when_unsupported
    ac = Minitest::Memory::AllocationCounter
    original = ac.method(:supported?)
    ac.singleton_class.remove_method(:supported?)
    ac.define_singleton_method(:supported?) { false }

    assert_empty_counter_result(ac.count_retained { +"hello" })
  ensure
    ac.singleton_class.remove_method(:supported?)
    ac.define_singleton_method(:supported?, &original)
  end

  def assert_empty_counter_result(result)
    assert_instance_of Minitest::Memory::AllocationCounter::Result, result
    assert_equal({}, result.allocated)
    assert_equal({}, result.ignored)
    assert_equal 0, result.total.count
    assert_equal 0, result.total.size
  end

  # assert_allocations strict mode suppressed by size-only total limit

  def test_assert_allocations_strict_mode_suppressed_by_size_only
    @tc.assert_allocations(Canary => 0, :size => 0..100_000) { +"hello" }
  end

  # assert_allocations strict mode message content

  def test_assert_allocations_strict_mode_message_includes_count
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Float => 0) { Canary.new }
    end

    assert_match(/Allocated 1 /, err.message)
  end

  def test_assert_allocations_strict_mode_message_includes_class
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Float => 0) { Canary.new }
    end

    assert_match(/Canary instances/, err.message)
  end

  def test_assert_allocations_strict_mode_message_includes_size
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Float => 0) { Canary.new }
    end

    assert_match(/, 0 bytes,/, err.message)
  end

  # assert_retentions filters non-Module keys from klasses

  def test_assert_retentions_ignores_non_module_keys
    _canary = nil
    _string = nil
    @tc.assert_retentions(Canary => 1, :foo => 0) do
      _canary = Canary.new
      _string = +"retained"
    end
  end
end
