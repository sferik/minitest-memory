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

Use the `:count` and `:size` symbol keys to set limits on total allocations
across all classes:

```ruby
# Limit total object count across all classes
assert_allocations(count: 10) { ... }

# Limit total allocation bytes across all classes
assert_allocations(size: 1024) { ... }

# Limit both count and size
assert_allocations(count: 10, size: 1024) { ... }

# Ranges work too
assert_allocations(count: 5..10) { ... }

# Combine per-class and global limits
assert_allocations(String => 2, count: 10) { ... }
```

### Retained object tracking

Use `assert_retentions` to check which objects survive garbage collection,
detecting potential memory leaks:

> [!WARNING]
> Garbage collection is disabled while the block executes. Avoid long-running
> or memory-intensive code inside the block.

```ruby
# Limit retained String objects
assert_retentions(String => 1) { ... }

# Hash-style limits with count and size
assert_retentions(String => { count: 1, size: 1024 }) { ... }

# Range limits work too
assert_retentions(String => 1..5) { ... }
```

Use `refute_retentions` to prevent any retained objects of the given types:

```ruby
refute_retentions(String, Array) do
  # code that must not retain strings or arrays
end
```

### `refute_allocations`

Use `refute_allocations` to prevent any allocations of the given types:

```ruby
refute_allocations(String, Array) do
  # code that must not allocate strings or arrays
end
```

### Minitest::Spec

It also works with `Minitest::Spec`. Include `Minitest::Memory` in your spec
class to use both assertions and expectations:

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

#### Expectations

The following `must_*` / `wont_*` expectations are available:

```ruby
# Limit allocations per class (wraps assert_allocations)
_ { code }.must_limit_allocations(String => 2)
_ { code }.must_limit_allocations(String => { count: 2, size: 1024 })
_ { code }.must_limit_allocations(String => 2..5)

# Limit total allocations across all classes
_ { code }.must_limit_allocations(count: 10)
_ { code }.must_limit_allocations(count: 5..10, size: 1024)

# Limit retained objects (wraps assert_retentions)
_ { code }.must_limit_retentions(String => 1)
_ { code }.must_limit_retentions(String => { count: 1, size: 1024 })

# Prevent allocations of specific classes (wraps refute_allocations)
_ { code }.wont_allocate(String, Array)

# Prevent retained objects of specific classes (wraps refute_retentions)
_ { code }.wont_retain(String, Array)
```

## How It Works

`assert_allocations` uses `ObjectSpace.trace_object_allocations` to track
every object allocated during the block's execution. It then compares the
counts and sizes per class against the limits you provide. If any class
exceeds its limit, the assertion fails with a message that includes the
source location of each allocation, sorted by frequency:

```
Expected no String allocations, got 3
  2× at app/models/user.rb:42
  1× at lib/serializer.rb:18
```

## License

MIT
