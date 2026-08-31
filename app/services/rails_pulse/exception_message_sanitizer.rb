module RailsPulse
  # Strips PII from exception messages before they are persisted or exported.
  #
  # Extracted from ExceptionCaptureService so the same filtering applies to
  # occurrence rows and to anything that ships a message off the machine
  # (see RailsPulse::Exceptions::RawData).
  class ExceptionMessageSanitizer
    MAX_LENGTH = 500

    class << self
      def call(message, statement_invalid: false)
        new(message, statement_invalid: statement_invalid).call
      end

      def for_exception(exception)
        call(exception.message.to_s, statement_invalid: statement_invalid?(exception))
      end

      private

      # ActiveRecord may not be loaded in every host context this runs in.
      def statement_invalid?(exception)
        defined?(ActiveRecord::StatementInvalid) && exception.is_a?(ActiveRecord::StatementInvalid)
      end
    end

    def initialize(message, statement_invalid: false)
      @message = message.to_s
      @statement_invalid = statement_invalid
    end

    def call
      message = @message

      # Strip the appended SQL statement from ActiveRecord::StatementInvalid
      # which embeds the offending query including literal PII values.
      if @statement_invalid
        message = message.split("\n").first.to_s
        message = message.sub(/\s*:\s*(?:INSERT|UPDATE|DELETE|SELECT)\b.*/i, "")
        # Redact DETAIL: Key (col)=(value) clauses from PG unique violations
        message = message.gsub(/DETAIL:\s*Key\s*\([^)]*\)=\([^)]*\)/, "DETAIL: Key (…)=(…)")
      end

      # Apply Rails' parameter filter in key=value mode
      if defined?(ActiveSupport::ParameterFilter) && (patterns = filter_parameters).any?
        message = ActiveSupport::ParameterFilter.new(patterns).filter_param("message", message)
      end

      message.truncate(MAX_LENGTH)
    end

    private

    def filter_parameters
      Rails.application.config.filter_parameters
    rescue
      []
    end
  end
end
