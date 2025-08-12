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
      normalized = query.dup

      # Handle IN clauses with multiple values - replace content but preserve structure
      normalized = normalized.gsub(/\bIN\s*\(\s*([^)]+)\)/i) do |match|
        content = $1
        # Count commas to determine number of values
        value_count = content.split(",").length
        placeholders = Array.new(value_count, "?").join(", ")
        "IN (#{placeholders})"
      end

      # Handle BETWEEN clauses
      normalized = normalized.gsub(/\bBETWEEN\s+\?\s+AND\s+\?/i, "BETWEEN ? AND ?")

      normalized
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
