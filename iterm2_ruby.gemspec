# frozen_string_literal: true

require_relative "lib/iterm2/version"

Gem::Specification.new do |spec|
  spec.name = "iterm2_ruby"
  spec.version = ITerm2::VERSION
  spec.authors = ["Forrest Chang"]
  spec.summary = "Ruby bindings for iTerm2's native WebSocket+Protobuf API"
  spec.description = "Control iTerm2 via its native API: list sessions, send text, read screens, and raise tabs, all without osascript."
  spec.homepage = "https://github.com/fkchang/iterm2_ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "bin/*", "proto/*.proto", "README.md", "CHANGELOG.md", "LICENSE", "*.gemspec", "Gemfile", "Rakefile", "llms.txt", "docs/**/*.md"]
  spec.bindir = "bin"
  spec.executables = ["iterm2ctl"]

  # Required for encoding/decoding iTerm2 API protobuf frames.
  spec.add_dependency "google-protobuf", "~> 4.0"

  # WebSocket framing is hand-rolled in lib/iterm2/connection.rb, so no websocket gem is required.
  # base64/ostruct are stdlib in modern Ruby and intentionally not listed as gem dependencies.
end
