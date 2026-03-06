# minitest-memory

Minitest assertions for tracking memory allocations. Verify that your code
allocates only the expected number of objects.

## Installation

Add to your Gemfile:

```ruby
gem "minitest-memory"
```

## Usage

Include `Minitest::Memory` in your test class, then use `assert_allocations`
to set upper bounds on object allocations within a block:

```ruby
require "minitest/autorun"
require "minitest/memory"

class MyTest < Minitest::Test
  include Minitest::Memory

  def test_no_string_allocations
    assert_allocations(String => 0) do
      # code that should not allocate strings
    end
  end

  def test_limited_allocations
    assert_allocations(String => 2, Array => 1) do
      # code that should allocate at most 2 Strings and 1 Array
    end
  end
end
```

Use `refute_allocations` to prevent any allocations of the given types:

```ruby
refute_allocations(String, Array) do
  # code that must not allocate strings or arrays
end
```

It also works with `Minitest::Spec`:

```ruby
require "minitest/autorun"
require "minitest/memory"

class Minitest::Spec
  include Minitest::Memory
end

describe MyClass do
  it "does not allocate strings" do
    assert_allocations(String => 0) do
      # code under test
    end
  end
end
```

## How It Works

`assert_allocations` uses `ObjectSpace.trace_object_allocations` to track
every object allocated during the block's execution. It then compares the
counts per class against the limits you provide. If any class exceeds its
limit, the assertion fails with a message like:

```
Expected at most 0 String allocations, got 3
```

## License

MIT
