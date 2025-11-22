# frozen_string_literal: true

require_relative 'lib/macdev/version'

Gem::Specification.new do |spec|
  spec.name          = 'macdev'
  spec.version       = Macdev::VERSION
  spec.authors       = ['Kevin Marker']
  spec.email         = ['kmarker@gmail.com']

  spec.summary       = 'Project-isolated development environments on macOS using Homebrew'
  spec.description   = 'Create Nix-like isolated development environments on macOS using Homebrew, with support for pure (project-scoped) and impure (system-wide) packages'
  spec.homepage      = 'https://github.com/kmarker/macdev'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage

  spec.files = Dir['lib/**/*.rb', 'bin/*', 'README.md', 'LICENSE', 'CLAUDE.md']
  spec.bindir = 'bin'
  spec.executables = ['macdev']
  spec.require_paths = ['lib']

  spec.add_dependency 'toml-rb', '~> 3.0'

  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.60'
end
