require "test_helper"

module RailsPulse
  module Dashboard
    class StoragePressureTest < ActiveSupport::TestCase
      fixtures :rails_pulse_events

      fixtures :rails_pulse_routes

      def setup
        RailsPulse::Summary.delete_all
        RailsPulse::Operation.delete_all
        RailsPulse::Request.delete_all
        @original_retention  = RailsPulse.configuration.full_retention_period
        @original_archiving  = RailsPulse.configuration.archiving_enabled
        @now = Time.current
        travel_to @now
      end

      def teardown
        RailsPulse.configuration.store_full_details = :all
        RailsPulse.configuration.full_retention_period = @original_retention
        RailsPulse.configuration.archiving_enabled     = @original_archiving
        travel_back
      end

      # Structure Tests

      # Writer Drop Tests

      test "pressure items flag requests dropped by the writer in the last hour" do
        rails_pulse_events(:web_two_latest).update!(value: 7)
        item = StoragePressure.new.pressure_items.find { |i| i[:type] == "TRACKING" }

        assert item, "expected a TRACKING pressure item"
        assert_equal :critical, item[:severity]
        assert_includes item[:reason], "7 requests dropped in the last hour"
        assert_includes item[:popover_body], "async_queue_size"
      end

      test "no pressure item when nothing was dropped" do
        assert_nil StoragePressure.new.pressure_items.find { |i| i[:type] == "TRACKING" }
      end

      test "storage_counts ignore tracking items so the Storage badge stays about storage" do
        pressure = StoragePressure.new
        pressure.stubs(:pressure_items).returns([ { type: "TRACKING", severity: :critical } ])

        assert_equal({ healthy: 1, slow: 0, critical: 0 }, pressure.storage_counts)
      end

      # Detail Capture Tests

      test "detail capture keeping over a quarter of requests is a storage warning naming the settings and routes" do
        create_fresh_summary
        RailsPulse.configuration.store_full_details = { above: :slow, sample_rate: 0.05 }
        rate = stub(high?: true, share: 0.6, share_label: "60%", total: 1000)
        RailsPulse::DetailCaptureRate.stubs(:for).returns(rate)
        RailsPulse::DetailCaptureRate.stubs(:top_kept_routes_label).returns("/reports (590 of 600)")

        pressure = StoragePressure.new
        item = pressure.pressure_items.find { |i| i[:name] == "Full details" }

        assert item, "expected a detail capture pressure item"
        assert_equal "STORAGE", item[:type]
        assert_equal :warning, item[:severity]
        assert_equal "60% kept", item[:metric]
        assert_includes item[:popover_body], "Raise request_thresholds[:slow] (700ms now) or query_thresholds[:slow] (100ms now), set store_full_details[:above] to a higher threshold, or lower store_full_details[:sample_rate] (5% now)"
        assert_includes item[:popover_body], "/reports (590 of 600)"
        assert_equal({ healthy: 0, slow: 1, critical: 0 }, pressure.storage_counts)
        assert_equal :healthy, StorageStatus.new(storage_pressure: pressure).cleanup[:health]
      end

      test "detail capture at a normal share is not a pressure item" do
        create_fresh_summary
        RailsPulse.configuration.store_full_details = { above: :slow }
        RailsPulse::DetailCaptureRate.stubs(:for).returns(stub(high?: false))

        assert_empty StoragePressure.new.pressure_items
      end

      test "detail capture with no rate yet is not a pressure item" do
        create_fresh_summary
        RailsPulse.configuration.store_full_details = { above: :slow }
        RailsPulse::DetailCaptureRate.stubs(:for).returns(nil)

        assert_empty StoragePressure.new.pressure_items
      end

      test "detail capture off is not a pressure item and computes no rate" do
        create_fresh_summary
        RailsPulse::DetailCaptureRate.expects(:for).never

        assert_empty StoragePressure.new.pressure_items
      end

      test "pressure_items returns an array" do
        create_fresh_summary

        result = StoragePressure.new.pressure_items

        assert_kind_of Array, result
      end

      test "pressure_items are computed once per instance" do
        create_fresh_summary
        pressure = StoragePressure.new

        first = pressure.pressure_items
        queries = 0
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          queries += 1 if payload[:name] != "SCHEMA"
        end
        second = pressure.pressure_items
        ActiveSupport::Notifications.unsubscribe(subscriber)

        assert_same first, second
        assert_equal 0, queries
      end

      test "storage_counts returns hash with healthy, slow, critical keys" do
        create_fresh_summary

        result = StoragePressure.new.storage_counts

        assert_kind_of Hash, result
        assert_includes result.keys, :healthy
        assert_includes result.keys, :slow
        assert_includes result.keys, :critical
      end

      test "storage_counts values are 0 or 1" do
        create_fresh_summary

        result = StoragePressure.new.storage_counts

        result.each_value do |v|
          assert_includes [ 0, 1 ], v
        end
      end

      test "exactly one of healthy slow critical is 1" do
        create_fresh_summary

        result = StoragePressure.new.storage_counts

        assert_equal 1, result.values.sum
      end

      # Signal A — Summary Staleness

      test "returns no staleness item when summary is fresh" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)

        items = StoragePressure.new.pressure_items.select { |i| i[:name] == "Summary job" }

        assert_empty items
      end

      test "returns warning item when summary is 3 hours stale" do
        create_overall_hourly_summary(period_end: 3.hours.ago)

        items = StoragePressure.new.pressure_items.select { |i| i[:name] == "Summary job" }

        assert_equal 1, items.size
        assert_equal :warning, items.first[:severity]
        assert_equal "STORAGE", items.first[:type]
      end

      test "returns critical item when summary is 25 hours stale" do
        create_overall_hourly_summary(period_end: 25.hours.ago)

        items = StoragePressure.new.pressure_items.select { |i| i[:name] == "Summary job" }

        assert_equal 1, items.size
        assert_equal :critical, items.first[:severity]
      end

      test "returns critical item when summary job has never run" do
        items = StoragePressure.new.pressure_items.select { |i| i[:name] == "Summary job" }

        assert_equal 1, items.size
        assert_equal :critical, items.first[:severity]
        assert_includes items.first[:reason], "never"
      end

      test "staleness item metric includes stale hours when stale" do
        create_overall_hourly_summary(period_end: 3.hours.ago)

        item = StoragePressure.new.pressure_items.find { |i| i[:name] == "Summary job" }

        assert_includes item[:metric], "stale"
        assert_includes item[:metric_sub], "Last run:"
      end

      test "returns no staleness item after SummaryService runs with zero requests" do
        RailsPulse::SummaryService.new("hour", 1.hour.ago.beginning_of_hour).perform

        items = StoragePressure.new.pressure_items.select { |i| i[:name] == "Summary job" }

        assert_empty items
      end

      # Expired records

      test "requests past retention and older than every hourly summary are not a pressure item" do
        # Hourly summaries are kept for 7 days and raw requests for 30, so an
        # expired request waiting for the next daily cleanup always predates
        # them. Time-based cleanup deletes it by age alone.
        RailsPulse.configuration.full_retention_period = 30.days
        create_overall_hourly_summary(period_end: 30.minutes.ago)
        create_request(occurred_at: 31.days.ago)

        assert_empty StoragePressure.new.pressure_items
        assert_equal 1, StoragePressure.new.storage_counts[:healthy]
      end

      # Signal B — Sub-hour Retention

      test "returns warning when full_retention_period is 30 minutes" do
        RailsPulse.configuration.instance_variable_set(:@full_retention_period, 30.minutes)
        create_fresh_summary

        items = StoragePressure.new.pressure_items.select { |i| i[:name] == "Retention period misconfigured" }

        assert_equal 1, items.size
        assert_equal :warning, items.first[:severity]
        assert_includes items.first[:reason], "30m"
      end

      test "returns no misconfiguration warning when full_retention_period is 2 hours" do
        RailsPulse.configuration.full_retention_period = 2.hours
        create_fresh_summary

        items = StoragePressure.new.pressure_items.select { |i| i[:name] == "Retention period misconfigured" }

        assert_empty items
      end

      test "returns no misconfiguration warning when full_retention_period is exactly 1 hour" do
        RailsPulse.configuration.instance_variable_set(:@full_retention_period, 1.hour)
        create_fresh_summary

        items = StoragePressure.new.pressure_items.select { |i| i[:name] == "Retention period misconfigured" }

        assert_empty items
      end

      # storage_counts

      test "storage_counts is healthy when summary is fresh and no other pressure" do
        create_fresh_summary

        counts = StoragePressure.new.storage_counts

        assert_equal 1, counts[:healthy]
        assert_equal 0, counts[:slow]
        assert_equal 0, counts[:critical]
      end

      test "storage_counts is slow when summary is 3 hours stale" do
        create_overall_hourly_summary(period_end: 3.hours.ago)

        counts = StoragePressure.new.storage_counts

        assert_equal 0, counts[:healthy]
        assert_equal 1, counts[:slow]
        assert_equal 0, counts[:critical]
      end

      test "storage_counts is critical when summary job has never run" do
        counts = StoragePressure.new.storage_counts

        assert_equal 0, counts[:healthy]
        assert_equal 0, counts[:slow]
        assert_equal 1, counts[:critical]
      end

      # Edge Cases

      test "pressure_items is empty when everything is healthy" do
        create_fresh_summary

        items = StoragePressure.new.pressure_items

        assert_empty items
      end

      test "each pressure item has required keys" do
        # Force a staleness item by not creating any summaries
        items = StoragePressure.new.pressure_items

        items.each do |item|
          assert_includes item.keys, :type
          assert_includes item.keys, :name
          assert_includes item.keys, :reason
          assert_includes item.keys, :metric
          assert_includes item.keys, :metric_sub
          assert_includes item.keys, :link
          assert_includes item.keys, :severity
          assert_includes item.keys, :sort_score
        end
      end

      private

      def create_overall_hourly_summary(period_end:)
        period_start = period_end.beginning_of_hour
        RailsPulse::Summary.create!(
          summarizable_type: "RailsPulse::Request",
          summarizable_id:   0,
          period_type:       "hour",
          period_start:      period_start,
          period_end:        period_end,
          count:             1,
          avg_duration:      100.0
        )
      end

      def create_fresh_summary
        create_overall_hourly_summary(period_end: 30.minutes.ago)
      end

      def create_request(occurred_at:)
        route = rails_pulse_routes(:api_users)
        RailsPulse::Request.create!(
          route:        route,
          duration:     100.0,
          status:       200,
          is_error:     false,
          request_uuid: SecureRandom.uuid,
          occurred_at:  occurred_at
        )
      end
    end
  end
end
