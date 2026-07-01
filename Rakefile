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

desc "Run the packrat_parser vs racc vs parslet benchmark"
task :bench do
  # Regenerate the racc parser, then run under the fork's legacy parser (the
  # packrat_parser grammar uses `for ... then`). Needs the parslet gem.
  sh "racc -o benchmark/calc_racc.rb benchmark/calc.y"
  sh "ruby --parser=parse.y benchmark/bench.rb"
end

task default: :test
