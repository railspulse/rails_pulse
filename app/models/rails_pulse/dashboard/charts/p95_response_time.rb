module RailsPulse
  module Dashboard
    module Charts
      class P95ResponseTime
        def to_chart_data
          start_date = 2.weeks.ago.beginning_of_day

          # Performance optimization: Single query instead of N+1 queries (15 queries -> 1 query)
          # Fetch all requests for 2-week period, pre-sorted by date and duration
          # For optimal performance, ensure index exists: (occurred_at, duration)
          requests_by_day = RailsPulse::Request
            .where(occurred_at: start_date..)
            .select("occurred_at, duration, DATE(occurred_at) as request_date")
            .order("request_date, duration")
            .group_by { |r| r.request_date.to_date }

          # Generate all dates in range and calculate P95 for each
          (start_date.to_date..Time.current.to_date).each_with_object({}) do |date, hash|
            day_requests = requests_by_day[date] || []

            if day_requests.empty?
              p95_value = 0
            else
              # Calculate P95 from in-memory sorted array (already sorted by DB)
              count = day_requests.length
              p95_index = (count * 0.95).ceil - 1
              p95_value = day_requests[p95_index].duration.round(0)
            end

            formatted_date = date.strftime("%b %-d")
            hash[formatted_date] = p95_value
          end
        end
      end
    end
  end
end
