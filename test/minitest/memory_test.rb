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

  # AllocationCounter.count

  def test_count_returns_hash
    result = Minitest::Memory::AllocationCounter.count { +"hello" }

    assert_instance_of Hash, result
  end

  def test_count_tracks_string_allocations
    result = Minitest::Memory::AllocationCounter.count { +"hello" }

    assert_operator result[String], :>=, 1
  end

  def test_count_tracks_array_allocations
    result = Minitest::Memory::AllocationCounter.count { [1, 2, 3] }

    assert_operator result[Array], :>=, 1
  end

  def test_count_returns_zero_for_unallocated_classes
    result = Minitest::Memory::AllocationCounter.count { nil }

    assert_equal 0, result[Float]
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

    assert_equal 1, result[Canary]
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

  # assert_allocations

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
