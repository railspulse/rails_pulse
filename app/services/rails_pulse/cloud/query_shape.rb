module RailsPulse
  module Cloud
    # What Cloud receives for a query, rebuilt from the normalised SQL by
    # allow-list. Normalisation replaces the literals it recognises with `?`,
    # so a literal in a form it does not recognise stays in the stored SQL;
    # here every token must be a keyword, an identifier, an operator, a
    # number or a placeholder, and a query with anything else has no shape.
    #
    #   shape = QueryShape.new('SELECT "users".* FROM "users" WHERE "users"."email" = ? LIMIT ?')
    #   shape.sql_shape  # => "SELECT users.* FROM users WHERE users.email = ? LIMIT ?"
    #   shape.label      # => "SELECT users"
    #
    #   QueryShape.new("SELECT * FROM notes WHERE body = $$jane@example.com$$").sql_shape  # => nil
    class QueryShape
      MAX_LENGTH = 2_000
      MAX_LABEL_TABLES = 5

      IDENTIFIER = /[A-Za-z_][A-Za-z0-9_$]*/
      BARE_IDENTIFIER = /\A#{IDENTIFIER}\z/
      NUMBER = /\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/
      OPERATOR = %r{[=<>!+\-*/%:|]+}
      PUNCTUATION = /[.,();]/
      PLACEHOLDER = /\?|\$\d+/
      # Comments carry no shape, and query log tags put request IDs in them.
      COMMENT = %r{/\*.*?(?:\*/|\z)|--[^\n]*}m

      # Keywords after which the next name is a table.
      TABLE_KEYWORDS = %w[FROM JOIN INTO UPDATE].freeze

      # Keywords that take a parenthesised list, so `IN (?, ?)` is not
      # rendered like a function call.
      KEYWORDS_BEFORE_PARENTHESIS = %w[
        ALL AND ANY AS EXISTS FROM IN INTO JOIN LATERAL NOT ON OR SELECT SET SOME THEN UNION USING VALUES WHEN WHERE
      ].freeze

      # MySQL quotes identifiers with backticks; a double-quoted token there
      # is a string, whatever it contains.
      def self.for_adapter(sql, adapter)
        new(sql, double_quotes_are_strings: adapter.to_s.match?(/mysql|trilogy/i))
      end

      def initialize(sql, double_quotes_are_strings: false)
        @sql = sql.to_s.gsub(COMMENT, " ")
        @double_quotes_are_strings = double_quotes_are_strings
      end

      # The shape, or nil when any token is not on the allow-list.
      def sql_shape
        return @sql_shape if defined?(@sql_shape)

        @sql_shape = tokens.any? { |kind, _| kind == :unsafe } ? nil : render.first(MAX_LENGTH)
      end

      # The statement type and up to five table names, always available
      # because it is built only from tokens that pass.
      def label
        first_kind, first_text = tokens.first
        statement = first_kind == :word ? first_text.upcase : "QUERY"
        tables = table_names
        tables.empty? ? statement : "#{statement} #{tables.join(', ')}"
      end

      private

      # [[kind, text], ...] where kind is :word, :name (a quoted identifier,
      # unquoted), :number, :placeholder, :operator or :unsafe.
      def tokens
        @tokens ||= begin
          scanner = StringScanner.new(@sql)
          result = []
          until scanner.eos?
            next if scanner.skip(/\s+/)

            result << next_token(scanner)
          end
          result
        end
      end

      def next_token(scanner)
        if (text = scanner.scan(IDENTIFIER)) then [ :word, text ]
        elsif scanner.scan(NUMBER) then [ :number, "?" ]
        elsif (text = scanner.scan(PLACEHOLDER)) then [ :placeholder, "?" ]
        elsif (text = scanner.scan(/"(?:[^"]|"")*"?/)) then quoted(text, '"')
        elsif (text = scanner.scan(/`[^`]*`?/)) then quoted(text, "`")
        elsif (text = scanner.scan(/'(?:[^']|'')*'?/)) then [ :unsafe, text ]
        elsif (text = scanner.scan(PUNCTUATION)) then [ :operator, text ]
        elsif (text = scanner.scan(OPERATOR)) then [ :operator, text ]
        else [ :unsafe, scanner.getch ]
        end
      end

      def quoted(text, quote)
        return [ :unsafe, text ] if quote == '"' && @double_quotes_are_strings

        content = text.delete_prefix(quote).delete_suffix(quote)
        content.match?(BARE_IDENTIFIER) && text.end_with?(quote) && text.length > 1 ? [ :name, content ] : [ :unsafe, text ]
      end

      # Tokens rejoined with single spaces, except none around `.`, after `(`,
      # before `)` and `,`, or between a function name and its `(`, with
      # schema qualifiers dropped.
      def render
        output = +""
        tokens = without_schemas
        tokens.each_with_index do |token, index|
          output << " " if index.positive? && space_between?(tokens[index - 1], token, index > 1 ? tokens[index - 2] : nil)
          output << token.last
        end
        output
      end

      def space_between?(previous, token, earlier)
        before = previous.last
        text = token.last
        return false if before == "." || text == "." || before == "(" || text == ")" || text == ","
        return false if text == "(" && function_name?(previous, earlier)

        true
      end

      # A word before `(` is a function call, unless it is a keyword or the
      # table named after INTO (`INSERT INTO posts (title)`).
      def function_name?(token, earlier)
        kind, text = token
        return false unless kind == :word && !KEYWORDS_BEFORE_PARENTHESIS.include?(text.upcase)

        !(earlier && earlier.first == :word && TABLE_KEYWORDS.include?(earlier.last.upcase))
      end

      # A three-part name (schema.table.column) loses its schema anywhere; a
      # two-part name right after FROM, JOIN, INTO or UPDATE is schema.table
      # and loses its schema too. Apps with one schema per tenant name their
      # customers there.
      def without_schemas
        list = tokens.dup
        index = 0
        result = []
        while index < list.size
          if qualified_name?(list, index, 3)
            index += 2
          elsif qualified_name?(list, index, 2) && table_position?(result)
            index += 2
          end
          result << list[index]
          index += 1
        end
        result
      end

      # A name of `parts` identifiers joined by dots starts at `index`.
      def qualified_name?(list, index, parts)
        (0...parts).all? do |part|
          kind, text = list[index + (part * 2)]
          dot = list[index + (part * 2) + 1]
          name = %i[word name].include?(kind)
          last = part == parts - 1
          name && (last || dot&.last == ".") && (!last || text != "*")
        end
      end

      def table_position?(result)
        kind, text = result.last
        kind == :word && TABLE_KEYWORDS.include?(text.upcase)
      end

      def table_names
        names = []
        tokens.each_with_index do |(kind, text), index|
          next unless kind == :word && TABLE_KEYWORDS.include?(text.upcase)

          name = table_after(index + 1)
          names << name if name && !names.include?(name)
          break if names.size >= MAX_LABEL_TABLES
        end
        names
      end

      # The table named after a keyword, with any schema dropped. Nil when
      # what follows is not a plain name (a subquery, or anything unsafe).
      def table_after(index)
        name = nil
        loop do
          kind, text = tokens[index]
          return name unless %i[word name].include?(kind)

          name = text
          return name unless tokens[index + 1]&.last == "."

          index += 2
        end
      end
    end
  end
end
