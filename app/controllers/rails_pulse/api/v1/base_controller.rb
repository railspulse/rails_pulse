module RailsPulse
  module Api
    module V1
      # Read-only JSON API for the rails-pulse CLI, the MCP server, CI scripts
      # and coding agents. Authenticated by config.api_token alone: the
      # dashboard session is never consulted, and with no token configured
      # every request is refused.
      class BaseController < RailsPulse::ApplicationController
        skip_before_action :authenticate_rails_pulse_user!
        skip_before_action :set_show_non_tagged_default
        skip_before_action :set_onboarding_state
        skip_before_action :load_deployment_markers

        # Prepended so it runs ahead of the inherited require_current_schema!:
        # the schema report lists missing tables and columns and must not be
        # served to anonymous callers.
        prepend_before_action :authenticate_api_token!

        # After authentication, so an anonymous caller learns nothing from
        # which of its parameters were refused.
        before_action :validate_params!

        # Every action is a GET read from the query string. Rails would
        # otherwise copy a JSON request's parameters into a hash named after
        # the controller (`route`, `job`), which collides with the filters of
        # the same name whenever a client sends Content-Type: application/json.
        wrap_parameters false

        # Parameters every endpoint reads as one string. A repeated or nested
        # one (`search[]=x`) is refused rather than reaching a String method.
        SCALAR_PARAMS = %i[limit offset min_requests occurrences since until search route status sort job period at].freeze
        INTEGER_PARAMS = %i[limit offset min_requests occurrences].freeze

        # Past any real table, and inside a 64-bit integer on every adapter.
        MAX_INTEGER = 1_000_000_000

        # A date, optionally a time, optionally a zone. Time.parse would also
        # take "10" as the 10th of this month, which is not a window anyone
        # asked for.
        ISO8601 = /\A\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)?(?:Z|[+-]\d{2}:?\d{2})?\z/i

        private

        def authenticate_api_token!
          token = RailsPulse.configuration.api_token.to_s
          provided = request.headers["X-Rails-Pulse-Token"].to_s
          return if token.present? && ActiveSupport::SecurityUtils.secure_compare(provided, token)

          render json: { error: "Unauthorized" }, status: :unauthorized
        end

        # The schema report picks its format from the request; API callers
        # rarely send an Accept header, so answer JSON regardless.
        def require_current_schema!
          request.format = :json
          super
        end

        def validate_params!
          SCALAR_PARAMS.each do |name|
            value = params[name]
            next if value.nil? || value.is_a?(String)

            return render_bad_request("'#{name}' must be a single value")
          end

          INTEGER_PARAMS.each do |name|
            value = params[name]
            next if value.blank? || value.match?(/\A\d+\z/)

            return render_bad_request("'#{name}' must be a whole number")
          end

          @since_time = parse_time_param(:since)
          return if performed?
          @until_time = parse_time_param(:until)
          return if performed?

          if @since_time && @until_time && @until_time <= @since_time
            render_bad_request("'until' must be later than 'since'")
          end
        end

        def render_bad_request(message)
          render json: { error: message }, status: :bad_request
        end

        def limit
          integer_param(:limit, 25, 1..500)
        end

        def offset
          integer_param(:offset, 0, 0..MAX_INTEGER)
        end

        def integer_param(name, default, range)
          params[name].blank? ? default : params[name].to_i.clamp(range)
        end

        # A time with no zone is read as UTC, so a window means the same thing
        # wherever the caller and the server are.
        def parse_time_param(name)
          value = params[name]
          return if value.blank?

          string = value.strip
          raise ArgumentError unless string.match?(ISO8601)

          ActiveSupport::TimeZone["UTC"].parse(string)
        rescue ArgumentError
          render_bad_request(
            "Invalid time format for '#{name}'. Use ISO 8601, such as 2026-09-24T12:00:00Z; " \
            "a time with no zone is read as UTC."
          )
        end

        # Parsed and checked by validate_params! before the action runs.
        def time_range
          [ @since_time, @until_time ]
        end

        def paginated(collection)
          total = collection.count
          data = collection.limit(limit).offset(offset)
          [ data, { total: total, limit: limit, offset: offset } ]
        end
      end
    end
  end
end
