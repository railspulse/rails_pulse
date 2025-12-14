require "test_helper"

module RailsPulse
  module Routes
    module Cards
      class AverageResponseTimesTest < ActiveSupport::TestCase
        setup do
          @route = rails_pulse_routes(:api_users)

          # Create summaries for testing
          14.times do |i|
            RailsPulse::Summary.create!(
              summarizable: @route,
              summarizable_type: "RailsPulse::Route",
              period_type: "day",
              period_start: (14 - i).days.ago.beginning_of_day,
              period_end: (14 - i).days.ago.end_of_day,
              avg_duration: 100 + (i * 10),
              min_duration: 50,
              max_duration: 200,
              count: 100,
              error_count: 0,
              success_count: 100
            )
          end
        end

        test "should work when ActiveRecord.default_timezone is :utc" do
          # Ensure timezone is set to :utc (default)
          original_timezone = ActiveRecord.default_timezone
          ActiveRecord.default_timezone = :utc

          card = AverageResponseTimes.new(route: @route)

          # Should not raise an error
          assert_nothing_raised do
            result = card.to_metric_card

            assert_not_nil result
            assert_equal "average_response_times", result[:id]
          end
        ensure
          ActiveRecord.default_timezone = original_timezone
        end

        test "should work when ActiveRecord.default_timezone is :local" do
          # This test captures issue #81
          # Groupdate requires ActiveRecord.default_timezone to be :utc
          # but many applications use :local
          original_timezone = ActiveRecord.default_timezone
          ActiveRecord.default_timezone = :local

          card = AverageResponseTimes.new(route: @route)

          # This should work but currently fails with:
          # Groupdate::Error (ActiveRecord.default_timezone must be :utc to use Groupdate)
          assert_nothing_raised do
            result = card.to_metric_card

            assert_not_nil result
            assert_equal "average_response_times", result[:id]
          end
        ensure
          ActiveRecord.default_timezone = original_timezone
        end

        # TODO: Test that card returns average response time for route in time range
        # TODO: Test that card filters requests by route_id
        # TODO: Test that card compares to previous period
        # TODO: Test that card shows percentage change
        # TODO: Test that card indicates if performance improved or degraded
        # TODO: Test that card handles routes with no requests
      end
    end
  end
end
