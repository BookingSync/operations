require_relative 'lib/operations/version'

Gem::Specification.new do |spec|
  spec.name          = "operations"
  spec.version       = Operations::VERSION
  spec.authors       = ["Arkadiy Zabazhanov"]
  spec.email         = ["kinwizard@gmail.com"]

  spec.summary       = "Operations framework"
  spec.description   = "Operations framework"
  spec.homepage      = "https://github.com/BookingSync/operations"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/BookingSync/operations"
  spec.metadata["changelog_uri"] = "https://github.com/BookingSync/operations"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
