module CircuitBreaker
  class Breaker
    EVENT_SUCCESS = 'success'.freeze
    EVENT_FAILURE = 'failure'.freeze
    EVENT_TIMEOUT = 'timeout'.freeze
    EVENT_SHORT_CIRCUITED = 'short_circuited'.freeze

    attr_accessor :window_duration,
                  :sleep_window_duration,
                  :error_threshold,
                  :request_volume_threshold

    def initialize(options)
      @window_duration = options[:window_duration] || 10
      @sleep_window_duration = options[:sleep_window_duration] || 5
      @error_threshold = options[:error_threshold] || 0.5
      @request_volume_threshold = options[:request_volume_threshold] || @window_duration

      @buckets = []
      @bucket = Bucket.new(Time.now.to_i)
      @buckets_success = 0
      @buckets_failure = 0
      @buckets_timeout = 0
      @buckets_short_circuted = 0
      @last_error_at = 0
    end

    def allow_request?
      success = @buckets_success + @bucket.success
      failure = @buckets_failure + @bucket.failure
      timeout = @buckets_timeout + @bucket.timeout
      error = failure + timeout
      request = success + error
      return true if error.to_f / request < @error_threshold
      return true if request < @request_volume_threshold
      @bucket.timestamp - @last_error_at >= @sleep_window_duration
    end

    def health
      Health.new(@buckets_success + @bucket.success,
                 @buckets_failure + @bucket.failure,
                 @buckets_timeout + @bucket.timeout,
                 @buckets_short_circuted + @bucket.short_circuited)
    end

    def slide(t)
      if t > @bucket.timestamp
        @buckets.push @bucket
        @bucket = Bucket.new(t)
        window_start = @bucket.timestamp - @window_duration + 1
        @buckets = @buckets.drop_while { |bucket| bucket.timestamp < window_start }
        @buckets_success = 0
        @buckets_failure = 0
        @buckets_timeout = 0
        @buckets_short_circuted = 0
        @buckets.each do |bucket|
          @buckets_success += bucket.success
          @buckets_failure += bucket.failure
          @buckets_timeout += bucket.timeout
          @buckets_short_circuted += bucket.short_circuited
        end
      end
    end

    def record_success
      @bucket.hit_success
    end

    def record_failure
      @bucket.hit_failure
      @last_error_at = @bucket.timestamp
    end

    def record_timeout
      @bucket.hit_timeout
      @last_error_at = @bucket.timestamp
    end

    def record_short_circuited
      @bucket.hit_short_circuited
    end

    Health = Struct.new(:success, :failure, :timeout, :short_circuited)

    class Bucket
      attr_reader :timestamp, :success, :failure, :timeout, :short_circuited

      def initialize(timestamp)
        @timestamp = timestamp
        @success = 0
        @failure = 0
        @timeout = 0
        @short_circuited = 0
      end

      def error; @failure + @timeout end

      def hit_success; @success += 1 end

      def hit_failure; @failure += 1 end

      def hit_timeout; @timeout += 1 end

      def hit_short_circuited; @short_circuited += 1 end
    end
  end
end
