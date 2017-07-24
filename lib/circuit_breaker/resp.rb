require 'hiredis/reader'

module CircuitBreaker
  module Resp
    CRNL = "\r\n".freeze
    NL = "\n".freeze
    NEWLINE = CRNL
    TYPE_SIMPLE_STRING = '+'.freeze
    TYPE_ERROR = '-'.freeze
    TYPE_INTEGER = ':'.freeze
    TYPE_BULK_STRING = '$'.freeze
    TYPE_ARRAY = '*'.freeze

    def resp_simple_string(v)
      TYPE_SIMPLE_STRING.dup << v << NEWLINE
    end

    def resp_error(v)
      TYPE_ERROR.dup << v << NEWLINE
    end

    def resp_integer(v)
      TYPE_INTEGER.dup << v.to_s << NEWLINE
    end

    def resp_bulk_string(v)
      TYPE_BULK_STRING.dup << v.bytesize.to_s << NEWLINE << v << NEWLINE
    end

    def resp_array(a)
      r = TYPE_ARRAY.dup << a.size.to_s << NEWLINE
      a.each do |v|
        r << v
      end
      r
    end

    class RequestParser
      def initialize
        @reader = nil
      end

      def feed(data)
        if @reader.nil?
          @reader = data[0] == TYPE_ARRAY ? Hiredis::Reader.new : InlineRequestReader.new
        end
        @reader.feed(data)
      end

      def request
        @reader.gets
      end
    end

    class InlineRequestReader
      def initialize
        @buffer = ''
      end

      def feed(data)
        @buffer << data
      end

      def gets
        drop = CRNL.size
        index = @buffer.index(CRNL)
        if index.nil?
          drop = NL.size
          index = @buffer.index(NL) if index.nil?
        end
        return false if index.nil?
        @buffer.slice!(0, index + drop)[0..(-(drop + 1))].split
      end
    end
  end
end
