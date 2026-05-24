module RailsPulse
  class SqlQueryNormalizer
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
      content.match?(/^[a-zA-Z_][a-zA-Z0-9_]*$/) || content.include?(".")
    end

    def replace_literal_values(query)
      normalized = query.dup

      # Replace floating-point numbers FIRST (before integers) to avoid double replacement
      normalized = normalized.gsub(/(?<![a-zA-Z_])\b\d+\.\d+\b(?![a-zA-Z_])/, "?")

      # Replace integer literals with placeholders, but preserve identifiers containing numbers
      # Negative lookbehind/lookahead prevents replacing numbers in table/column names
      normalized = normalized.gsub(/(?<![a-zA-Z_])\b\d+\b(?![a-zA-Z_])/, "?")

      # Replace string literals (single quotes)
      normalized = normalized.gsub(/'(?:[^']|'')*'/, "?")

      # Replace double-quoted string literals (not protected identifiers)
      normalized = normalized.gsub(/"(?:[^"]|"")*"/, "?")

      # Handle boolean literals
      normalized = normalized.gsub(/\b(true|false)\b/i, "?")

      normalized
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
