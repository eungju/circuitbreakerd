require 'spec_helper'
require 'circuit_breaker/breaker'

RSpec.describe CircuitBreaker::Breaker do
  before do
    Timecop.return
    @dut = CircuitBreaker::Breaker.new()
  end

  it 'records success' do
    @dut.record_success
    expect(@dut.health.success).to eq(1)
    expect(@dut.health.failure).to eq(0)
  end

  it 'records failure' do
    @dut.record_failure
    expect(@dut.health.success).to eq(0)
    expect(@dut.health.failure).to eq(1)
  end

  it 'records timeout' do
    @dut.record_timeout
    expect(@dut.health.timeout).to eq(1)
    expect(@dut.health.success).to eq(0)
    expect(@dut.health.failure).to eq(0)
  end

  it 'records short circuited' do
    @dut.record_short_circuited
    expect(@dut.health.short_circuited).to eq(1)
    expect(@dut.health.success).to eq(0)
    expect(@dut.health.failure).to eq(0)
  end

  it 'trips to open when the error threshold reached by failures' do
    @dut.request_volume_threshold.times do |i|
      expect(@dut.allow_request?).to eq(true)
      if i < 5
        @dut.record_success
      else
        @dut.record_failure
      end
    end
    expect(@dut.allow_request?).to eq(false)
    expect(@dut.health.success).to eq(5)
    expect(@dut.health.failure).to eq(5)
  end

  it 'keeps closed when the request volume threshold has not reached' do
    @dut.request_volume_threshold.pred.times do
      expect(@dut.allow_request?).to eq(true)
      @dut.record_failure
    end
    expect(@dut.allow_request?).to eq(true)
    expect(@dut.health.success).to eq(0)
    expect(@dut.health.failure).to eq(9)
  end

  it 'discards samples older than window duration' do
    @dut.window_duration.succ.times do |i|
      @dut.slide(Time.now.to_i)
      if i < 2
        @dut.record_failure
      else
        @dut.record_success
      end
      Timecop.travel(1)
    end
    expect(@dut.health.success).to eq(@dut.window_duration - 1)
    expect(@dut.health.failure).to eq(1)
  end

  it 'keeps open when the reset attempt failed' do
    @dut.request_volume_threshold.times do
      @dut.record_failure
    end
    Timecop.travel(@dut.sleep_window_duration)
    @dut.slide(Time.now.to_i)
    expect(@dut.allow_request?).to be(true)
    @dut.record_failure
    expect(@dut.allow_request?).to be(false)
  end

  it 'resets to closed when the reset attempt succeed' do
    @dut.request_volume_threshold.times do
      @dut.record_failure
    end
    Timecop.travel(@dut.sleep_window_duration)
    @dut.slide(Time.now.to_i)
    expect(@dut.allow_request?).to be(true)
    @dut.record_success
    expect(@dut.allow_request?).to be(true)
  end
end
