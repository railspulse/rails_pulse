module RailsPulse
  # Builds LIKE patterns whose `_`, `%` and escape characters match literally.
  #
  # Every pattern built here must be used with CLAUSE appended to the LIKE
  # expression. SQLite has no default escape character, so `foo!_bar` without an
  # explicit ESCAPE matches a literal `!` while the `_` still wildcards, and the
  # comparison silently matches nothing. `!` is the escape character rather than
  # `\` because MySQL and PostgreSQL disagree on how a backslash is quoted.
  module LikePattern
    ESCAPE_CHARACTER = "!".freeze

    # Interpolated directly into SQL strings, so it must stay a literal.
    CLAUSE = "ESCAPE '#{ESCAPE_CHARACTER}'".freeze

    module_function

    # @param value [#to_s] user-supplied text to match anywhere in a column
    # @return [String] escaped pattern wrapped in leading and trailing wildcards
    def containing(value)
      "%#{escape(value)}%"
    end

    # @param value [#to_s] user-supplied text
    # @return [String] the text with LIKE metacharacters escaped
    def escape(value)
      ActiveRecord::Base.sanitize_sql_like(value.to_s, ESCAPE_CHARACTER)
    end
  end
end
