# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Minitest::Spec expectations — `must_limit_allocations`, `must_limit_retentions`, `wont_allocate`, and `wont_retain` (e.g. `_ { code }.must_limit_allocations(String => {count: 10})`)
- `assert_retentions` — track retained objects that survive GC, detecting potential memory leaks (e.g. `assert_retentions(String => 0)`)
- `refute_retentions` — fails if any of the given classes are retained after GC within a block
- Global allocation limits — `assert_allocations` now accepts `:count` and `:size` symbol keys for total limits across all classes (e.g. `assert_allocations(count: 10)`)
- Range-based limits — limits can be a Range (e.g. `String => 2..5`) to require allocations within a specific range, for both direct and hash-style `:count`/`:size` limits
- `refute_allocations` — fails if any of the given classes are allocated within a block
- Allocation size limits — `assert_allocations` now accepts hash limits with `:count` and/or `:size` keys (e.g. `String => { size: 1024 }`)

## [1.0.0] - 2026-03-06

### Added

- `Minitest::Memory::AllocationCounter.count` — counts object allocations by class within a block
- `assert_allocations` — fails if any class exceeds its allocation limit within a block
