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

### Range limits

Pass a Range to require allocations within a specific range:

```ruby
# Require between 2 and 5 String allocations
assert_allocations(String => 2..5) { ... }

# Range limits work with count and size in hashes too
assert_allocations(String => { count: 2..5 }) { ... }
assert_allocations(String => { size: 1024..4096 }) { ... }
```

### Size limits

Pass a Hash with `:count` and/or `:size` keys to constrain total bytes
allocated per class (beyond the base object slot size):

```ruby
# Limit total String bytes
assert_allocations(String => { size: 1024 }) { ... }

# Limit both count and size
assert_allocations(String => { count: 2, size: 1024 }) { ... }

# Count-only via hash (equivalent to String => 2)
assert_allocations(String => { count: 2 }) { ... }
```

### Global limits

Use `assert_total_allocations` to set limits on the total count or size
across all classes:

```ruby
# Limit total object count across all classes
assert_total_allocations(count: 10) { ... }

# Limit total allocation bytes across all classes
assert_total_allocations(size: 1024) { ... }

# Limit both count and size
assert_total_allocations(count: 10, size: 1024) { ... }

# Ranges work too
assert_total_allocations(count: 5..10) { ... }
```

### `refute_allocations`

Use `refute_allocations` to prevent any allocations of the given types:

```ruby
refute_allocations(String, Array) do
  # code that must not allocate strings or arrays
end
```

### Minitest::Spec

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
counts and sizes per class against the limits you provide. If any class
exceeds its limit, the assertion fails with a message like:

```
Expected at most 2 String allocations, got 3
Expected within 2..5 String allocations, got 1
Expected at most 1024 String allocation bytes, got 2048
Expected at most 10 total allocations, got 15
```

## License

MIT
