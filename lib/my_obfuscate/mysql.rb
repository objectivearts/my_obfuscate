#encoding: UTF-8
require 'stringio'
require 'strscan'

class MyObfuscate
  class Mysql
    include MyObfuscate::InsertStatementParser
    include MyObfuscate::ConfigScaffoldGenerator

    LPAREN = /\(/
    RPAREN = /\)/
    NULL_LITERAL = /NULL/
    STRING_LITERAL = /'(\\\\|\\'|.)*?'/ # Matching "\\" followed by "\'" followed by . ensures proper escape handling
    OTHER_LITERAL = /[^,\)]+/           # All other literals are terminated by separator or right paren
    WHITESPACE = /[\s,;]+/              # We treat the "," separator and ";" terminator as whitespace

    def parse_insert_statement(line)
      if regex_match = insert_regex.match(line)
        {
            :ignore     => !regex_match[1].nil?,
            :table_name => regex_match[2].to_sym,
            :column_names => regex_match[3].split(/`\s*,\s*`/).map { |col| col.gsub('`', "").to_sym }
        }
      end
    end

    def make_insert_statement(table_name, column_names, rows, ignore = nil)
      buffer = StringIO.new
      buffer.write "INSERT #{ignore ? 'IGNORE ' : '' }INTO `#{table_name}` (`#{column_names.join('`, `')}`) VALUES "
      write_rows(buffer, rows)
      buffer.write ";"
      buffer.string
    end

    def write_rows(buffer, rows)
      rows.each_with_index do |row_values, i|
        buffer.write("(")
        write_row_values(buffer, row_values)
        buffer.write(")")
        buffer.write(",") if i < rows.length - 1
      end
    end

    def write_row_values(buffer, row_values)
      row_values.each_with_index do |value, j|
        buffer.write value
        buffer.write(",") if j < row_values.length - 1
      end
    end

    def insert_regex
      /^\s*INSERT\s*(IGNORE )?\s*INTO `(.*?)` \((.*?)\) VALUES\s*/i
    end

    def rows_to_be_inserted(line)
      scanner = StringScanner.new line
      scanner.scan insert_regex

      rows = []
      row_values = []
      until scanner.eos?
        if scanner.scan(LPAREN)
          # Left paren indicates the start of a row of (val1, val2, ..., valn)
          row_values = []
        elsif scanner.scan(RPAREN)
          # Right paren indicates the end of a row of (val1, val2, ..., valn)
          rows << row_values
        elsif scanner.scan(NULL_LITERAL)
          row_values << nil
        elsif match = scanner.scan(STRING_LITERAL)
          # We drop the leading and trailing quotes to extract the string
          row_values << match.slice(1, match.length - 2)
        elsif match = scanner.scan(OTHER_LITERAL)
          # All other literals.  We match these up to the "," separator or ")" closing paren.
          # Hence we rstrip to drop any whitespace between the literal and the "," or ")".
          row_values << match.rstrip
        else
          # This is minimal validation.  We're assuming valid input generated by mysqldump.
          raise "Parse error: unexpected token begginning at #{scanner.peek 80}"
        end
        # Ignore whitespace/separator after any token
        scanner.scan(WHITESPACE)
      end

      rows
    end

    def make_valid_value_string(value)
      if value.nil?
        "NULL"
      elsif value =~ /^0x[0-9a-fA-F]+$/
        value
      else
        "'" + value + "'"
      end
    end
  end
end
