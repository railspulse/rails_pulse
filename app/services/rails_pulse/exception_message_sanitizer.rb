module RailsPulse
  # Strips PII from exception messages before they are persisted or exported.
  #
  # Extracted from ExceptionCaptureService so the same filtering applies to
  # occurrence rows, job-run failure messages, and anything that ships a
  # message off the machine (see RailsPulse::Exceptions::RawData).
  #
  # Three layers, applied in order:
  #
  # 1. Adapter-specific cleanup for ActiveRecord::StatementInvalid — the
  #    driver error is kept, the offending statement and any literal values
  #    the database echoes back (PG `DETAIL: Key (col)=(val)`, MySQL
  #    `Duplicate entry 'val'`) are redacted.
  # 2. `key=value` / `key: value` / `"key":"value"` pairs anywhere in the
  #    text whose key matches the host's `config.filter_parameters` — the
  #    same rules Rails applies to logged params, so `password=hunter2` and
  #    `token: abc` are masked without any extra configuration.
  # 3. An optional host hook, `config.exception_message_filter`, for anything
  #    the generic rules cannot know about.
  class ExceptionMessageSanitizer
    MAX_LENGTH = 500
    FILTERED = "[FILTERED]".freeze

    # Matches `key=value`, `key: value`, `'key' => value` and JSON-style
    # `"key":"value"` fragments in free text. A bare `:` only counts as a
    # separator after a quoted key or when followed by whitespace, so URL
    # schemes (`https://…`) and clock times (`12:30`) are not read as pairs.
    # The value is a quoted string (with escapes) or a run of characters up
    # to the next delimiter — including `&` and `?`, so query strings split
    # per key. An unquoted value may not end right before another `=` or `:`
    # (atomic, so `Error: token: x` is not read as `Error` = `token`), but
    # may contain `://` so URLs survive as one value.
    KEY_VALUE_PAIR = /
      (?<lead>["'])?
      (?<key>[A-Za-z_][\w.\-\[\]]*)
      (?(<lead>)\k<lead>)
      (?<sep>\s*=>\s*|\s*=\s*|\s*:\s+|(?(<lead>):|(?!)))
      (?<value>
        "(?:[^"\\]|\\.)*"
        | '(?:[^'\\]|\\.)*'
        | (?>(?:[^\s,;)\]}&\#?=:]|:(?=\/\/))+)(?![=:]|\s*=>)
      )
    /x

    class << self
      def call(message, statement_invalid: false, exception: nil)
        new(message, statement_invalid: statement_invalid, exception: exception).call
      end

      def for_exception(exception)
        call(exception.message.to_s, statement_invalid: statement_invalid?(exception), exception: exception)
      end

      private

      # ActiveRecord may not be loaded in every host context this runs in.
      def statement_invalid?(exception)
        defined?(ActiveRecord::StatementInvalid) && exception.is_a?(ActiveRecord::StatementInvalid)
      end
    end

    def initialize(message, statement_invalid: false, exception: nil)
      @message = message.to_s
      @statement_invalid = statement_invalid
      @exception = exception
    end

    def call
      message = @message
      message = redact_statement_invalid(message) if @statement_invalid
      message = filter_key_value_pairs(message)
      message = apply_custom_filter(message)
      message.truncate(MAX_LENGTH)
    end

    private

    def redact_statement_invalid(message)
      # Strip the appended SQL statement, which embeds the offending query
      # including literal PII values.
      message = message.split("\n").first.to_s
      message = message.sub(/\s*:\s*(?:INSERT|UPDATE|DELETE|SELECT)\b.*/i, "")
      # PostgreSQL: DETAIL: Key (email)=(alice@example.com) already exists.
      message = message.gsub(/DETAIL:\s*Key\s*\([^)]*\)=\([^)]*\)/, "DETAIL: Key (…)=(…)")
      # MySQL puts the offending value on the first line, ahead of the SQL:
      # Duplicate entry 'alice@example.com' for key 'index_users_on_email'
      message.gsub(/Duplicate entry '(?:[^'\\]|\\.)*'/i, "Duplicate entry '#{FILTERED}'")
    end

    # Rails' ParameterFilter only masks by key, so on its own it does nothing
    # for a message like "login failed password=hunter2". Scan the text for
    # key/value fragments and ask the filter about each key individually —
    # this reuses the host's exact matching rules (substring, regexp, and
    # proc filters alike).
    def filter_key_value_pairs(message)
      filter = parameter_filter
      return message unless filter

      # A host that filters a key literally named "message" wants the whole
      # thing gone; honour that before looking inside it.
      whole = filter.filter_param("message", message)
      return whole unless whole.equal?(message)

      message.gsub(KEY_VALUE_PAIR) do
        match = Regexp.last_match
        key   = match[:key]
        value = match[:value]

        if filter.filter(key => value)[key] == value
          match[0]
        else
          lead = match[:lead].to_s
          "#{lead}#{key}#{lead}#{match[:sep]}#{FILTERED}"
        end
      end
    end

    def apply_custom_filter(message)
      hook = custom_filter
      return message unless hook

      result = hook.arity == 1 ? hook.call(message) : hook.call(message, @exception)
      result.to_s
    rescue => e
      # The hook exists to remove sensitive data; if it blows up, storing the
      # unfiltered message would defeat its purpose. Fail closed.
      RailsPulse.logger.warn("[RailsPulse] exception_message_filter raised #{e.class}: #{e.message}; message redacted")
      FILTERED
    end

    def parameter_filter
      patterns = filter_parameters
      return nil if patterns.blank?
      return nil unless defined?(ActiveSupport::ParameterFilter)

      ActiveSupport::ParameterFilter.new(patterns)
    end

    def filter_parameters
      Rails.application.config.filter_parameters
    rescue
      []
    end

    def custom_filter
      hook = RailsPulse.configuration&.exception_message_filter
      hook if hook.respond_to?(:call)
    rescue
      nil
    end
  end
end
