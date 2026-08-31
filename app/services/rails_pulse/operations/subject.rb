module RailsPulse
  module Operations
    # Normalizes the different things a caller can ask about — a Route, Query or
    # Job record, or the symbol :requests for the overall application rollup —
    # into the (summarizable_type, summarizable_id) pair the summaries table is
    # keyed by.
    #
    # This exists so callers of the Operations API never have to know how
    # summaries are stored. It is the one place that knows about the
    # summarizable_id = 0 convention used for the overall request rollup.
    class Subject
      SUPPORTED_TYPES = %w[
        RailsPulse::Route
        RailsPulse::Query
        RailsPulse::Job
        RailsPulse::Request
        RailsPulse::ExceptionGroup
      ].freeze

      # The overall-request rollup is stored with a sentinel id rather than a
      # real record, so it needs its own constant.
      OVERALL_REQUESTS_ID = 0

      # Exception summaries use the same sentinel for their all-groups rollup.
      OVERALL_ROLLUP_ID = 0

      attr_reader :type, :id, :record

      # @param subject [RailsPulse::Route, RailsPulse::Query, RailsPulse::Job, Symbol]
      #   a record, or :requests for the overall application rollup
      # @return [Subject]
      # @raise [ArgumentError] if the subject is not something summaries are kept for
      def self.wrap(subject)
        return subject if subject.is_a?(self)

        if subject == :requests
          return new(type: "RailsPulse::Request", id: OVERALL_REQUESTS_ID, record: nil)
        end

        if subject == :exceptions
          return new(type: "RailsPulse::ExceptionGroup", id: OVERALL_ROLLUP_ID, record: nil)
        end

        type = subject.class.name

        unless SUPPORTED_TYPES.include?(type)
          raise ArgumentError,
            "unsupported subject #{type.inspect} — expected a Route, Query, Job, or :requests"
        end

        new(type: type, id: subject.id, record: subject)
      end

      def initialize(type:, id:, record:)
        @type   = type
        @id     = id
        @record = record
      end

      # Summaries for this subject, unscoped by period.
      def summaries
        RailsPulse::Summary.where(summarizable_type: type, summarizable_id: id)
      end

      def overall_requests?
        type == "RailsPulse::Request" && id == OVERALL_REQUESTS_ID
      end

      def overall_exceptions?
        type == "RailsPulse::ExceptionGroup" && id == OVERALL_ROLLUP_ID
      end

      # Short human label, used in finding messages and API output.
      def label
        return "All requests" if overall_requests?
        return "All exceptions" if overall_exceptions?

        case type
        when "RailsPulse::Route" then record&.path
        when "RailsPulse::Query" then record&.normalized_sql
        when "RailsPulse::Job"   then record&.name
        when "RailsPulse::ExceptionGroup" then record&.exception_class
        end.presence || "#{type.demodulize} ##{id}"
      end

      def ==(other)
        other.is_a?(Subject) && other.type == type && other.id == id
      end
      alias eql? ==

      def hash
        [ type, id ].hash
      end
    end
  end
end
