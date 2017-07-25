require 'spec_helper'
require 'circuit_breaker/breaker_panel'

RSpec.describe CircuitBreaker::Breaker do
  def smooth
  end

  def faulty
    raise IOError
  end

  extend CircuitBreaker::BreakerPanel
  @@breaker = CircuitBreaker::InprocBreaker.new(:test, {}, $logger)
  relay_through :faulty, @@breaker
  relay_through :smooth, @@breaker

  it 'relays the smooth method' do
    smooth
    expect(@@breaker.health.success).to eq(1)
  end

  it 'relays the faulty method' do
    begin
      faulty
    rescue IOError
      expect(@@breaker.health.failure).to eq(1)
    else
      fail
    end
  end
end
