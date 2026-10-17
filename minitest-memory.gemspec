require_relative "lib/minitest/memory/version"

Gem::Specification.new do |spec|
  spec.name = "minitest-memory"
  spec.version = Minitest::Memory::VERSION
  spec.authors = ["Erik Berlin"]
  spec.email = ["sferik@gmail.com"]
  spec.summary = "Memory allocation assertions for Minitest"
  spec.description = "Assertions and expectations that limit the objects a block allocates or retains, " \
                     "by count and size, with the source location of each allocation in failure messages."
  spec.homepage = "https://sferik.github.io/minitest-memory"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.metadata = {
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/sferik/minitest-memory",
    "bug_tracker_uri" => "https://github.com/sferik/minitest-memory/issues",
    "changelog_uri" => "https://github.com/sferik/minitest-memory/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://www.rubydoc.info/gems/minitest-memory"
  }

  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "CHANGELOG.md", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "minitest", ">= 5.21", "< 7"
  spec.add_dependency "minitest-strict", ">= 1.0"
end
