module RailsPulse
  class SqlQueryNormalizer
    # Adapters whose drivers escape a quote inside a string literal with a
    # backslash ('O\'Brien', "O\"Brien") rather than by doubling it. The
    # PostgreSQL and SQLite adapters double the quote, and on those databases
    # a backslash inside a plain string is an ordinary character ('C:\' is a
    # complete string), so backslash handling must switch on the adapter
    # rather than apply everywhere.
    BACKSLASH_ESCAPING_ADAPTERS = %w[mysql2 trilogy].freeze

    # Opening delimiter of a PostgreSQL dollar-quoted string: $$ or $tag$.
    # \G anchors the match at the scan position, so a failed attempt does
    # not search ahead through the rest of the string.
    DOLLAR_QUOTE_OPENER = /\G\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/

    # String-literal prefixes: PostgreSQL escape strings (E'...'), bit,
    # hex and national strings (B'...', X'...', N'...'), upper or lower case.
    STRING_PREFIX_CHARS = "EeBbXxNn"

    # A quoted token protected as an identifier rather than redacted as a
    # value: a plain identifier or a dotted chain of them ("users.email").
    # Anything else between double quotes — an email, a sentence, a number —
    # is a string value on the databases where double quotes can delimit
    # strings (MySQL, SQLite), so it must not survive normalization.
    QUOTED_IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_$]*(?:\.[A-Za-z_][A-Za-z0-9_$]*)*\z/

    # Longest double-quoted span that is checked against QUOTED_IDENTIFIER.
    # PostgreSQL caps an identifier at 63 bytes and MySQL at 64, so a dotted
    # chain of three is well within this; anything longer is a value, and
    # skipping the regex keeps a long literal from tripping a host's tight
    # Regexp.timeout (issue #286).
    MAX_QUOTED_IDENTIFIER_LENGTH = 256

    # Smart normalization: preserve table/column names, replace only literal values
    def self.normalize(query_string, adapter: host_adapter)
      new(query_string, adapter: adapter).normalize
    end

    # The host application's primary database adapter, which decides the
    # string-escaping rules. A host that also queries a second database on a
    # different adapter has those queries normalized with the primary's rules.
    def self.host_adapter
      @host_adapter ||= ActiveRecord::Base.connection_db_config.adapter.to_s
    end

    def initialize(query_string, adapter: self.class.host_adapter)
      @query_string = query_string
      @backslash_escapes = BACKSLASH_ESCAPING_ADAPTERS.include?(adapter.to_s.downcase)
    end

    def normalize
      return nil if @query_string.nil?
      return "" if @query_string.empty?

      normalized = @query_string.dup

      # Step 0: Replace every string literal in one left-to-right pass, so a
      # quote form occurring inside another (an apostrophe in a dollar-quoted
      # string, $$ inside a plain string) cannot pair across two separate
      # literals. Double-quoted spans are kept only when they are identifiers.
      normalized = replace_string_literals(normalized)

      # Step 1: Temporarily protect quoted identifiers
      protected_identifiers = protect_identifiers(normalized)
      normalized = protected_identifiers[:normalized]

      # Step 2: Replace literal values
      normalized = replace_literal_values(normalized)

      # Step 3: Handle special SQL constructs
      normalized = handle_special_constructs(normalized)

      # Step 4: Restore protected identifiers
      normalized = restore_identifiers(normalized, protected_identifiers[:mapping])

      # Step 5: Clean up and normalize whitespace
      normalize_whitespace(normalized)
    end

    private

    # One linear scan over the query replacing every single-quoted string
    # ('...', with '' doubling and, on backslash-escaping adapters, \'),
    # prefixed string (E'...' and friends, with backslash escapes) and
    # dollar-quoted string ($$...$$, $tag$...$tag$) with "?". A double-quoted
    # span is copied through when it is an identifier and replaced with "?"
    # when it is a value; backticked spans are always identifiers and are
    # copied through. Left to right with no backtracking, like the databases'
    # own lexers, and no regex runs across literal content, so a host's tight
    # Regexp.timeout cannot trip on a long literal (see issue #286).
    def replace_string_literals(query)
      result = +""
      i = 0
      len = query.length

      while i < len
        char = query[i]

        case char
        when "'"
          close = find_closing_quote(query, i + 1, "'", backslash_escapes: @backslash_escapes)
          if close
            result << "?"
            i = close + 1
          else
            result << query[i..]
            break
          end
        when '"'
          close = find_closing_quote(query, i + 1, '"', backslash_escapes: @backslash_escapes)
          if close
            result << (quoted_identifier?(query[(i + 1)...close]) ? query[i..close] : "?")
            i = close + 1
          else
            result << query[i..]
            break
          end
        when "`"
          close = find_closing_quote(query, i + 1, "`")
          if close
            result << query[i..close]
            i = close + 1
          else
            result << query[i..]
            break
          end
        when "$"
          if (m = DOLLAR_QUOTE_OPENER.match(query, i))
            delimiter = m[0]
            close = query.index(delimiter, i + delimiter.length)
            if close
              result << "?"
              i = close + delimiter.length
              next
            end
          end
          result << char
          i += 1
        else
          if STRING_PREFIX_CHARS.include?(char) && query[i + 1] == "'" &&
              (i == 0 || !query[i - 1].match?(/[A-Za-z0-9_$]/))
            close = find_closing_quote(query, i + 2, "'", backslash_escapes: true)
            if close
              result << "?"
              i = close + 1
              next
            end
          end
          result << char
          i += 1
        end
      end

      result
    end

    # Swaps every quoted identifier for a placeholder so the value
    # replacement below cannot touch it: a column named "true" or `col2`
    # must come back intact. A double-quoted span that is not an identifier
    # can only remain after an unterminated literal was copied through
    # verbatim; it is a value and is redacted here.
    def protect_identifiers(query)
      protected_identifiers = {}
      identifier_counter = 0

      normalized = query.gsub(/`[^`]+`|"([^"]+)"/) do |match|
        next "?" if $1 && !quoted_identifier?($1)

        placeholder = "__IDENTIFIER_#{identifier_counter}__"
        protected_identifiers[placeholder] = match
        identifier_counter += 1
        placeholder
      end

      { normalized: normalized, mapping: protected_identifiers }
    end

    def quoted_identifier?(content)
      content.length <= MAX_QUOTED_IDENTIFIER_LENGTH && content.match?(QUOTED_IDENTIFIER)
    end

    def replace_literal_values(query)
      normalized = query.dup

      # Replace numbers in exponent form first (1e5, 2.5E-3, 1.0e-05 as Ruby
      # writes small floats), then decimals, then integers, so that no later
      # pattern can match the remains of an earlier one. The lookarounds keep
      # digits that are part of an identifier (users2, int4) in place.
      normalized = normalized.gsub(/(?<![a-zA-Z_])\b\d+(?:\.\d+)?[eE][+-]?\d+\b(?![a-zA-Z_])/, "?")
      normalized = normalized.gsub(/(?<![a-zA-Z_])\b\d+\.\d+\b(?![a-zA-Z_])/, "?")
      normalized = normalized.gsub(/(?<![a-zA-Z_])\b\d+\b(?![a-zA-Z_])/, "?")

      # Handle boolean literals
      normalized.gsub(/\b(true|false)\b/i, "?")
    end

    # Returns the index of the unescaped closing quote_char starting the
    # search at `start`, treating a doubled quote_char (e.g. '') as an
    # escaped literal quote rather than a terminator. With
    # backslash_escapes, a backslash also escapes the character after it.
    # Returns nil if the string is never closed.
    def find_closing_quote(query, start, quote_char, backslash_escapes: false)
      j = start
      len = query.length

      while j < len
        char = query[j]

        if backslash_escapes && char == "\\"
          j += 2
        elsif char == quote_char
          return j unless query[j + 1] == quote_char
          j += 2
        else
          j += 1
        end
      end

      nil
    end

    def handle_special_constructs(query)
      normalized = normalize_in_clauses(query)
      normalized = normalize_values_rows(normalized)
      normalized.gsub(/\bBETWEEN\s+\?\s+AND\s+\?/i, "BETWEEN ? AND ?")
    end

    # The number of values in an IN list is a property of one execution, not
    # of the statement, so every literal list becomes IN (?): a preload that
    # runs with 3 ids and then with 12 is one Query. A subquery is kept, with
    # the IN clauses inside it normalized the same way, so `id IN (SELECT …)`
    # stays a different statement from `id IN (?)`. Paren depth is tracked so
    # a subquery containing nested parens (HAVING (COUNT(*) > ?)) ends where
    # it should.
    def normalize_in_clauses(query)
      result = +""
      i = 0
      while i < query.length
        m = word_boundary?(query, i) && query[i..].match(/\AIN\s*\(/i)

        if m
          open = i + m[0].length - 1
          close = matching_paren(query, open)
          content = query[(open + 1)...close]
          result << (content.match?(/\bSELECT\b/i) ? "IN (#{normalize_in_clauses(content)})" : "IN (?)")
          i = close + 1
        else
          result << query[i]
          i += 1
        end
      end
      result
    end

    # A multi-row insert (insert_all) lists one parenthesised group per row,
    # and the row count is likewise a property of one execution: only the
    # first row is kept, so VALUES (?, ?), (?, ?) becomes VALUES (?, ?).
    def normalize_values_rows(query)
      result = +""
      i = 0
      while i < query.length
        m = word_boundary?(query, i) && query[i..].match(/\AVALUES\s*\(/i)

        if m
          close = matching_paren(query, i + m[0].length - 1)
          result << query[i..close]
          i = close + 1

          while i < query.length && (row = query[i..].match(/\A\s*,\s*\(/))
            i = matching_paren(query, i + row[0].length - 1) + 1
          end
        else
          result << query[i]
          i += 1
        end
      end
      result
    end

    def word_boundary?(query, i)
      i == 0 || !query[i - 1].match?(/[a-zA-Z_0-9]/)
    end

    # Index of the ")" matching the "(" at `open`, or the query's length
    # when it is never closed.
    def matching_paren(query, open)
      depth = 0
      j = open
      while j < query.length
        case query[j]
        when "(" then depth += 1
        when ")"
          depth -= 1
          return j if depth == 0
        end
        j += 1
      end
      query.length
    end

    def restore_identifiers(query, identifier_mapping)
      normalized = query.dup
      # Block form: a replacement string would interpret \` or \\ inside an
      # identifier as a back-reference.
      identifier_mapping.each do |placeholder, original|
        normalized = normalized.gsub(placeholder) { original }
      end
      normalized
    end

    def normalize_whitespace(query)
      query.gsub(/\s+/, " ").strip
    end
  end
end
