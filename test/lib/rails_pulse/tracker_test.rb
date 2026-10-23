require "test_helper"

class RailsPulse::TrackerTest < ActiveSupport::TestCase
  def setup
    super
    RailsPulse::SchemaCheck.reset!
    RailsPulse::Tracker.reset_rollups!
  end

  def teardown
    RailsPulse::SchemaCheck.reset!
    RailsPulse::Tracker.reset_rollups!
    super
  end

  # Schema Gate Tests

  test "track_request persists a request when the schema is current" do
    assert_difference "RailsPulse::Request.count", 1 do
      RailsPulse::Tracker.track_request(tracking_data)
    end
  end

  test "track_request persists nothing while the schema is outdated" do
    RailsPulse::SchemaCheck.stubs(:expected_schema).returns("rails_pulse_routes" => [ "ghost" ])

    assert_no_difference [ "RailsPulse::Request.count", "RailsPulse::Route.count" ] do
      RailsPulse::Tracker.track_request(tracking_data)
    end
  end

  # Rollup Fold Tests (detail: false payloads from detail capture)

  test "a folded request creates no request or operation rows" do
    assert_no_difference [ "RailsPulse::Request.count", "RailsPulse::Operation.count" ] do
      RailsPulse::Tracker.track_request(folded_tracking_data)
    end
  end

  test "a folded request still creates its route" do
    assert_difference "RailsPulse::Route.count", 1 do
      RailsPulse::Tracker.track_request(folded_tracking_data)
    end
  end

  test "a folded request lands in route and query rollups after a flush" do
    data = folded_tracking_data
    RailsPulse::Tracker.track_request(data)

    assert_difference "RailsPulse::Rollup.count", 2 do
      RailsPulse::Tracker.flush_rollups!
    end

    route = RailsPulse::Route.find_by!(path: "/tracker-test")
    route_rollup = RailsPulse::Rollup.find_by!(rollupable_type: "RailsPulse::Route", rollupable_id: route.id)

    assert_equal 1, route_rollup.count
    assert_equal 1, route_rollup.status_2xx
    assert_in_delta 12.5, route_rollup.sum_duration.to_f, 1e-6
    assert_equal data[:occurred_at].beginning_of_hour, route_rollup.period_start

    query_rollup = RailsPulse::Rollup.find_by!(rollupable_type: "RailsPulse::Query")

    assert_equal 1, query_rollup.count
    assert_in_delta 3.25, query_rollup.sum_duration.to_f, 1e-6
  end

  test "a folded request's SQL still creates its query record" do
    assert_difference "RailsPulse::Query.count", 1 do
      RailsPulse::Tracker.track_request(folded_tracking_data)
    end
  end

  test "a second flush replaces the writer's rollup row instead of adding one" do
    RailsPulse::Tracker.track_request(folded_tracking_data(operations: []))
    RailsPulse::Tracker.flush_rollups!

    RailsPulse::Tracker.track_request(folded_tracking_data(operations: []))

    assert_no_difference "RailsPulse::Rollup.count" do
      RailsPulse::Tracker.flush_rollups!
    end

    assert_equal 2, RailsPulse::Rollup.where(rollupable_type: "RailsPulse::Route").sum(:count)
  end

  test "a deleted route is recreated for folds once the route id cache expires" do
    RailsPulse::Tracker.track_request(folded_tracking_data(operations: []))
    RailsPulse::Route.find_by!(path: "/tracker-test").delete

    # Within the TTL the cached id is still served, so no route is created.
    assert_no_difference "RailsPulse::Route.count" do
      RailsPulse::Tracker.track_request(folded_tracking_data(operations: []))
    end

    travel 11.minutes do
      assert_difference "RailsPulse::Route.count", 1 do
        RailsPulse::Tracker.track_request(folded_tracking_data(operations: []))
      end
    end
  end

  # Batched Fold Tests (perform_tracking_batch with detail: false payloads)

  test "a folded batch's SQL durations land in each request's query rollup" do
    batch = [ folded_tracking_data, folded_tracking_data(operations: gadget_operations) ]

    assert_difference "RailsPulse::Query.count", 2 do
      RailsPulse::Tracker.perform_tracking_batch(batch)
    end
    RailsPulse::Tracker.flush_rollups!

    widgets = RailsPulse::Query.where("normalized_sql LIKE ?", "%widgets%").first
    gadgets = RailsPulse::Query.where("normalized_sql LIKE ?", "%gadgets%").first

    widget_rollup = RailsPulse::Rollup.find_by!(rollupable_type: "RailsPulse::Query", rollupable_id: widgets.id)
    gadget_rollup = RailsPulse::Rollup.find_by!(rollupable_type: "RailsPulse::Query", rollupable_id: gadgets.id)

    assert_equal 1, widget_rollup.count
    assert_in_delta 3.25, widget_rollup.sum_duration.to_f, 1e-6
    assert_equal 1, gadget_rollup.count
    assert_in_delta 1.5, gadget_rollup.sum_duration.to_f, 1e-6
  end

  test "a folded batch sharing one statement creates one query and folds every duration" do
    batch = [ folded_tracking_data, folded_tracking_data ]

    assert_difference "RailsPulse::Query.count", 1 do
      RailsPulse::Tracker.perform_tracking_batch(batch)
    end
    RailsPulse::Tracker.flush_rollups!

    query_rollup = RailsPulse::Rollup.find_by!(rollupable_type: "RailsPulse::Query")

    assert_equal 2, query_rollup.count
    assert_in_delta 6.5, query_rollup.sum_duration.to_f, 1e-6
  end

  test "a folded batch resolves its SQL with one query lookup" do
    batch = [ folded_tracking_data, folded_tracking_data(operations: gadget_operations) ]
    RailsPulse::Tracker.perform_tracking_batch(batch)
    RailsPulse::Tracker.reset_rollups!

    selects = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      selects += 1 if payload[:sql].start_with?("SELECT") && payload[:sql].include?("rails_pulse_queries")
    end

    RailsPulse::Tracker.perform_tracking_batch(batch)

    assert_equal 1, selects
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "a folded batch whose batched SQL resolution fails falls back to per-request resolution" do
    # resolve_sql_durations delegates to resolve_sql_durations_many, so the
    # fallback goes through the same method: fail the first (batched) call
    # only, then restore the real implementation for the per-request calls.
    operation_singleton = RailsPulse::Operation.singleton_class
    operation_singleton.send(:alias_method, :real_resolve_sql_durations_many, :resolve_sql_durations_many)
    calls = 0
    operation_singleton.send(:define_method, :resolve_sql_durations_many) do |ops_lists|
      calls += 1
      raise ActiveRecord::StatementInvalid, "boom" if calls == 1

      real_resolve_sql_durations_many(ops_lists)
    end

    RailsPulse::Tracker.perform_tracking_batch([ folded_tracking_data, folded_tracking_data(operations: gadget_operations) ])
    RailsPulse::Tracker.flush_rollups!

    assert RailsPulse::Rollup.exists?(rollupable_type: "RailsPulse::Route")
    assert_equal 2, RailsPulse::Rollup.where(rollupable_type: "RailsPulse::Query").count
  ensure
    operation_singleton.send(:alias_method, :resolve_sql_durations_many, :real_resolve_sql_durations_many)
    operation_singleton.send(:remove_method, :real_resolve_sql_durations_many)
  end

  test "a folded batch whose SQL resolution fails entirely still folds its routes" do
    RailsPulse::Operation.stubs(:resolve_sql_durations_many).raises(ActiveRecord::StatementInvalid, "boom")
    RailsPulse::Operation.stubs(:resolve_sql_durations).raises(ActiveRecord::StatementInvalid, "boom")

    RailsPulse::Tracker.perform_tracking_batch([ folded_tracking_data ])
    RailsPulse::Tracker.flush_rollups!

    assert RailsPulse::Rollup.exists?(rollupable_type: "RailsPulse::Route")
    assert_not RailsPulse::Rollup.exists?(rollupable_type: "RailsPulse::Query")
  ensure
    RailsPulse::Operation.unstub(:resolve_sql_durations_many)
    RailsPulse::Operation.unstub(:resolve_sql_durations)
  end

  test "flush with nothing folded writes nothing" do
    assert_no_difference "RailsPulse::Rollup.count" do
      RailsPulse::Tracker.flush_rollups!
    end
  end

  test "rows from a failed flush are written by the next flush" do
    RailsPulse::Tracker.track_request(folded_tracking_data(operations: []))

    RailsPulse::Rollup.stubs(:upsert_rows).raises(ActiveRecord::StatementInvalid, "connection lost")

    assert_no_difference "RailsPulse::Rollup.count" do
      RailsPulse::Tracker.flush_rollups!
    end

    RailsPulse::Rollup.unstub(:upsert_rows)

    assert_difference "RailsPulse::Rollup.count", 1 do
      RailsPulse::Tracker.flush_rollups!
    end

    assert_equal 1, RailsPulse::Rollup.where(rollupable_type: "RailsPulse::Route").sum(:count)
  end

  private

  def tracking_data
    {
      method: "GET",
      path: "/tracker-test",
      duration: 12.5,
      status: 200,
      is_error: false,
      request_uuid: SecureRandom.uuid,
      controller_action: "home#index",
      occurred_at: Time.current,
      response_size_bytes: 128,
      operations: []
    }
  end

  def gadget_operations
    [
      {
        operation_type: "sql",
        actual_sql: "SELECT * FROM gadgets WHERE id = 2",
        label: "SELECT * FROM gadgets WHERE id = 2",
        duration: 1.5
      }
    ]
  end

  def folded_tracking_data(operations: nil)
    operations ||= [
      {
        operation_type: "sql",
        actual_sql: "SELECT * FROM widgets WHERE id = 1",
        label: "SELECT * FROM widgets WHERE id = 1",
        duration: 3.25
      }
    ]
    {
      method: "GET",
      path: "/tracker-test",
      controller_action: "home#index",
      duration: 12.5,
      status: 200,
      occurred_at: Time.current,
      detail: false,
      operations: operations
    }
  end
end
