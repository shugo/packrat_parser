require_relative "lib/packrat_parser/version"

Gem::Specification.new do |spec|
  spec.name = "packrat_parser"
  spec.version = PackratParser::VERSION
  spec.authors = ["Shugo Maeda"]
  spec.email = ["shugo.maeda@gmail.com"]

  spec.summary = "A packrat / PEG parser-combinator library with a Scala-inspired API."
  spec.description = <<~DESC
    packrat_parser is a small PEG/packrat parser-combinator library. Grammar
    rules are plain methods that return parsers and can be written using the
    `for ... then` comprehension (flat_map/map/filter), giving a Scala-style
    for-comprehension feel.
  DESC
  spec.homepage = "https://github.com/shugo/packrat_parser"
  spec.license = "MIT"

  # The `for ... then` comprehension used by grammars requires the Ruby fork
  # built with the legacy parser (run with `--parser=parse.y`). The library
  # itself is plain Ruby.
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir["lib/**/*.rb", "examples/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "test-unit", "~> 3.0"
end
