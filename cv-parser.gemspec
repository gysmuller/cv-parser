# frozen_string_literal: true

require_relative "lib/cv_parser/version"

Gem::Specification.new do |spec|
  spec.name = "cv-parser"
  spec.version = CvParser::VERSION
  spec.authors = ["Gys Muller"]

  spec.summary = "A Ruby gem for parsing CVs/resumes using LLMs"
  spec.description = "CV Parser is a Ruby gem that extracts structured information from CVs and resumes in various formats using LLMs."
  spec.homepage = "https://github.com/gysmuller/cv-parser"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob("{bin,lib,exe}/**/*") + %w[LICENSE.txt README.md CHANGELOG.md]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "base64", "~> 0.2"          # Required for Ruby 3.4+ compatibility
  spec.add_dependency "faraday", "~> 2.0"         # HTTP client for Anthropic
  spec.add_dependency "faraday-multipart", "~> 1.0" # Multipart form support for file uploads
  spec.add_dependency "fiddle", "~> 1.1"          # Required for Ruby 3.5+ compatibility
  spec.add_dependency "json", "~> 2.6"            # JSON handling for CLI output
  spec.add_dependency "mime-types", "~> 3.5"      # MIME type detection for file uploads
  spec.add_dependency "rdoc", "~> 6.6"            # Required for Ruby 3.5+ compatibility
  spec.add_dependency "rexml", "~> 3.2"           # XML parsing for DOCX conversion
  spec.add_dependency "zlib", "~> 3.0"            # Compression support for DOCX conversion

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.57"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.metadata["rubygems_mfa_required"] = "true"
end
