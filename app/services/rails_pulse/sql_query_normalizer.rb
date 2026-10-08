module RailsPulse
  class SqlQueryNormalizer
    # Above this length, skip the regex-based literal scan in favor of a
    # slower-per-char but backtracking-free manual scan. Regex matching here
    # is linear (benchmarked at ~0.4s for an 8,000,000-char literal under a
    # 1s Regexp.timeout), but a host app can configure Regexp.timeout far
    # below that, and very long queries are rare enough that the fast path
    # isn't worth the risk. 100_000 chars leaves generous headroom below
    # where even an aggressive timeout config could plausibly trip — see
    # issue #286.
    LONG_QUERY_THRESHOLD = 100_000

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

    # Smart normalization: preserve table/column names, replace only literal values
    def self.normalize(query_string)
      new(query_string).normalize
    end

    def initialize(query_string)
      @query_string = query_string
    end

    def normalize
      return nil if @query_string.nil?
      return "" if @query_string.empty?

      normalized = @query_string.dup

      # Step 0: Replace single-quoted, prefixed and dollar-quoted string
      # literals in one left-to-right pass, so a quote form occurring inside
      # another (an apostrophe in a dollar-quoted string, $$ inside a plain
      # string) cannot pair across two separate literals.
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
    # ('...', with '' doubling), prefixed string (E'...' and friends, with
    # backslash escapes) and dollar-quoted string ($$...$$, $tag$...$tag$)
    # with "?". Double-quoted and backticked spans are copied through
    # verbatim — whether they are identifiers or values is decided later —
    # so a quote character inside them cannot open a string here. Left to
    # right with no backtracking, like the databases' own lexers, and no
    # regex runs across literal content, so a host's tight Regexp.timeout
    # cannot trip on a long literal (see LONG_QUERY_THRESHOLD and #286).
    def replace_string_literals(query)
      result = +""
      i = 0
      len = query.length

      while i < len
        char = query[i]

        case char
        when "'"
          close = find_closing_quote(query, i + 1, "'")
          if close
            result << "?"
            i = close + 1
          else
            result << query[i..]
            break
          end
        when '"', "`"
          close = find_closing_quote(query, i + 1, char)
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

    def protect_identifiers(query)
      protected_identifiers = {}
      identifier_counter = 0
      normalized = query.dup

      # Protect backticked identifiers (MySQL style)
      normalized = normalized.gsub(/`([^`]+)`/) do |match|
        placeholder = "__IDENTIFIER_#{identifier_counter}__"
        protected_identifiers[placeholder] = match
        identifier_counter += 1
        placeholder
      end

      # Protect double-quoted identifiers (PostgreSQL/SQL standard style)
      # Only protect if they appear in contexts where identifiers are expected
      normalized = normalized.gsub(/"([^"]+)"/) do |match|
        content = $1
        # Only protect if it looks like an identifier (no spaces, not a sentence)
        if looks_like_identifier?(content)
          placeholder = "__IDENTIFIER_#{identifier_counter}__"
          protected_identifiers[placeholder] = match
          identifier_counter += 1
          placeholder
        else
          match  # Leave it as-is for now, will be replaced as string literal
        end
      end

      { normalized: normalized, mapping: protected_identifiers }
    end

    def looks_like_identifier?(content)
      content.match?(QUOTED_IDENTIFIER)
    end

    def replace_literal_values(query)
      normalized = query.dup

      # Single-quoted, prefixed and dollar-quoted strings were already
      # replaced by replace_string_literals before identifier protection.

      # Replace double-quoted string literals (not protected identifiers)
      normalized = replace_quoted_literals(normalized, '"')

      # Replace floating-point numbers FIRST (before integers) to avoid double replacement
      normalized = normalized.gsub(/(?<![a-zA-Z_])\b\d+\.\d+\b(?![a-zA-Z_])/, "?")

      # Replace integer literals with placeholders, but preserve identifiers containing numbers
      # Negative lookbehind/lookahead prevents replacing numbers in table/column names
      normalized = normalized.gsub(/(?<![a-zA-Z_])\b\d+\b(?![a-zA-Z_])/, "?")

      # Handle boolean literals
      normalized = normalized.gsub(/\b(true|false)\b/i, "?")

      normalized
    end

    # Replaces quote_char-delimited string literals with a single placeholder.
    # Uses a regex for the common case (fast — see benchmarks in
    # LONG_QUERY_THRESHOLD's comment) and falls back to a manual scan for
    # very long queries, where that regex risks Regexp::TimeoutError under
    # an aggressively configured Regexp.timeout — see issue #286.
    def replace_quoted_literals(query, quote_char)
      if query.length < LONG_QUERY_THRESHOLD
        pattern = quote_char == "'" ? /'(?:[^']|'')*'/ : /"(?:[^"]|"")*"/
        query.gsub(pattern, "?")
      else
        scan_quoted_literals(query, quote_char)
      end
    end

    # Linear, non-regex scan used above LONG_QUERY_THRESHOLD. A quote left
    # unterminated for the rest of the string is left untouched rather than
    # rescanned from every possible start position, which is what would make
    # a naive manual reimplementation quadratic.
    def scan_quoted_literals(query, quote_char)
      result = +""
      i = 0
      len = query.length

      while i < len
        char = query[i]

        unless char == quote_char
          result << char
          i += 1
          next
        end

        close_index = find_closing_quote(query, i + 1, quote_char)

        if close_index
          result << "?"
          i = close_index + 1
        else
          result << query[i..]
          break
        end
      end

      result
    end

    # Returns the index of the unescaped closing quote_char starting the
    # search at `start`, treating a doubled quote_char (e.g. '') as an
    # escaped literal quote rather than a terminator. With
    # backslash_escapes (prefixed strings like E'...'), a backslash also
    # escapes the character after it. Returns nil if the string is never
    # closed.
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
      normalized.gsub(/\bBETWEEN\s+\?\s+AND\s+\?/i, "BETWEEN ? AND ?")
    end

    # Replaces IN clause contents with placeholders using paren-depth tracking
    # so that subqueries containing nested parens (e.g. HAVING (COUNT(*) > N))
    # are handled correctly. A flat [^)]+ regex stops at the first ) it finds,
    # which breaks when the subquery contains function calls or nested clauses.
    def normalize_in_clauses(query)
      result = +""
      i = 0
      while i < query.length
        at_word_boundary = i == 0 || !query[i - 1].match?(/[a-zA-Z_0-9]/i)
        m = at_word_boundary && query[i..].match(/\AIN\s*\(\s*/i)

        if m
          content_start = i + m[0].length
          depth = 1
          j = content_start

          while j < query.length && depth > 0
            case query[j]
            when "(" then depth += 1
            when ")" then depth -= 1
            end
            j += 1 if depth > 0
          end

          content = query[content_start...j]

          if content.strip.match?(/\ASELECT\s/i)
            result << "IN (?)"
          else
            value_count = [ content.split(",").length, 1 ].max
            result << "IN (#{Array.new(value_count, "?").join(", ")})"
          end
          i = j + 1
        else
          result << query[i]
          i += 1
        end
      end
      result
    end

    def restore_identifiers(query, identifier_mapping)
      normalized = query.dup
      identifier_mapping.each do |placeholder, original|
        normalized = normalized.gsub(placeholder, original)
      end
      normalized
    end

    def normalize_whitespace(query)
      query.gsub(/\s+/, " ").strip
    end
  end
end
