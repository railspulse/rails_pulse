require "test_helper"

module RailsPulse
  module Cloud
    class HealthItemTest < ActiveSupport::TestCase
      fixtures :rails_pulse_routes

      setup do
        Operation.delete_all
        Request.delete_all
        ExceptionOccurrence.delete_all
        Event.delete_all
        @now = Time.utc(2026, 10, 4, 10, 5, 12)
        @minute = Time.utc(2026, 10, 4, 10, 4)
        travel_to @now
      end

      teardown do
        travel_back
      end

      # Structure Tests

      test "covers the minute just ended" do
        item = HealthItem.for_minute_before(@now)

        assert_equal "health", item[:type]
        assert_equal "2026-10-04T10:04:00Z", item[:window_start]
        assert_equal "2026-10-04T10:05:00Z", item[:window_end]
      end

      # Calculation Tests

      test "counts requests, errors and exceptions inside the minute only" do
        [ [ 10.0, 200 ], [ 20.0, 200 ], [ 30.0, 500 ], [ 40.0, 404 ] ].each { |duration, status| request(duration, status, @minute + 10.seconds) }
        request(999.0, 500, @minute - 1.second)
        request(999.0, 500, @minute + 1.minute)

        item = HealthItem.for_minute_before(@now)

        assert_equal 4, item[:request_count]
        assert_equal 1, item[:error_count]
        assert_in_delta 25.0, item[:avg_duration]
        assert_in_delta Statistics.calculate_percentile([ 10.0, 20.0, 30.0, 40.0 ], 0.95), item[:p95_duration]
      end

      test "lists each host's live writers from their heartbeats, without process IDs" do
        heartbeat("web-1", 101, queue_depth: 5, dropped: 0, at: @minute + 20.seconds)
        heartbeat("web-1", 101, queue_depth: 9, dropped: 2, at: @minute + 50.seconds)
        heartbeat("web-1", 102, queue_depth: 1, dropped: 0, at: @minute + 30.seconds)
        heartbeat("web-2", 201, queue_depth: 0, dropped: 4, at: @minute - 30.seconds)
        heartbeat("web-3", 301, queue_depth: 0, dropped: 0, at: @minute - 10.minutes)

        hosts = HealthItem.for_minute_before(@now)[:hosts]

        assert_equal [ "web-1", "web-2" ], hosts.map { |host| host[:host] }
        assert_equal({ host: "web-1", processes: 2, queue_depth: 10, dropped: 2, last_heartbeat_at: "2026-10-04T10:04:50Z" }, hosts.first)
        assert_equal 0, hosts.last[:dropped]
        assert(hosts.none? { |host| host.to_s.include?("101") })
      end

      test "a host is named by its config.cloud.host_label when it has one" do
        WriterHeartbeat.record!(hostname: "ip-10-0-3-17", host_label: "web-1", pid: 1, queue_size: 1000, queue_depth: 0,
                                dropped: 0, dropped_total: 0, sampled_at: @minute + 5.seconds)

        assert_equal [ "web-1" ], HealthItem.for_minute_before(@now)[:hosts].map { |host| host[:host] }
      end

      # Edge Cases

      test "a quiet minute has zero counts and no durations" do
        item = HealthItem.for_minute_before(@now)

        assert_equal 0, item[:request_count]
        assert_nil item[:avg_duration]
        assert_nil item[:p95_duration]
        assert_empty item[:hosts]
      end

      private

      def request(duration, status, at)
        Request.create!(route: rails_pulse_routes(:api_users), duration: duration, status: status, is_error: status >= 500, occurred_at: at)
      end

      def heartbeat(host, pid, queue_depth:, dropped:, at:)
        WriterHeartbeat.record!(hostname: host, pid: pid, queue_size: 1000, queue_depth: queue_depth, dropped: dropped, dropped_total: dropped, sampled_at: at)
      end
    end
  end
end
