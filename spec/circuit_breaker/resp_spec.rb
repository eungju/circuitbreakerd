require 'spec_helper'
require 'circuit_breaker/resp'

RSpec.describe CircuitBreaker::Resp do
  Resp = CircuitBreaker::Resp
  include Resp

  it 'can represent simple strings' do
    expect(resp_simple_string("OK")).to eq("+OK\r\n")
  end

  it 'can represent errors' do
    expect(resp_error("ERR")).to eq("-ERR\r\n")
  end

  it 'can represent integers' do
    expect(resp_integer(42)).to eq(":42\r\n")
  end

  it 'can represent bulk strings' do
    expect(resp_bulk_string("Hello")).to eq("$5\r\nHello\r\n")
  end

  it 'can represent arrays' do
    expect(resp_array([resp_simple_string("key"), resp_integer(1)])).to eq("*2\r\n+key\r\n:1\r\n")
  end

  it 'can parse CRNL lines' do
    dut = Resp::RequestParser.new
    dut.feed "abc"
    expect(dut.request).to eq(false)
    dut.feed "\r\n"
    expect(dut.request).to eq(["abc"])
    expect(dut.request).to eq(false)
  end

  it 'can parse NL lines' do
    dut = Resp::RequestParser.new
    dut.feed "abc"
    expect(dut.request).to eq(false)
    dut.feed "\n"
    expect(dut.request).to eq(["abc"])
    expect(dut.request).to eq(false)
  end

  it 'can parse inline command request' do
    dut = Resp::RequestParser.new
    dut.feed "SET a 1\r\n"
    expect(dut.request).to eq(["SET", "a", "1"])
  end

  it 'can parse unified command request' do
    dut = Resp::RequestParser.new
    dut.feed "*3\r\n$3\r\nSET\r\n$1\r\na\r\n$1\r\n1\r\n"
    expect(dut.request).to eq(["SET", "a", "1"])
  end
end
