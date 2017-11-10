require 'eventmachine'
require_relative 'breaker'
require_relative 'resp'
require_relative 'remote'

module CircuitBreaker
  class Server
    def initialize
      @unknown_breaker = CircuitBreaker::Breaker.new({})
      @breakers = Hash.new(@unknown_breaker)
      @timestamp = Time.now.to_i
    end

    def maintain
      now = Time.now
      t = now.to_i
      if t > @timestamp
        @timestamp = t
        @breakers.each do |name, breaker|
          breaker.slide(t)
        end
        @unknown_breaker.slide(t)
      end
    end

    def install(name, options)
      unless @breakers.has_key?(name)
        breaker = CircuitBreaker::Breaker.new(options)
        @breakers[name] = breaker
      end
    end

    def allow_request?(name)
      @breakers[name].allow_request?
    end

    def record_success(name, latency)
      @breakers[name].record_success(latency)
    end

    def record_failure(name, latency)
      @breakers[name].record_failure(latency)
    end

    def record_timeout(name, latency)
      @breakers[name].record_timeout(latency)
    end

    def record_short_circuited(name)
      @breakers[name].record_short_circuited()
    end

    def metrics(name)
      @breakers[name].metrics
    end

    def breakers
      @breakers.keys
    end
  end

  class RespHandler < EM::Connection
    Resp = CircuitBreaker::Resp
    include Resp
    include CircuitBreaker::Remote

    INTEGER_OPTIONS = [:window_duration, :sleep_window_duration, :request_volume_threshold]
    FLOAT_OPTIONS = [:error_threshold]

    def initialize(server, logger)
      @server = server
      @logger = logger
    end

    def post_init
      @logger.debug("Bind client")
      @request_parser = Resp::RequestParser.new
    end

    def unbind
      @logger.debug("Unbind client")
    end

    def receive_data(data)
      begin
        @request_parser.feed(data)
        while (request = @request_parser.request)
          handle_request(request) if !request.empty?
        end
      rescue => e
        @logger.error(e.message)
        close_connection
      end
    end

    def handle_request(request)
      command = request[0].upcase
      args = request[1..-1]
      if command == COMMAND_INSTALL
        handle_install(args)
      elsif command == COMMAND_ALLOW_REQUEST
        handle_allow_request(args)
      elsif command == COMMAND_RECORD
        handle_record(args)
      elsif command == COMMAND_METRICS
        handle_metrics(args)
      elsif command == COMMAND_BREAKERS
        handle_breakers(args)
      elsif command == COMMAND_PING
        handle_ping(args)
      elsif command == COMMAND_QUIT
        handle_quit(args)
      else
        handle_unknown_command(command)
      end
    end

    def handle_install(args)
      name = args[0]
      options = {}
      args[1..-1].each_cons(2) { |key, value|
        key = key.to_sym
        value = value.to_i if INTEGER_OPTIONS.include?(key)
        value = value.to_f if FLOAT_OPTIONS.include?(key)
        options[key] = value
      }
      @server.install(name, options)
      send_data resp_simple_string(RESPONSE_OK)
    end

    def handle_allow_request(args)
      name = args[0]
      allow = @server.allow_request?(name)
      send_data resp_integer(allow ? 1 : 0)
    end

    def handle_record(args)
      name = args[0]
      event = args[1].downcase
      latency = args.size >= 3 ? args[2].to_f : 0.0
      if event == EVENT_SUCCESS
        @server.record_success(name, latency)
      elsif event == EVENT_FAILURE
        @server.record_failure(name, latency)
      elsif event == EVENT_TIMEOUT
        @server.record_timeout(name, latency)
      elsif event == EVENT_SHORT_CIRCUITED
        @server.record_short_circuited(name)
      else
        send_data resp_error("ERR unknown event '#{event}'")
        return
      end
      send_data resp_simple_string(RESPONSE_OK)
    end

    def handle_metrics(args)
      name = args[0]
      metrics = @server.metrics(name)
      send_data resp_array([resp_simple_string(EVENT_SUCCESS), resp_integer(metrics.success),
                            resp_simple_string(EVENT_FAILURE), resp_integer(metrics.failure),
                            resp_simple_string(EVENT_TIMEOUT), resp_integer(metrics.timeout),
                            resp_simple_string(EVENT_SHORT_CIRCUITED), resp_integer(metrics.short_circuited),
                            resp_simple_string(LATENCY_SUM), resp_simple_string(metrics.latency_sum.to_s),
                            resp_simple_string(LATENCY_COUNT), resp_integer(metrics.latency_count),
                            resp_simple_string(LATENCY_PERCENTILES),
                            resp_array(metrics.latency_percentiles.map { |k, v| [resp_simple_string(k.to_s), resp_simple_string((v || 0).to_s)] }.flatten)])
    end

    def handle_breakers(args)
      send_data resp_array(@server.breakers.map { |name| resp_simple_string(name) })
    end

    def handle_ping(args)
      pong = args[0]
      send_data pong.nil? ? resp_simple_string('PONG') : resp_bulk_string(pong)
    end

    def handle_quit(args)
      send_data resp_simple_string(RESPONSE_OK)
      close_connection(after_writing=true)
    end

    def handle_unknown_command(command)
      send_data resp_error("ERR unknown command '#{command}'")
    end
  end
end
