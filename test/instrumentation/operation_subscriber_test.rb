require "test_helper"

class OperationSubscriberTest < ActiveSupport::TestCase
  def setup
    # Use existing fixture data
    @request = rails_pulse_requests(:users_request_1)

    # Setup request context for operation tracking
    RequestStore.store[:rails_pulse_request_id] = @request.id
    RequestStore.store[:rails_pulse_job_run_id] = nil
    RequestStore.store[:rails_pulse_operations] = []

    super
  end

  def teardown
    RequestStore.clear!
    super
  end

  test "subscriber module should exist" do
    assert defined?(RailsPulse::Subscribers::OperationSubscriber)
    assert_respond_to RailsPulse::Subscribers::OperationSubscriber, :subscribe!
  end

  test "should capture SQL operations" do
    payload = {
      sql: "SELECT * FROM users WHERE id = ?",
      name: "User Load"
    }

    ActiveSupport::Notifications.instrument("sql.active_record", payload) do
      sleep(0.01) # Ensure measurable duration
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 1, operations.size

    operation = operations.first

    assert_equal "sql", operation[:operation_type]
    assert_equal "SELECT * FROM users WHERE id = ?", operation[:label]
    assert_operator operation[:duration], :>=, 0, "Duration should be non-negative, got: #{operation[:duration]}"
    assert_equal @request.id, operation[:request_id]
  end

  test "should filter out schema SQL queries" do
    schema_queries = [
      { sql: "SHOW FULL FIELDS FROM `users`", name: "SCHEMA" },
      { sql: "SELECT sql FROM sqlite_master", name: "SCHEMA" },
      { sql: "PRAGMA table_info(`users`)", name: "SCHEMA" }
    ]

    schema_queries.each do |payload|
      ActiveSupport::Notifications.instrument("sql.active_record", payload) do
        sleep(0.001)
      end
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 0, operations.size, "Schema queries should be filtered out"
  end

  test "should filter out RailsPulse SQL queries" do
    payload = {
      sql: "SELECT * FROM rails_pulse_requests WHERE id = ?",
      name: "RailsPulse::Request Load"
    }

    ActiveSupport::Notifications.instrument("sql.active_record", payload) do
      sleep(0.001)
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 0, operations.size, "RailsPulse queries should be filtered out"
  end

  test "should capture template rendering operations" do
    payload = {
      identifier: "/app/views/users/show.html.erb"
    }

    ActiveSupport::Notifications.instrument("render_template.action_view", payload) do
      sleep(0.01)
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 1, operations.size

    operation = operations.first

    assert_equal "template", operation[:operation_type]
    assert_equal "/app/views/users/show.html.erb", operation[:label]
    assert_operator operation[:duration], :>=, 0
  end

  test "should capture controller action operations" do
    payload = {
      controller: "UsersController",
      action: "show"
    }

    ActiveSupport::Notifications.instrument("process_action.action_controller", payload) do
      sleep(0.01)
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 1, operations.size

    operation = operations.first

    assert_equal "controller", operation[:operation_type]
    assert_equal "UsersController#show", operation[:label]
    assert_operator operation[:duration], :>=, 0
  end

  test "should capture partial rendering operations" do
    payload = {
      identifier: "/app/views/users/_user.html.erb"
    }

    ActiveSupport::Notifications.instrument("render_partial.action_view", payload) do
      sleep(0.001)
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 1, operations.size

    operation = operations.first

    assert_equal "partial", operation[:operation_type]
    assert_equal "/app/views/users/_user.html.erb", operation[:label]
  end

  test "should capture cache operations" do
    payload = {
      key: "user/123/profile"
    }

    ActiveSupport::Notifications.instrument("cache_read.active_support", payload) do
      sleep(0.001)
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 1, operations.size

    operation = operations.first

    assert_equal "cache_read", operation[:operation_type]
    assert_equal "user/123/profile", operation[:label]
  end

  test "should capture operations with proper metadata" do
    payload = {
      sql: "SELECT * FROM users WHERE id = ?",
      name: "User Load"
    }

    start_time = Time.current
    ActiveSupport::Notifications.instrument("sql.active_record", payload) do
      sleep(0.01)
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 1, operations.size

    operation = operations.first

    assert_equal "sql", operation[:operation_type]
    assert_equal "SELECT * FROM users WHERE id = ?", operation[:label]
    assert_operator operation[:duration], :>=, 0
    assert_equal @request.id, operation[:request_id]
    assert_kind_of Float, operation[:start_time]
    assert_operator operation[:occurred_at], :>=, start_time
    assert_kind_of Time, operation[:occurred_at]
  end

  test "should not capture operations without request context" do
    RequestStore.store[:rails_pulse_request_id] = nil
    RequestStore.store[:rails_pulse_job_run_id] = nil

    payload = {
      sql: "SELECT * FROM users",
      name: "User Load"
    }

    ActiveSupport::Notifications.instrument("sql.active_record", payload) do
      sleep(0.001)
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 0, operations.size
  end

  test "should capture operations for background job context" do
    job_run = rails_pulse_job_runs(:mailer_run_success)

    RequestStore.store[:rails_pulse_request_id] = nil
    RequestStore.store[:rails_pulse_job_run_id] = job_run.id
    RequestStore.store[:rails_pulse_operations] = []

    payload = { sql: "SELECT 1", name: "Job SQL" }

    ActiveSupport::Notifications.instrument("sql.active_record", payload) do
      sleep(0.001)
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 1, operations.size
    assert_nil operations.first[:request_id]
    assert_equal job_run.id, operations.first[:job_run_id]
  end

  test "should clean SQL labels by removing Rails comments" do
    payload = {
      sql: "/*action='search',application='Dummy',controller='home'*/ SELECT * FROM users",
      name: "User Load"
    }

    ActiveSupport::Notifications.instrument("sql.active_record", payload) do
      sleep(0.001)
    end

    operations = RequestStore.store[:rails_pulse_operations]
    operation = operations.first

    assert_equal "SELECT * FROM users", operation[:label]
  end

  test "should handle HTTP client operations" do
    payload = {
      method: "GET",
      uri: "https://api.example.com/users"
    }

    ActiveSupport::Notifications.instrument("request.net_http", payload) do
      sleep(0.001)
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 1, operations.size

    operation = operations.first

    assert_equal "http", operation[:operation_type]
    assert_equal "GET https://api.example.com/users", operation[:label]
  end

  test "should handle Active Job operations" do
    job_class = Class.new do
      def self.name
        "TestJob"
      end
    end

    payload = {
      job: job_class.new
    }

    ActiveSupport::Notifications.instrument("perform.active_job", payload) do
      sleep(0.001)
    end

    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 1, operations.size

    operation = operations.first

    assert_equal "job", operation[:operation_type]
    assert_equal "TestJob", operation[:label]
  end

  test "should handle exceptions gracefully" do
    # The subscriber should handle nil SQL gracefully and still capture it
    payload = { sql: nil, name: "User Load" }

    assert_nothing_raised do
      ActiveSupport::Notifications.instrument("sql.active_record", payload) do
        sleep(0.001)
      end
    end

    # Should have captured the operation even with nil SQL
    operations = RequestStore.store[:rails_pulse_operations]

    assert_equal 1, operations.size
    operation = operations.first

    assert_nil operation[:label] # nil SQL should result in nil label
  end

  test "should capture start time and occurred_at" do
    payload = {
      sql: "SELECT * FROM users",
      name: "User Load"
    }

    start_time = Time.current
    ActiveSupport::Notifications.instrument("sql.active_record", payload) do
      sleep(0.001)
    end

    operations = RequestStore.store[:rails_pulse_operations]
    operation = operations.first

    assert_kind_of Float, operation[:start_time]
    assert_kind_of Time, operation[:occurred_at]
    assert_operator operation[:occurred_at], :>=, start_time
  end
end
