require 'monitor'
require 'redis/errors'
require_relative 'breaker'
require_relative 'remote'
require_relative 'monitor'

module CircuitBreaker
  class ShortCircuitedError < StandardError; end

  class BreakerProxy
    attr_reader :request_timeout, :tolerable_errors

    def initialize(name, options={}, monitor)
      @name = name
      @options = {request_timeout: 1.0, tolerable_errors: [], monitor_sampling_fraction: 1.0}
      @options.merge!(options)
      @request_timeout = @options[:request_timeout]
      @tolerable_errors = @options[:tolerable_errors].dup
      @monitor_sampling_fraction = @options[:monitor_sampling_fraction]
      @monitor = monitor
      @state = :closed
    end

    def request
      allow = allow_request?
      state = allow ? :closed : :open
      #logger.warn("Circuit #{@name} changed the state to #{state}") if @state != state
      @state = state
      started_at = Time.now
      if allow
        begin
          v = yield
        rescue => e
          if @tolerable_errors.any? { |error_class| e.kind_of?(error_class) }
            handle_success(started_at)
          else
            record_failure
            monitor_request(Breaker::EVENT_FAILURE, started_at)
          end
          raise
        else
          handle_success(started_at)
          v
        end
      else
        record_short_circuited
        monitor_request(Breaker::EVENT_SHORT_CIRCUITED, started_at)
        raise ShortCircuitedError
      end
    end

    def handle_success(started_at)
      latency = Time.now - started_at
      if latency > @request_timeout
        record_timeout
        monitor_request(Breaker::EVENT_TIMEOUT, started_at)
      else
        record_success
        monitor_request(Breaker::EVENT_SUCCESS, started_at)
      end
    end

    def monitor_request(event, started_at)
      sample = @monitor_sampling_fraction == 1.0 || Random.rand < @monitor_sampling_fraction
      @monitor.record_request(@name, event, Time.now - started_at) if sample
    end
  end

  class InprocBreaker < BreakerProxy
    attr_reader :underlying

    def initialize(name, options={})
      super(name, options, NoopMonitor.new)
      @underlying = Breaker.new(@options)
    end

    def allow_request?
      @underlying.slide(Time.now.to_i)
      @underlying.allow_request?
    end

    def record_success
      @underlying.record_success
    end

    def record_failure
      @underlying.record_failure
    end

    def record_timeout
      @underlying.record_timeout
    end

    def record_short_circuited
      @underlying.record_short_circuited
    end

    def health
      @underlying.health
    end
  end

  class RemoteBreaker < BreakerProxy
    FALLBACK_HEALTH = Breaker::Health.new(0, 0, 0, 0)

    def initialize(name, options={}, monitor, client)
      super(name, options, monitor)
      @client = client
      install
    end

    def install
      resilient(nil) do
        @client.install(@name, @options)
      end
    end

    def allow_request?
      resilient(true) do
        @client.allow_request(@name)
      end
    end

    def record_success
      resilient(nil) do
        @client.record_success(@name)
      end
    end

    def record_failure
      resilient(nil) do
        @client.record_failure(@name)
      end
    end

    def record_timeout
      resilient(nil) do
        @client.record_timeout(@name)
      end
    end

    def record_short_circuited
      resilient(nil) do
        @client.record_short_circuited(@name)
      end
    end

    def health
      resilient(FALLBACK_HEALTH) do
        @client.health(@name)
      end
    end

    private

    def resilient(fallback)
      begin
        yield
      rescue
        #logger.error('CircuitBreaker is unreachable')
        fallback
      end
    end
  end

  class RespClient
    attr :client

    include MonitorMixin
    include CircuitBreaker::Remote

    def initialize(options = {})
      options = {timeout: 0.1, reconnect_attempt: 0}.merge!(options)
      @original_client = @client = Redis::Client.new(options)
      @queue = Hash.new { |h, k| h[k] = [] }
      super()
    end

    def synchronize
      mon_synchronize { yield(@client) }
    end

    def with_reconnect(val=true, &blk)
      synchronize do |client|
        client.with_reconnect(val, &blk)
      end
    end

    def without_reconnect(&blk)
      with_reconnect(false, &blk)
    end

    def connected?
      @original_client.connected?
    end

    def close
      @original_client.disconnect
    end
    alias disconnect! close

    def install(name, options)
      synchronize do |client|
        client.call([COMMAND_INSTALL, name] + options.to_a.flatten)
      end
    end

    def allow_request(name)
      synchronize do |client|
        client.call([COMMAND_ALLOW_REQUEST, name], &Boolify)
      end
    end

    def record(name, event)
      synchronize do |client|
        client.call([COMMAND_RECORD, name, event])
      end
    end

    def record_success(name)
      record(name, EVENT_SUCCESS)
    end

    def record_failure(name)
      record(name, EVENT_FAILURE)
    end

    def record_timeout(name)
      record(name, EVENT_TIMEOUT)
    end

    def record_short_circuited(name)
      record(name, EVENT_SHORT_CIRCUITED)
    end

    # Get the health metrics in a hash.
    #
    # @param [String] name
    # @return [Hash<String, Object>]
    def health(name)
      synchronize do |client|
        client.call([COMMAND_HEALTH, name], &Hashify)
      end
    end

    # Find all breakers.
    #
    # @return [Array<String>]
    def breakers()
      synchronize do |client|
        client.call([COMMAND_BREAKERS])
      end
    end

    # Ping the server.
    #
    # @return [String] `PONG`
    def ping
      synchronize do |client|
        client.call([COMMAND_PING])
      end
    end

    # Close the connection.
    #
    # @return [String] `OK`
    def quit
      synchronize do |client|
        begin
          client.call([COMMAND_QUIT])
        rescue ConnectionError
        ensure
          client.disconnect
        end
      end
    end

    def id
      @original_client.id
    end

    def inspect
      "#<CircuitBreaker::RespClient for #{id}>"
    end

    def dup
      self.class.new(@options)
    end

    private

    # Commands returning 1 for true and 0 for false may be executed in a pipeline
    # where the method call will return nil. Propagate the nil instead of falsely
    # returning false.
    Boolify =
        lambda { |value|
          value == 1 if value
        }

    BoolifySet =
        lambda { |value|
          if value && "OK" == value
            true
          else
            false
          end
        }

    Hashify =
        lambda { |array|
          hash = Hash.new
          array.each_slice(2) do |field, value|
            hash[field] = value
          end
          hash
        }

    Floatify =
        lambda { |str|
          if str
            if (inf = str.match(/^(-)?inf/i))
              (inf[1] ? -1.0 : 1.0) / 0.0
            else
              Float(str)
            end
          end
        }

    FloatifyPairs =
        lambda { |array|
          if array
            array.each_slice(2).map do |member, score|
              [member, Floatify.call(score)]
            end
          end
        }

  end
end

require "redis/connection"
require "redis/client"
