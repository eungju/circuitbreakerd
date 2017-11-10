require 'spec_helper'
require 'circuit_breaker/server'

RSpec.describe CircuitBreaker::Server do
  before do
    Timecop.return
    @dut = CircuitBreaker::Server.new
    @name = "b"
    @dut.install(@name, {})
  end

  it 'allow request' do
    expect(@dut.allow_request?(@name)).to eq(true)
  end

  it 'record success' do
    @dut.record_success(@name, 0.01)
    expect(@dut.metrics(@name).success).to eq(1)
  end

  it 'record failure' do
    @dut.record_failure(@name, 0.01)
    expect(@dut.metrics(@name).failure).to eq(1)
  end

  it 'record timeout' do
    @dut.record_timeout(@name, 0.1)
    expect(@dut.metrics(@name).timeout).to eq(1)
  end

  it 'record short-circuited' do
    @dut.record_short_circuited(@name)
    expect(@dut.metrics(@name).short_circuited).to eq(1)
  end

  it 'breakers' do
    expect(@dut.breakers).to eq([@name])
  end
end
