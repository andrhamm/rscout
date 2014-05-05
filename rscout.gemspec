# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rscout/version'

Gem::Specification.new do |spec|
  spec.name          = "rscout"
  spec.version       = Rscout::VERSION
  spec.authors       = ["Andrew Hammond (@andrhamm)"]
  spec.email         = ["andrew@evertrue.com"]
  spec.description   = %q{Integration tests with Rspec}
  spec.summary       = %q{Integration tests with Rspec}
  spec.homepage      = "https://github.com/andrhamm"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'json'
  spec.add_dependency 'dotenv-rails'
  spec.add_dependency 'thor'
  spec.add_dependency 'rspec', '~> 2.14.1'
  spec.add_dependency 'dotenv'
  spec.add_dependency 'hashie'
  spec.add_dependency 'pagerduty'
  spec.add_dependency 'syntax'
  spec.add_dependency 'mail'
  spec.add_dependency 'activesupport', '~> 4.0', '>= 4.0.2'

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
