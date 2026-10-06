module RailsPulse
  module Api
    module V1
      # Exception groups: one row per distinct exception class and location,
      # with its lifecycle status and how often and how recently it fired.
      # This is what an agent or a desktop notifier reads to answer "what is
      # broken right now?" — the raw 5xx request list under /requests cannot
      # say which exception it was, only that the response failed.
      class ExceptionsController < BaseController
        STATUSES     = RailsPulse::ExceptionGroup::STATUSES
        SORT_COLUMNS = %w[last_seen_at first_seen_at occurrence_count].freeze
        DEFAULT_OCCURRENCES = 5
        MAX_OCCURRENCES     = 20

        rescue_from ActiveRecord::RecordNotFound do
          render json: { error: "No exception group with id #{params[:id]}" }, status: :not_found
        end

        def index
          parsed_range = time_range
          return unless parsed_range
          since_start, until_end = parsed_range

          status = params[:status].presence
          if status && !STATUSES.include?(status)
            return render json: { error: "Invalid status. Valid values: #{STATUSES.join(', ')}" }, status: :bad_request
          end

          sort = params[:sort].presence || "last_seen_at"
          unless SORT_COLUMNS.include?(sort)
            return render json: { error: "Invalid sort. Valid values: #{SORT_COLUMNS.join(', ')}" }, status: :bad_request
          end

          collection = RailsPulse::ExceptionGroup.order(sort => :desc, id: :desc)
          collection = collection.where(status: status) if status
          collection = collection.where(fingerprint: params[:fingerprint]) if params[:fingerprint].present?
          collection = collection.where(last_seen_at: since_start..) if since_start
          collection = collection.where(last_seen_at: ..until_end) if until_end
          collection = apply_search(collection)

          data, meta = paginated(collection)
          render json: { data: data.map { |group| ExceptionGroupSerializer.serialize(group) }, meta: meta }
        end

        # One group with its most recent occurrences: backtrace, request and
        # params for each. This is what an agent reads to find the cause,
        # so it carries everything the dashboard's exception page shows.
        def show
          group = RailsPulse::ExceptionGroup.find(params[:id])
          count = integer_param(:occurrences, DEFAULT_OCCURRENCES, 1..MAX_OCCURRENCES)
          occurrences = group.occurrences.order(occurred_at: :desc, id: :desc).limit(count)

          render json: {
            data: ExceptionGroupSerializer.serialize(group).merge(
              occurrences: occurrences.map { |occurrence| ExceptionOccurrenceSerializer.serialize(occurrence) }
            )
          }
        end

        private

        # Case-insensitive substring match on the exception class or the
        # app-code location it was raised from.
        def apply_search(scope)
          return scope unless params[:search].present?

          term = RailsPulse::LikePattern.containing(params[:search].to_s.downcase)
          scope.where(
            "LOWER(exception_class) LIKE :term #{RailsPulse::LikePattern::CLAUSE} " \
            "OR LOWER(location) LIKE :term #{RailsPulse::LikePattern::CLAUSE}",
            term: term
          )
        end
      end
    end
  end
end
