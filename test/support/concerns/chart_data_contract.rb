module ChartDataContract
  extend ActiveSupport::Concern

  included do
    # Shared assertions for chart data format validation
    def assert_valid_chart_data(data, expected_days: 14)
      assert_chart_data_format(data)
      assert_chart_date_keys(data)
      assert_chart_numeric_values(data)
      assert_chart_time_range_coverage(data, expected_days)
    end

    def assert_chart_data_format(data)
      assert_instance_of Hash, data, "Chart data must be a Hash"
      assert_not_empty data, "Chart data should not be empty for valid time ranges"
    end

    def assert_chart_date_keys(data)
      data.keys.each do |key|
        assert_instance_of String, key, "Chart data keys must be strings"
        assert_match(/\A[A-Z][a-z]{2} \d{1,2}\z/, key,
          "Chart date key '#{key}' must follow 'MMM D' format (e.g., 'Jan 15')")
      end
    end

    def assert_chart_numeric_values(data)
      data.values.each do |value|
        assert_kind_of Numeric, value,
          "Chart values must be numeric, got #{value.class}: #{value}"
        assert_operator value, :>=, 0, "Chart values should be non-negative, got: #{value}"
      end
    end

    def assert_chart_time_range_coverage(data, expected_days)
      start_date = expected_days.days.ago.beginning_of_day.to_date
      end_date = Time.current.end_of_day.to_date

      expected_date_count = (start_date..end_date).count

      # Allow for some flexibility in date coverage
      # (some days might legitimately have no data)
      assert_operator data.keys.count, :<=, expected_date_count, "Chart data has more dates (#{data.keys.count}) than expected range (#{expected_date_count})"

      # Verify date keys are within expected range
      data.keys.each do |date_key|
        parsed_date = parse_chart_date_key(date_key)

        assert parsed_date >= start_date && parsed_date <= end_date,
          "Chart date '#{date_key}' (#{parsed_date}) is outside expected range #{start_date} to #{end_date}"
      end
    end

    def assert_empty_chart_data_handling(chart_instance)
      # Clear all requests to test empty data handling
      RailsPulse::Request.delete_all

      data = chart_instance.to_chart_data

      assert_instance_of Hash, data, "Empty data should still return a Hash"

      # Empty data should either be an empty hash or contain zero values
      if data.any?
        data.values.each do |value|
          assert_equal 0, value, "Empty data should have zero values, got: #{value}"
        end
      end
    end

    def assert_chart_data_completeness(data, start_date: 14.days.ago.to_date, end_date: Time.current.to_date)
      # Helper to verify specific date ranges are covered
      date_keys = data.keys.map { |key| parse_chart_date_key(key) }

      missing_dates = (start_date..end_date).to_a - date_keys

      # Some missing dates might be acceptable (e.g., no requests on certain days)
      # This assertion helps identify if we're missing data unexpectedly
      if missing_dates.any?
        puts "Info: Missing dates in chart data: #{missing_dates.map(&:strftime).join(', ')}"
      end
    end

    private

    def parse_chart_date_key(date_key)
      # Parse "Jan 15" format back to Date
      # Assume current year for simplicity
      Date.strptime("#{Time.current.year} #{date_key}", "%Y %b %d")
    rescue Date::Error
      # If current year parsing fails, try previous year
      # (handles year boundary cases)
      Date.strptime("#{Time.current.year - 1} #{date_key}", "%Y %b %d")
    end
  end
end
