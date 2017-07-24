require 'influxdb'

module CircuitBreaker
  class NoopMonitor
    def record_request(name, event, latency)
    end
  end

  class InfluxdbMonitor
    def initialize(options)
      @client = InfluxDB::Client.new udp: {host: options[:host], port: options[:port]}
    end

    def record_request(name, event, latency)
      begin
        @client.write_point("breaker_requests", {values: {latency: (latency * 1000).to_i}, tags: {breaker: name, event: event}})
      rescue
        # ignored
      end
    end
  end
end
