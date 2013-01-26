module Impala
  class Cursor
    include Enumerable

    def initialize(handle, service, buffer_length=1024)
      @handle = handle
      @service = service
      @metadata = @service.get_results_metadata(@handle)

      @buffer_length = buffer_length
      @row_buffer = []

      @done = false
      @open = true
    end

    def inspect
      "#<#{self.class}#{open? ? '' : ' (CLOSED)'}>"
    end

    def each
      while row = fetch_row
        yield row
      end
    end

    def fetch_row
      raise CursorError.new("Cursor has expired or been closed") unless @open

      if @row_buffer.empty?
        if @done
          return nil
        else
          fetch_more
        end
      end

      @row_buffer.shift
    end

    def fetch_all
      self.to_a
    end

    def close
      @open = false
      @service.close(@handle)
    end

    def open?
      @open
    end

    def has_more?
      !@done || !@row_buffer.empty?
    end

    private

    def fetch_more
      return if @done

      begin
        res = @service.fetch(@handle, false, @buffer_length)
      rescue Protocol::Beeswax::BeeswaxException => e
        @closed = true
        raise CursorError.new("Cursor has expired or been closed")
      end

      rows = res.data.map { |raw| parse_row(raw) }
      @row_buffer.concat(rows)
      @done = true unless res.has_more
    end

    def parse_row(raw)
      row = {}
      fields = raw.split(@metadata.delim)

      fields.zip(@metadata.schema.fieldSchemas).each do |raw_value, schema|
        value = convert_raw_value(raw_value, schema)
        row[schema.name.to_sym] = value
      end

      row
    end

    def convert_raw_value(value, schema)
      return nil if value == 'NULL'

      case schema.type
      when 'string'
        value
      when 'boolean'
        if value == 'true'
          true
        elsif value == 'false'
          false
        else
          raise ParsingError.new("Invalid value for boolean: #{value}")
        end
      when 'tinyint', 'int', 'bigint'
        value.to_i
      when 'double'
        value.to_f
      else
        raise ParsingError.new("Unknown type: #{schema.type}")
      end
    end
  end
end