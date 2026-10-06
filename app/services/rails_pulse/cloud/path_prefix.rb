module RailsPulse
  module Cloud
    # The prefix a request the router did not recognise is sent to Cloud
    # under. The stored path is the raw URL, which can carry tokens, IDs or
    # email addresses, so only a first segment that looks like code
    # (`/wp-admin`, `/.env`) survives, and everything after it becomes `/*`.
    #
    #   PathPrefix.for("/wp-admin/setup.php")          # => "/wp-admin/*"
    #   PathPrefix.for("/wp-login.php")                # => "/wp-login.php"
    #   PathPrefix.for("/users/jane.doe@example.com")  # => "/users/*"
    #   PathPrefix.for("/8f3a9c1e2b7d")                # => "/*"
    module PathPrefix
      # Every prefix past the busiest in an hour is combined under this one.
      OTHER = "*".freeze

      SAFE_SEGMENT = /\A[A-Za-z0-9._-]{1,40}\z/
      DIGIT_RUN = /\d{4}/
      HEXADECIMAL = /\A\h{8,}\z/
      UUID = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/
      EMAIL_MARKERS = [ "@", "%40" ].freeze

      module_function

      def for(path)
        path = path.to_s
        return "/" if path == "/"

        first, rest = path.delete_prefix("/").split("/", 2)
        return "/*" unless safe_segment?(first)

        rest.nil? ? "/#{first}" : "/#{first}/*"
      end

      # True for a path segment that reads as part of the application rather
      # than something a user supplied.
      def safe_segment?(segment)
        return false unless segment.is_a?(String) && segment.match?(SAFE_SEGMENT)

        !identifier?(segment)
      end

      def identifier?(segment)
        segment.match?(DIGIT_RUN) ||
          segment.match?(HEXADECIMAL) ||
          segment.match?(UUID) ||
          EMAIL_MARKERS.any? { |marker| segment.include?(marker) }
      end
    end
  end
end
