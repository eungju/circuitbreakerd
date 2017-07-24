require 'securerandom'
require_relative 'client'

module CircuitBreaker
  module BreakerPanel
    @@client = nil
    @@monitor = nil

    def self.initialize(client, monitor)
      @@client = client
      @@monitor = monitor
    end

    def install_breaker(name, options={})
      RemoteBreaker.new(name, options, @@monitor, @@client)
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
