require_relative "base_command"
require_relative "formatter"

module RailsPulse
  module CLI
    class Deployments < BaseCommand
      COLUMNS = [
        [ "Revision", 14, :short_revision ],
        [ "Started",  25, :started_at ],
        [ "Finished", 25, :finished_at ],
        [ "Compared", 17, :compared ]
      ].freeze

      desc "list", "List recorded deployments"
      long_desc <<~DESC
        Returns deployments ordered by most recent first. A deployment still in progress has
        no finish time.

        Each deployment is compared across the hours it ran in: the hour before it started
        against the hour after it finished. degraded when average or p95 response time is
        more than 1.5x and at least 50ms worse afterwards, or the error rate more than 1.25x
        and at least a percentage point worse; insufficient_data when either hour had fewer
        than 10 requests; pending until the hour after has been summarized, or unavailable
        when it never will be because SummaryJob is not running.

        Filter by time window (ISO 8601):
          --since 2026-06-01T00:00:00Z
          --until 2026-06-01T23:59:59Z

        Find a deployment by its full revision or the start of one:
          --revision a1b2c3d

        Use --json to get the full revision, duration, metadata and per-metric comparison.
      DESC
      option :limit,  type: :numeric, default: 25,    desc: "Max records to return (1–500)"
      option :offset, type: :numeric, default: 0,     desc: "Number of records to skip (for pagination)"
      option :since,  type: :string,                  desc: "Return deployments started at or after this time (ISO 8601)"
      option :until,  type: :string,                  desc: "Return deployments started at or before this time (ISO 8601)"
      option :revision, type: :string,                desc: "Full revision or the start of one"
      option :json,   type: :boolean, default: false, desc: "Output raw JSON including meta envelope"
      def list
        with_error_handling do
          params = { limit: options[:limit], offset: options[:offset] }
          params[:since] = options[:since] if options[:since]
          params[:until] = options[:until] if options[:until]
          params[:revision] = options[:revision] if options[:revision]
          result = client.get("/deployments", params)
          (result["data"] || []).each { |row| row["compared"] = row.dig("comparison", "outcome") } unless options[:json]
          Formatter.render(result, json: options[:json], columns: COLUMNS)
        end
      end
    end
  end
end
