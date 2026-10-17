module RailsPulse
  # What share of the last day's traffic detail capture kept in full
  # (decision 0022), for all requests, one route or one query.
  #
  # Reads summaries and rollups only, never the requests table: an hour's
  # summary counts every request, the rollups count the ones folded, and the
  # difference was kept. That limits it to hours SummaryJob has summarized.
  #
  # The window starts at the first hour with any rollup, so hours from before
  # detail capture was turned on (when everything was kept) don't count. With
  # no rollup at all in the last day the rate is unknown: detail capture was
  # turned on too recently, or nothing is being folded.
  class DetailCaptureRate
    WINDOW = 24.hours

    # Above this share detail capture saves little of what it would store
    # without it; a slow threshold likely sits below typical timings.
    HIGH_SHARE = 0.25

    attr_reader :kept, :total

    # subject: nil for all requests, or a Route or Query
    def self.for(subject = nil, now: Time.current)
      return unless Rollup.table_available?

      new(subject, now).compute
    end

    # What to change when the share is high, e.g. "raise
    # request_thresholds[:slow] (700ms now) or query_thresholds[:slow] (100ms
    # now), or lower detail_capture_sample_rate (1% now)"
    def self.retune_advice(settings)
      advice = "raise request_thresholds[:slow] (#{settings.requests_slower_than.round}ms now) " \
               "or query_thresholds[:slow] (#{settings.queries_slower_than.round}ms now)"
      return advice unless settings.sample_rate.positive?

      "#{advice}, or lower detail_capture_sample_rate (#{(settings.sample_rate * 100).round(2).to_s.delete_suffix('.0')}% now)"
    end

    # "/reports (2,900 of 3,000), /search (400 of 1,200)", or nil when no
    # route kept anything
    def self.top_kept_routes_label(now: Time.current)
      routes = top_kept_routes(now: now).map do |route, kept, total|
        "#{route.path} (#{kept.to_fs(:delimited)} of #{total.to_fs(:delimited)})"
      end
      routes.join(", ").presence
    end

    # Routes keeping the most requests in the window, as
    # [[route, kept, total], ...], most kept first.
    def self.top_kept_routes(limit: 3, now: Time.current)
      return [] unless Rollup.table_available?

      new(nil, now).top_kept_routes(limit)
    end

    def initialize(subject, now)
      @subject = subject
      @now = now
    end

    def compute
      hours = summarized_hours
      return if hours.empty?

      @total = summaries.where(period_start: hours).sum(:count).to_i
      return if @total.zero?

      folded = rollups.where(period_start: hours).sum(:count).to_i
      @kept = [ @total - folded, 0 ].max
      self
    end

    def top_kept_routes(limit)
      hours = summarized_hours(Summary.for_routes)
      return [] if hours.empty?

      totals = Summary.for_routes.where(period_type: "hour", period_start: hours).group(:summarizable_id).sum(:count)
      folded = Rollup.where(rollupable_type: "RailsPulse::Route", period_start: hours).group(:rollupable_id).sum(:count)
      kept = totals.to_h { |id, total| [ id, [ total.to_i - folded[id].to_i, 0 ].max ] }

      top = kept.select { |_id, count| count.positive? }.max_by(limit) { |_id, count| count }
      routes = Route.where(id: top.map(&:first)).index_by(&:id)
      top.filter_map { |id, count| [ routes[id], count, totals[id].to_i ] if routes[id] }
    end

    def share
      kept.fdiv(total)
    end

    def high?
      share > HIGH_SHARE
    end

    # "17.7%", "under 0.1%"
    def share_label
      percent = share * 100
      return "under 0.1%" if percent.positive? && percent < 0.1

      "#{percent.round(1).to_s.delete_suffix('.0')}%"
    end

    private

    def window_start
      @window_start ||= (@now - WINDOW).beginning_of_hour
    end

    # Rollups for the current hour exist before its summary does, so the
    # hours come from the summaries.
    def summarized_hours(scope = subject_summaries)
      first_folded = Rollup.where(rollupable_type: rollupable_type, period_start: window_start..).minimum(:period_start)
      return [] unless first_folded

      Summary.where(period_type: "hour", period_start: first_folded..)
        .merge(scope)
        .distinct
        .pluck(:period_start)
    end

    def summaries
      Summary.where(period_type: "hour").merge(subject_summaries)
    end

    def subject_summaries
      @subject ? Summary.where(summarizable: @subject) : Summary.overall_requests
    end

    def rollups
      @subject ? Rollup.where(rollupable: @subject) : Rollup.where(rollupable_type: "RailsPulse::Route")
    end

    # A route or all requests starts at the first folded request anywhere,
    # not its own, so a route whose every request was kept still has a rate.
    def rollupable_type
      @subject.is_a?(Query) ? "RailsPulse::Query" : "RailsPulse::Route"
    end
  end
end
