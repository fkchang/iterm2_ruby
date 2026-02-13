# frozen_string_literal: true

require_relative "lib/iterm2/version"

Gem::Specification.new do |spec|
  spec.name = "iterm2_ruby"
  spec.version = ITerm2::VERSION
  spec.authors = ["Forrest Chang"]
  spec.summary = "Ruby bindings for iTerm2's native WebSocket+Protobuf API"
  spec.description = "Control iTerm2 via its native API. List sessions, send text, read screens, raise tabs — all without osascript."
  spec.homepage = "https://github.com/fkchang/iterm2_ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*.rb", "bin/*", "proto/*.proto", "README.md", "LICENSE", "*.gemspec", "Gemfile", "Rakefile", "llms.txt", "docs/**/*.md"]
  spec.bindir = "bin"
  spec.executables = ["iterm2ctl"]

  spec.add_dependency "google-protobuf", "~> 4.0"
  spec.add_dependency "base64"
  spec.add_dependency "ostruct"
end
