require "bundler/gem_tasks"
require "rake/testtask"
require "rdoc/task"
require "standard/rake"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

RDoc::Task.new(:rdoc) do |t|
  t.rdoc_dir = "doc"
  t.rdoc_files.include("lib/**/*.rb")
  t.options << "--all"
end

desc "Check RDoc coverage"
task :rdoc_coverage do
  output = `rdoc -C lib 2>&1`
  puts output
  abort "RDoc coverage is not 100%" unless output.include?("100.00% documented")
end

desc "Run mutation tests"
task :mutant do
  system("bundle exec mutant run") || abort("Mutation testing failed!")
end

desc "Lint with RuboCop"
task :rubocop do
  system("bundle exec rubocop") || abort("RuboCop failed!")
end

desc "Lint with RuboCop and Standard Ruby"
task lint: %i[rubocop standard]

desc "Type check with Steep"
task :steep do
  system("bundle exec steep check") || abort("Type checking failed!")
end

task default: %i[test lint rdoc_coverage mutant steep]
