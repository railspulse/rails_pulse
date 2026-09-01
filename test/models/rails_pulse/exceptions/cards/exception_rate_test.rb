require "test_helper"

module RailsPulse
  module Exceptions
    module Cards
      # Raw occurrence counts rise with traffic. This card exists to separate
      # "the application got worse" from "the application got busier", so the
      # tests care most about the ratio moving independently of volume.
      class ExceptionRateTest < ActiveSupport::TestCase
        def setup
          ENV["TEST_TYPE"] = "functional"
          super
          RailsPulse::Summary.delete_all
          @now = Time.current
          travel_to @now
        end

        def teardown
          travel_back
          super
        end

        # Structure Tests

        test "card returns hash with required keys" do
          result = card.to_metric_card

          assert_kind_of Hash, result
          assert_equal "exceptions_rate", result[:id]
          assert_equal "exceptions", result[:context]
          assert_equal "Exception Rate", result[:title]
          assert_includes result.keys, :summary
          assert_includes result.keys, :chart_data
          assert_includes result.keys, :trend_icon
          assert_includes result.keys, :trend_amount
          assert_includes result.keys, :trend_text
          assert_includes result.keys, :period_stat
        end

        # Calculation Tests

        test "card divides occurrences by requests per thousand" do
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 20)
          create_summary("RailsPulse::Request", 1.day.ago, count: 4_000)

          assert_equal "5.0 per 1,000", card.to_metric_card[:summary]
        end

        test "card reports both raw totals in the period stat" do
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 20)
          create_summary("RailsPulse::Request", 1.day.ago, count: 4_000)

          assert_equal "20 raised · 4,000 requests", card.to_metric_card[:period_stat]
        end

        test "card sums every period in the window" do
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 5)
          create_summary("RailsPulse::ExceptionGroup", 2.days.ago, count: 5)
          create_summary("RailsPulse::Request", 1.day.ago, count: 500)
          create_summary("RailsPulse::Request", 2.days.ago, count: 500)

          assert_equal "10.0 per 1,000", card.to_metric_card[:summary]
        end

        test "card ignores per-group summaries and reads only the rollup" do
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 20)
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 999, summarizable_id: 42)
          create_summary("RailsPulse::Request", 1.day.ago, count: 4_000)

          assert_equal "5.0 per 1,000", card.to_metric_card[:summary]
        end

        test "rate falls when traffic grows faster than occurrences" do
          # Previous window: 10 per 1,000. Current window: 5 per 1,000, even
          # though the raw occurrence count went up.
          create_summary("RailsPulse::ExceptionGroup", 10.days.ago, count: 10)
          create_summary("RailsPulse::Request", 10.days.ago, count: 1_000)
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 15)
          create_summary("RailsPulse::Request", 1.day.ago, count: 3_000)

          result = card.to_metric_card

          assert_equal "trending-down", result[:trend_icon]
          assert_equal "50.0%", result[:trend_amount]
        end

        test "rate rises when occurrences grow faster than traffic" do
          create_summary("RailsPulse::ExceptionGroup", 10.days.ago, count: 10)
          create_summary("RailsPulse::Request", 10.days.ago, count: 1_000)
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 40)
          create_summary("RailsPulse::Request", 1.day.ago, count: 2_000)

          result = card.to_metric_card

          assert_equal "trending-up", result[:trend_icon]
          assert_equal "100.0%", result[:trend_amount]
        end

        # Edge Cases

        test "card reads zero with no summaries at all" do
          result = card.to_metric_card

          assert_equal "0.0 per 1,000", result[:summary]
          assert_empty result[:chart_data].values.map { |v| v[:value] }.reject(&:zero?)
        end

        test "card reads zero rather than dividing by zero requests" do
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 20)

          result = card.to_metric_card

          assert_equal "0.0 per 1,000", result[:summary]
          assert_equal card.send(:period_date_range), result[:period_stat]
        end

        test "card reads zero when there are requests but no exceptions" do
          create_summary("RailsPulse::Request", 1.day.ago, count: 4_000)

          assert_equal "0.0 per 1,000", card.to_metric_card[:summary]
        end

        test "card ignores summaries of a different period type" do
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 20, period_type: "hour")
          create_summary("RailsPulse::Request", 1.day.ago, count: 4_000, period_type: "hour")

          assert_equal "0.0 per 1,000", card.to_metric_card[:summary]
        end

        test "card drops the trend over windows too long to compare" do
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 20)
          create_summary("RailsPulse::Request", 1.day.ago, count: 4_000)

          result = card(period: 30).to_metric_card

          assert_nil result[:trend_icon]
          assert_nil result[:trend_text]
        end

        test "sparkline covers every day of the window" do
          create_summary("RailsPulse::ExceptionGroup", 1.day.ago, count: 20)
          create_summary("RailsPulse::Request", 1.day.ago, count: 4_000)

          chart_data = card.to_metric_card[:chart_data]

          assert_equal 8, chart_data.size
          assert_includes chart_data.values.map { |v| v[:value] }, 5.0
        end

        private

        def card(period: 7, period_type: "day")
          RailsPulse::Exceptions::Cards::ExceptionRate.new(period: period, period_type: period_type)
        end

        def create_summary(type, period_start, count:, summarizable_id: 0, period_type: "day")
          start = period_type == "hour" ? period_start.beginning_of_hour : period_start.beginning_of_day
          finish = period_type == "hour" ? start + 1.hour : start + 1.day

          RailsPulse::Summary.create!(
            summarizable_type: type,
            summarizable_id: summarizable_id,
            period_type: period_type,
            period_start: start,
            period_end: finish,
            count: count
          )
        end
      end
    end
  end
end
