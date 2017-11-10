# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "circuit_breaker/version"

Gem::Specification.new do |spec|
  spec.name          = "circuitbreakerd"
  spec.version       = CircuitBreaker::VERSION
  spec.authors       = ["Park Eungju"]
  spec.email         = ["eungju@gmail.com"]

  spec.summary       = %q{A circuit breaker daemon}
  spec.description   = %q{Out-of-process circuit breaker daemon}
  spec.homepage      = ""

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "simplecov", "~> 0.14"
  spec.add_development_dependency "timecop", "~> 0.9"
  spec.add_runtime_dependency "eventmachine", "~> 1.2"
  spec.add_runtime_dependency "hiredis", "~> 0.6"
  spec.add_runtime_dependency "redis", "~> 3.2"
  spec.add_runtime_dependency "influxdb", "~> 0.3"
  spec.add_runtime_dependency "quantile", "~> 0.2.0"
  spec.add_runtime_dependency "daemons", "~> 1.2"
end
