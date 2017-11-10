module CircuitBreaker
  module Remote
    RESPONSE_OK = 'OK'.freeze

    COMMAND_INSTALL = 'INSTALL'.freeze
    COMMAND_ALLOW_REQUEST = 'ALLOW_REQUEST'.freeze
    COMMAND_RECORD = 'RECORD'.freeze
    COMMAND_METRICS= 'METRICS'.freeze
    COMMAND_BREAKERS = 'BREAKERS'.freeze
    COMMAND_PING = 'PING'.freeze
    COMMAND_QUIT = 'QUIT'.freeze

    EVENT_SUCCESS = Breaker::EVENT_SUCCESS
    EVENT_FAILURE = Breaker::EVENT_FAILURE
    EVENT_TIMEOUT = Breaker::EVENT_TIMEOUT
    EVENT_SHORT_CIRCUITED = Breaker::EVENT_SHORT_CIRCUITED

    LATENCY_SUM = 'latency_sum'.freeze
    LATENCY_COUNT = 'latency_count'.freeze
    LATENCY_PERCENTILES = 'latency_percentiles'.freeze
  end
end