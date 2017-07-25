require 'securerandom'
require_relative 'client'

module CircuitBreaker
  module BreakerPanel
    @@client = nil
    @@logger = nil
    @@monitor = nil

    def self.initialize(client, logger, monitor)
      @@client = client
      @@logger = logger
      @@monitor = monitor
    end

    def install_breaker(name, options={})
      RemoteBreaker.new(name, options, @@logger, @@monitor, @@client)
    end

    def relay_through(target_method, breaker)
      guid = SecureRandom.uuid
      define_method("#{guid}") do |*args, &block|
        breaker.request {
          __send__("#{guid}_#{target_method}", *args, &block)
        }
      end
      alias_method "#{guid}_#{target_method}", target_method
      alias_method target_method, "#{guid}"
    end
  end
end
