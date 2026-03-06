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

  def test_count_returns_hash
    result = Minitest::Memory::AllocationCounter.count { +"hello" }

    assert_instance_of Hash, result
  end

  def test_count_returns_allocation_values
    result = Minitest::Memory::AllocationCounter.count { +"hello" }

    assert_instance_of Minitest::Memory::AllocationCounter::Allocation, result[String]
  end

  def test_count_tracks_string_allocations
    result = Minitest::Memory::AllocationCounter.count { +"hello" }

    assert_operator result[String].count, :>=, 1
  end

  def test_count_tracks_array_allocations
    result = Minitest::Memory::AllocationCounter.count { [1, 2, 3] }

    assert_operator result[Array].count, :>=, 1
  end

  def test_count_returns_nil_for_unallocated_classes
    result = Minitest::Memory::AllocationCounter.count { nil }

    assert_nil result[Float]
  end

  def test_count_tracks_allocation_size
    result = Minitest::Memory::AllocationCounter.count { +"a" * 10_000 }

    assert_operator result[String].size, :>, 0
  end

  def test_count_subtracts_slot_size_from_allocation
    result = Minitest::Memory::AllocationCounter.count { Canary.new }

    assert_equal 0, result[Canary].size
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

    assert_equal 1, result[Canary].count
  end

  # AllocationCounter.count_allocations

  def test_count_allocations_returns_hash
    result = Minitest::Memory::AllocationCounter.count_allocations(-1)

    assert_instance_of Hash, result
  end

  def test_count_allocations_returns_empty_for_unknown_generation
    result = Minitest::Memory::AllocationCounter.count_allocations(-1)

    assert_empty result
  end

  # assert_allocations (integer limit)

  def test_assert_allocations_passes_within_limits
    @tc.assert_allocations(String => 10) { +"hello" }
  end

  def test_assert_allocations_passes_with_zero_limit
    @tc.assert_allocations(Float => 0) { nil }
  end

  def test_assert_allocations_fails_when_exceeding
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => 0) { +"hello" }
    end

    assert_match(/Expected no String allocations/, err.message)
  end

  def test_assert_allocations_checks_multiple_classes
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => 0, Array => 100) do
        [+"hello", 1, 2, 3]
      end
    end

    assert_match(/String/, err.message)
  end

  def test_assert_allocations_reports_actual_count
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => 0) { +"hello" }
    end

    assert_match(/got \d+/, err.message)
  end

  def test_assert_allocations_reports_limit_in_message
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 1) { 2.times { Canary.new } }
    end

    assert_match(/Expected at most 1 .* allocations/, err.message)
  end

  # assert_allocations (hash limit with size)

  def test_assert_allocations_passes_within_size_limit
    @tc.assert_allocations(String => {size: 100_000}) { +"a" * 10_000 }
  end

  def test_assert_allocations_fails_when_exceeding_size_limit
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0}) { +"a" * 10_000 }
    end

    assert_match(/allocation bytes/, err.message)
  end

  def test_assert_allocations_size_zero_message
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0}) { +"a" * 10_000 }
    end

    assert_match(/Expected no String allocation bytes/, err.message)
  end

  def test_assert_allocations_size_reports_limit
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 1}) { +"a" * 10_000 }
    end

    assert_match(/Expected at most 1 .* allocation bytes/, err.message)
  end

  def test_assert_allocations_size_reports_actual
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0}) { +"a" * 10_000 }
    end

    assert_match(/got \d+/, err.message)
  end

  # assert_allocations (hash limit with count)

  def test_assert_allocations_with_count_hash
    @tc.assert_allocations(String => {count: 10}) { +"hello" }
  end

  def test_assert_allocations_fails_count_in_hash
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {count: 0}) { +"hello" }
    end

    assert_match(/Expected no String allocations/, err.message)
  end

  def test_assert_allocations_count_hash_reports_actual
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => {count: 0}) { Canary.new }
    end

    assert_match(/got 1/, err.message)
  end

  # assert_allocations (hash limit with both count and size)

  def test_assert_allocations_with_count_and_size
    @tc.assert_allocations(String => {count: 10, size: 100_000}) { +"hello" }
  end

  def test_assert_allocations_size_only_does_not_check_count
    @tc.assert_allocations(Canary => {size: 100_000}) { 10.times { Canary.new } }
  end

  def test_assert_allocations_count_only_hash_does_not_check_size
    @tc.assert_allocations(String => {count: 100}) { +"a" * 10_000 }
  end

  # assert_allocations (range limit)

  def test_assert_allocations_passes_within_range
    @tc.assert_allocations(Canary => 1..3) { 2.times { Canary.new } }
  end

  def test_assert_allocations_range_fails_below
    assert_raises(Minitest::Assertion) do
      @tc.assert_allocations(Canary => 3..5) { 2.times { Canary.new } }
    end
  end

  def test_assert_allocations_range_fails_above
    assert_raises(Minitest::Assertion) do
      @tc.assert_allocations(Canary => 0..1) { 2.times { Canary.new } }
    end
  end

  def test_assert_allocations_range_reports_actual
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 3..5) { 2.times { Canary.new } }
    end

    assert_match(/got 2/, err.message)
  end

  def test_assert_allocations_range_reports_limit
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 3..5) { Canary.new }
    end

    assert_match(/within 3\.\.5/, err.message)
  end

  def test_assert_allocations_range_reports_class
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => 3..5) { Canary.new }
    end

    assert_match(/Canary/, err.message)
  end

  # assert_allocations (range limit in hash with count)

  def test_assert_allocations_range_count_in_hash
    @tc.assert_allocations(Canary => {count: 1..3}) { 2.times { Canary.new } }
  end

  def test_assert_allocations_range_count_in_hash_fails
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(Canary => {count: 3..5}) { Canary.new }
    end

    assert_match(/within 3\.\.5 .* allocations/, err.message)
  end

  # assert_allocations (range limit in hash with size)

  def test_assert_allocations_range_size_in_hash
    @tc.assert_allocations(String => {size: 100..100_000}) { +"a" * 10_000 }
  end

  def test_assert_allocations_range_size_in_hash_fails
    err = assert_raises Minitest::Assertion do
      @tc.assert_allocations(String => {size: 0..1}) { +"a" * 10_000 }
    end

    assert_match(/within 0\.\.1 .* allocation bytes/, err.message)
  end

  # assert_total_allocations (count limit)

  def test_assert_total_allocations_count_passes
    @tc.assert_total_allocations(count: 100) { Canary.new }
  end

  def test_assert_total_allocations_count_fails
    err = assert_raises Minitest::Assertion do
      @tc.assert_total_allocations(count: 0) { Canary.new }
    end

    assert_match(/total allocations/, err.message)
  end

  def test_assert_total_allocations_count_reports_actual
    err = assert_raises Minitest::Assertion do
      @tc.assert_total_allocations(count: 0) { Canary.new }
    end

    assert_match(/got \d+/, err.message)
  end

  # assert_total_allocations (size limit)

  def test_assert_total_allocations_size_passes
    @tc.assert_total_allocations(size: 100_000) { +"a" * 10_000 }
  end

  def test_assert_total_allocations_size_fails
    err = assert_raises Minitest::Assertion do
      @tc.assert_total_allocations(size: 0) { +"a" * 10_000 }
    end

    assert_match(/total allocation bytes/, err.message)
  end

  def test_assert_total_allocations_size_zero_with_zero_size_object
    @tc.assert_total_allocations(size: 0) { Canary.new }
  end

  # assert_total_allocations (count only does not check size)

  def test_assert_total_allocations_count_only_skips_size
    @tc.assert_total_allocations(count: 100) { +"a" * 10_000 }
  end

  # assert_total_allocations (size only does not check count)

  def test_assert_total_allocations_size_only_skips_count
    @tc.assert_total_allocations(size: 100_000) { 100.times { Canary.new } }
  end

  # assert_total_allocations (count sums across instances)

  def test_assert_total_allocations_sums_counts
    @tc.assert_total_allocations(count: 50..1000) { 100.times { Canary.new } }
  end

  # assert_total_allocations (count and size)

  def test_assert_total_allocations_count_and_size
    @tc.assert_total_allocations(count: 100, size: 100_000) { +"hello" }
  end

  # assert_total_allocations (range limit)

  def test_assert_total_allocations_count_range
    @tc.assert_total_allocations(count: 1..100) { Canary.new }
  end

  # AllocationCounter.count_retained

  def test_count_retained_returns_hash
    result = Minitest::Memory::AllocationCounter.count_retained { nil }

    assert_instance_of Hash, result
  end

  def test_count_retained_returns_allocation_values
    _holder = nil
    result = Minitest::Memory::AllocationCounter.count_retained { _holder = Canary.new }

    assert_instance_of Minitest::Memory::AllocationCounter::Allocation, result[Canary]
  end

  def test_count_retained_tracks_retained_objects
    _holder = nil
    result = Minitest::Memory::AllocationCounter.count_retained { _holder = Canary.new }

    assert_equal 1, result[Canary].count
  end

  def test_count_retained_excludes_unreferenced_objects
    result = Minitest::Memory::AllocationCounter.count_retained do
      Canary.new
      nil
    end

    assert_nil result[Canary]
  end

  def test_count_retained_tracks_retained_size
    _holder = nil
    result = Minitest::Memory::AllocationCounter.count_retained { _holder = +"a" * 10_000 }

    assert_operator result[String].size, :>, 0
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
    @tc.assert_retentions(String => {size: 100_000}) { _holder = +"a" * 10_000 }
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
    limit = HashSubclass[:count, 10]
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
    @tc.assert_allocations(Canary => limit) { 2.times { Canary.new } }
  end

  # assert_allocations with hash subclass limit

  class HashSubclass < Hash; end

  def test_assert_allocations_accepts_hash_subclass_limit
    limit = HashSubclass[:count, 10]
    @tc.assert_allocations(String => limit) { +"hello" }
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
end
