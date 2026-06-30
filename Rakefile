require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  # Grammars in the tests use the `for ... then` comprehension, which only the
  # fork's legacy parser understands, so run the suite under --parser=parse.y.
  t.ruby_opts = ["--parser=parse.y"]
  t.libs = ["lib"]
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

task default: :test
