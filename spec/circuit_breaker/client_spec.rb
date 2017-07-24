require 'spec_helper'
require 'circuit_breaker/client'

RSpec.describe CircuitBreaker::InprocBreaker do
  before do
    Timecop.return
    @dut = CircuitBreaker::InprocBreaker.new(:test)
  end

  it 'executes the given block' do
    work = 0
    value = @dut.request {
      work += 1
      42
    }
    expect(work).to eq(1)
    expect(value).to eq(42)
  end

  it 'records a request as success' do
    @dut.request {}
    expect(@dut.health.success).to eq(1)
    expect(@dut.health.failure).to eq(0)
  end

  it 'records a request as failure when the request throws error' do
    begin
      @dut.request { raise StandardError }
    rescue
      expect(@dut.health.success).to eq(0)
      expect(@dut.health.failure).to eq(1)
    else
      fail
    end
  end

  it 'records a request as timeout when the request exeeds timeout' do
    @dut.request { Timecop.travel(@dut.request_timeout + 0.1) }
    expect(@dut.health.timeout).to eq(1)
    expect(@dut.health.success).to eq(0)
    expect(@dut.health.failure).to eq(0)
  end

  it 'allows some kind of errors' do
    @dut.tolerable_errors.push IOError
    begin
      @dut.request { raise EOFError }
    rescue EOFError
      expect(@dut.health.failure).to eq(0)
      expect(@dut.health.success).to eq(1)
    end
  end

  it 'short-circuits a request when the error threshold reached' do
    @dut.underlying.request_volume_threshold.times do |i|
      begin
        @dut.request { raise StandardError if i >= 5 }
      rescue
      end
    end
    work = 0
    begin
      @dut.request { work += 1 }
    rescue CircuitBreaker::ShortCircuitedError
      expect(work).to eq(0)
      expect(@dut.health.short_circuited).to eq(1)
      expect(@dut.health.success).to eq(5)
      expect(@dut.health.failure).to eq(5)
    else
      fail
    end
  end
end
