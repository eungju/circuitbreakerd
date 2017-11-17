require 'monitor'
require 'redis/errors'
require_relative 'breaker'
require_relative 'remote'
require_relative 'monitor'

module CircuitBreaker
  class ShortCircuitedError < StandardError; end

  class BreakerProxy
    attr_reader :request_timeout, :tolerable_errors

    def initialize(name, options, logger, monitor)
      @name = name
      @options = {request_timeout: 1.0, tolerable_errors: [], monitor_sampling_fraction: 1.0}
      @options.merge!(options)
      @request_timeout = @options[:request_timeout]
      @tolerable_errors = @options[:tolerable_errors].dup
      @monitor_sampling_fraction = @options[:monitor_sampling_fraction]
      @logger = logger
      @monitor = monitor
      @state = :closed
    end

    def request
      allow = allow_request?
      state = allow ? :closed : :open
      @logger.warn("Circuit #{@name} changed the state to #{state}") if @state != state
      @state = state
      started_at = Time.now
      if allow
        begin
          v = yield
        rescue => e
          if @tolerable_errors.any? { |error_class| e.kind_of?(error_class) }
            handle_success(started_at)
          else
            record_failure(Time.now - started_at)
            monitor_request(Breaker::EVENT_FAILURE, started_at)
          end
          raise
        else
          handle_success(started_at)
          v
        end
      else
        record_short_circuited()
        monitor_request(Breaker::EVENT_SHORT_CIRCUITED, started_at)
        raise ShortCircuitedError, "#@name is open"
      end
    end

    def handle_success(started_at)
      latency = Time.now - started_at
      if latency > @request_timeout
        record_timeout(latency)
        monitor_request(Breaker::EVENT_TIMEOUT, started_at)
      else
        record_success(latency)
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

    def initialize(name, options, logger, monitor)
      super(name, options, logger, monitor)
      @underlying = Breaker.new(@options)
    end

    def allow_request?
      @underlying.slide(Time.now.to_i)
      @underlying.allow_request?
    end

    def record_success(latency)
      @underlying.record_success(latency)
    end

    def record_failure(latency)
      @underlying.record_failure(latency)
    end

    def record_timeout(latency)
      @underlying.record_timeout(latency)
    end

    def record_short_circuited
      @underlying.record_short_circuited()
    end

    def metrics
      @underlying.metrics
    end
  end

  class RemoteBreaker < BreakerProxy
    FALLBACK_METRICS = Breaker::Metrics.new(0, 0, 0, 0, 0, 0, {})

    def initialize(name, options, logger, monitor, client)
      super(name, options, logger, monitor)
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

    def record_success(latency)
      resilient(nil) do
        @client.record_success(@name, latency)
      end
    end

    def record_failure(latency)
      resilient(nil) do
        @client.record_failure(@name, latency)
      end
    end

    def record_timeout(latency)
      resilient(nil) do
        @client.record_timeout(@name, latency)
      end
    end

    def record_short_circuited
      resilient(nil) do
        @client.record_short_circuited(@name)
      end
    end

    def metrics
      resilient(FALLBACK_METRICS) do
        @client.metrics(@name)
      end
    end

    private

    def resilient(fallback)
      begin
        yield
      rescue
        @logger.error('CircuitBreaker is unreachable')
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

    def record(name, event, latency)
      synchronize do |client|
        client.call([COMMAND_RECORD, name, event, latency])
      end
    end

    def record_success(name, latency)
      record(name, EVENT_SUCCESS, latency)
    end

    def record_failure(name, latency)
      record(name, EVENT_FAILURE, latency)
    end

    def record_timeout(name, latency)
      record(name, EVENT_TIMEOUT, latency)
    end

    def record_short_circuited(name)
      record(name, EVENT_SHORT_CIRCUITED, 0)
    end

    # Get the metrics in a hash.
    #
    # @param [String] name
    # @return [Hash<String, Object>]
    def metrics(name)
      synchronize do |client|
        r = client.call([COMMAND_METRICS, name], &Hashify)
        latency_buckets = Hash.new
        r[LATENCY_BUCKETS].each_slice(2) do |field, value|
          latency_buckets[Floatify.call(field)] = Floatify.call(value)
        end
        Breaker::Metrics.new(r[EVENT_SUCCESS],
                             r[EVENT_FAILURE],
                             r[EVENT_TIMEOUT],
                             r[EVENT_SHORT_CIRCUITED],
                             r[LATENCY_COUNT],
                             r[LATENCY_SUM],
                             latency_buckets)
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
