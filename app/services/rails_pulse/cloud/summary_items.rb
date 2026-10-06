module RailsPulse
  module Cloud
    # The `summary` items for one hour, built from that hour's
    # rails_pulse_summaries rows. Nothing is returned for an hour SummaryJob
    # has not written, so a partial hour is never sent.
    #
    # Each item names its subject by content (a route's pattern, a query's
    # hash, a job's class), never by a local id, and carries no field the
    # sync contract does not list. Route and query tags are not sent: they
    # are free-form and can name customers.
    class SummaryItems
      ROUTE_LIMIT = 2_000
      QUERY_LIMIT = 2_000
      UNMATCHED_LIMIT = 20
      CALL_SITES = 2

      # The key of the item that combines everything past a limit.
      OTHER = "*".freeze

      DURATIONS = %i[
        avg_duration min_duration max_duration p50_duration p95_duration p99_duration stddev_duration total_duration
      ].freeze
      REQUEST_COUNTS = %i[error_count status_2xx status_3xx status_4xx status_5xx].freeze
      JOB_COUNTS = %i[error_count success_count].freeze

      # @param period_start [Time] the start of an hour, in the application's zone
      # @param adapter [String] the Rails Pulse database adapter, which decides
      #   how a double-quoted SQL token is read
      def initialize(period_start, adapter:, route_patterns: RoutePattern.new, limits: {})
        @period_start = period_start
        @adapter = adapter
        @route_patterns = route_patterns
        @route_limit = limits.fetch(:route, ROUTE_LIMIT)
        @query_limit = limits.fetch(:query, QUERY_LIMIT)
        @unmatched_limit = limits.fetch(:unmatched, UNMATCHED_LIMIT)
      end

      def items
        return [] unless summarized?

        requests_items + route_items + unmatched_items + query_items + job_items + exception_items
      end

      def summarized?
        rows_of("RailsPulse::Request").any? { |row| row.summarizable_id.zero? }
      end

      private

      def rows
        @rows ||= Summary.where(period_type: "hour", period_start: @period_start).to_a.group_by(&:summarizable_type)
      end

      def rows_of(type)
        rows.fetch(type, [])
      end

      def item(kind, fields)
        { type: "summary", kind: kind, period_start: @period_start.utc.iso8601, **fields }
      end

      def metrics(row_or_rows, counts)
        group = Array(row_or_rows)
        if group.size == 1
          row = group.first
          { count: row[:count].to_i, **DURATIONS.index_with { |column| row[column]&.to_f }, **counts.index_with { |column| row[column].to_i } }
        else
          CombinedMetrics.of(group, counts: counts)
        end
      end

      # -- Requests and routes -------------------------------------------

      def requests_items
        overall = rows_of("RailsPulse::Request").find { |row| row.summarizable_id.zero? }
        [ item("requests", metrics(overall, REQUEST_COUNTS)) ]
      end

      # Route rows split into recognised routes and requests the router did
      # not match, which are stored without a controller action.
      def route_rows
        @route_rows ||= begin
          route_summaries = rows_of("RailsPulse::Route").select { |row| row.count.to_i.positive? }
          routes = Route.where(id: route_summaries.map(&:summarizable_id)).index_by(&:id)
          route_summaries.filter_map do |row|
            route = routes[row.summarizable_id]
            [ route, row ] if route
          end.partition { |route, _| route.controller_action.present? }
        end
      end

      def route_items
        groups = route_rows.first.group_by do |route, _|
          [ @route_patterns.path_for(route.path, route.controller_action), route.controller_action ]
        end

        ranked = groups.sort_by { |key, members| [ -members.sum { |_, row| row.total_duration.to_f }, key.map(&:to_s) ] }
        kept, rest = ranked.first(@route_limit), ranked.drop(@route_limit)

        items = kept.map do |(path, controller_action), members|
          methods = members.flat_map { |route, _| route.http_methods_list }.uniq.sort
          item("route", path: path, controller_action: controller_action, http_methods: methods,
                        **metrics(members.map(&:last), REQUEST_COUNTS))
        end
        items << item("route", path: OTHER, controller_action: nil, http_methods: [], **metrics(rest.flat_map { |_, members| members.map(&:last) }, REQUEST_COUNTS)) if rest.any?
        items
      end

      def unmatched_items
        groups = route_rows.last.group_by { |route, _| PathPrefix.for(route.path) }
        ranked = groups.sort_by { |prefix, members| [ -members.sum { |_, row| row.count.to_i }, prefix ] }
        kept, rest = ranked.first(@unmatched_limit), ranked.drop(@unmatched_limit)

        items = kept.map { |prefix, members| item("unmatched", path_prefix: prefix, **metrics(members.map(&:last), REQUEST_COUNTS)) }
        items << item("unmatched", path_prefix: PathPrefix::OTHER, **metrics(rest.flat_map { |_, members| members.map(&:last) }, REQUEST_COUNTS)) if rest.any?
        items
      end

      # -- Queries -------------------------------------------------------

      def query_items
        query_summaries = rows_of("RailsPulse::Query").select { |row| row.count.to_i.positive? }
        queries = Query.where(id: query_summaries.map(&:summarizable_id)).index_by(&:id)
        ranked = query_summaries.select { |row| queries[row.summarizable_id] }.sort_by { |row| [ -row.total_duration.to_f, row.summarizable_id ] }
        kept, rest = ranked.first(@query_limit), ranked.drop(@query_limit)
        sites = call_sites(kept.map(&:summarizable_id))

        items = kept.map do |row|
          query = queries[row.summarizable_id]
          shape = QueryShape.for_adapter(query.normalized_sql, @adapter)
          item("query", hashed_sql: query.hashed_sql, label: shape.label, sql_shape: shape.sql_shape,
                        call_sites: sites.fetch(query.id, []), **metrics(row, []))
        end
        items << item("query", hashed_sql: OTHER, label: "Other queries", sql_shape: nil, call_sites: [], **metrics(rest, [])) if rest.any?
        items
      end

      # The two code locations that ran each query most often in the hour.
      # Only paths inside the application are sent: a location outside it is
      # stored as an absolute path, which can name the server's directories.
      def call_sites(query_ids)
        return {} if query_ids.empty?

        Operation
          .where(occurred_at: @period_start...(@period_start + 1.hour), query_id: query_ids)
          .where.not(codebase_location: nil)
          .group(:query_id, :codebase_location)
          .count
          .select { |(_, location), _| application_path?(location) }
          .group_by { |(query_id, _), _| query_id }
          .transform_values do |entries|
            entries.sort_by { |(_, location), count| [ -count, location ] }.first(CALL_SITES).map { |(_, location), _| location }
          end
      end

      def application_path?(location)
        location.present? && !location.start_with?("/") && !location.include?("..") && !location.match?(/\A[A-Za-z]:/)
      end

      # -- Jobs and exceptions ---------------------------------------------

      def job_items
        job_summaries = rows_of("RailsPulse::Job").select { |row| row.count.to_i.positive? }
        jobs = Job.where(id: job_summaries.map(&:summarizable_id)).index_by(&:id)
        job_summaries.filter_map do |row|
          job = jobs[row.summarizable_id]
          next unless job

          item("job", name: job.name, queue_name: job.queue_name, **metrics(row, JOB_COUNTS))
        end
      end

      # Exceptions have no duration, so these items carry only a count.
      def exception_items
        summaries = rows_of("RailsPulse::ExceptionGroup")
        overall, per_group = summaries.partition { |row| row.summarizable_id.zero? }
        groups = ExceptionGroup.where(id: per_group.map(&:summarizable_id)).pluck(:id, :fingerprint).to_h

        items = per_group.filter_map do |row|
          fingerprint = groups[row.summarizable_id]
          item("exception_group", fingerprint: fingerprint, count: row.count.to_i) if fingerprint
        end
        overall.each { |row| items << item("exceptions", count: row.count.to_i) }
        items
      end
    end
  end
end
