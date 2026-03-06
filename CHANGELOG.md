# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-06

### Added

- `Minitest::Memory::AllocationCounter.count` — counts object allocations by class within a block
- `assert_allocations` — fails if any class exceeds its allocation limit within a block
