module CircuitBreaker
  class NoopMonitor
    def record_request(name, event, latency)
    end
  end
end
