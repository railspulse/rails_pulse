module RailsPulse
  module Api
    module V1
      class JobsController < BaseController
        STATUSES = %w[failed].freeze

        # Finest first. Hourly summaries are pruned by
        # config.hourly_summary_retention, so a window older than that is
        # answered from daily rows rather than reported as empty.
        GRANULARITIES = [
          { period_type: "hour", step: 1.hour },
          { period_type: "day",  step: 1.day }
        ].freeze

        def index
          parsed_range = time_range
          return unless parsed_range
          since_start, until_end = parsed_range

          collection = RailsPulse::Job.all.order(:name)
          collection = collection.where(name: params[:job]) if params[:job].present?

          status = params[:status].presence
          if status && !STATUSES.include?(status)
            return render json: { error: "Invalid status. Valid values: #{STATUSES.join(', ')}" }, status: :bad_request
          end
          collection = collection.with_failures if status == "failed"

          return render_windowed(collection, since_start, until_end) if since_start || until_end

          data, meta = paginated(collection)
          render json: { data: data.map { |job| JobSerializer.serialize(job) }, meta: meta }
        end

        private

        # Job rows carry lifetime counters, so a windowed question is answered
        # from the per-job summaries the summary service writes each period.
        # Returning the lifetime numbers instead would answer a different
        # question without saying so.
        def render_windowed(collection, since_start, until_end)
          until_end ||= Time.current
          since_start ||= until_end - 24.hours

          granularity = GRANULARITIES.first
          from, to = snap(since_start, until_end, granularity[:step])
          rows = summary_rows(collection, granularity[:period_type], from, to)

          # An empty finest-granularity result usually means the window predates
          # hourly retention rather than that nothing ran.
          if rows.empty?
            granularity = GRANULARITIES.last
            from, to = snap(since_start, until_end, granularity[:step])
            rows = summary_rows(collection, granularity[:period_type], from, to)
          end

          jobs = RailsPulse::Job.where(id: rows.map(&:summarizable_id)).index_by(&:id)
          page = rows.sort_by { |row| jobs[row.summarizable_id]&.name.to_s }.drop(offset).first(limit)

          data = page.filter_map do |row|
            job = jobs[row.summarizable_id]
            JobSerializer.serialize(job, stats: stats_for(row)) if job
          end

          render json: {
            data: data,
            meta: {
              total: rows.size, limit: limit, offset: offset,
              window: { since: from.utc.iso8601, until: to.utc.iso8601, period_type: granularity[:period_type] }
            }
          }
        end

        def summary_rows(collection, period_type, from, to)
          RailsPulse::Summary
            .for_jobs
            .where(period_type: period_type, period_start: from...to)
            .where(summarizable_id: collection.select(:id))
            .group(:summarizable_id)
            .select(
              "summarizable_id, COUNT(*) AS periods, SUM(count) AS runs, SUM(error_count) AS failures, " \
              "SUM(total_duration) AS total_duration, MIN(min_duration) AS min_duration, " \
              "MAX(max_duration) AS max_duration, MAX(p95_duration) AS p95_duration, " \
              "MAX(p99_duration) AS p99_duration"
            )
            .to_a
        end

        def stats_for(row)
          runs = row.runs.to_i
          stats = {
            runs_count:     runs,
            failures_count: row.failures.to_i,
            failure_rate:   runs > 0 ? ((row.failures.to_f / runs) * 100).round(2) : 0.0,
            avg_duration:   runs > 0 ? (row.total_duration.to_f / runs).round(2) : nil,
            min_duration:   row.min_duration&.to_f&.round(2),
            max_duration:   row.max_duration&.to_f&.round(2)
          }

          # A percentile is a property of a distribution, and the distribution
          # behind each period is not kept, so percentiles from several periods
          # cannot be combined. They are reported only when one period covers
          # the whole window.
          if row.periods.to_i == 1
            stats[:p95_duration] = row.p95_duration&.to_f&.round(2)
            stats[:p99_duration] = row.p99_duration&.to_f&.round(2)
          else
            stats[:percentiles_note] =
              "Omitted: the window spans #{row.periods} summary periods, which cannot be combined into one percentile. " \
              "Request a window covering a single period for p95 and p99."
          end

          stats
        end

        # Summaries are written per whole period, so a window is widened to the
        # period boundaries it touches and the response reports what was read.
        def snap(from, to, step)
          seconds = step.to_i
          floor = Time.at((from.to_i / seconds) * seconds).utc
          ceil = Time.at(((to.to_f / seconds).ceil) * seconds).utc
          [ floor, ceil ]
        end
      end
    end
  end
end
