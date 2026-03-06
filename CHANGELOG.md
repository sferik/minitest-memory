# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Range-based limits — limits can be a Range (e.g. `String => 2..5`) to require allocations within a specific range, for both direct and hash-style `:count`/`:size` limits
- `refute_allocations` — fails if any of the given classes are allocated within a block
- Allocation size limits — `assert_allocations` now accepts hash limits with `:count` and/or `:size` keys (e.g. `String => { size: 1024 }`)

## [1.0.0] - 2026-03-06

### Added

- `Minitest::Memory::AllocationCounter.count` — counts object allocations by class within a block
- `assert_allocations` — fails if any class exceeds its allocation limit within a block
