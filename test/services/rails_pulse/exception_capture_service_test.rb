require "test_helper"

module RailsPulse
  class ExceptionCaptureServiceTest < ActiveSupport::TestCase
    fixtures :rails_pulse_exception_groups, :rails_pulse_exception_occurrences, :rails_pulse_deployments

    def setup
      ENV["TEST_TYPE"] = "functional"
      super
      RequestStore.store[:skip_recording_rails_pulse_activity] = false
    end

    def teardown
      RequestStore.clear!
      super
    end

    def make_exception(klass = RuntimeError, message = "something went wrong")
      begin
        raise klass, message
      rescue => e
        e
      end
    end

    # Capture — group creation

    test "creates a new exception group on first capture" do
      exception = make_exception(ArgumentError, "bad arg")

      assert_difference -> { ExceptionGroup.count }, 1 do
        ExceptionCaptureService.capture(exception)
      end
    end

    test "sets exception_class on the group" do
      exception = make_exception(ArgumentError, "bad arg")
      ExceptionCaptureService.capture(exception)

      group = ExceptionGroup.order(:created_at).last

      assert_equal "ArgumentError", group.exception_class
    end

    test "sets first_seen_at and last_seen_at" do
      exception = make_exception(ArgumentError, "bad arg")
      ExceptionCaptureService.capture(exception)

      group = ExceptionGroup.order(:created_at).last

      assert_not_nil group.first_seen_at
      assert_not_nil group.last_seen_at
    end

    test "increments occurrence_count on repeated captures of the same exception" do
      exception = make_exception(ArgumentError, "bad arg")

      ExceptionCaptureService.capture(exception)
      group = ExceptionGroup.order(:created_at).last
      first_count = group.occurrence_count

      ExceptionCaptureService.capture(exception)

      assert_equal first_count + 1, group.reload.occurrence_count
    end

    test "does not create a duplicate group for the same fingerprint" do
      exception = make_exception(ArgumentError, "bad arg")

      ExceptionCaptureService.capture(exception)
      assert_no_difference -> { ExceptionGroup.count } do
        ExceptionCaptureService.capture(exception)
      end
    end

    # Capture — occurrence creation

    test "creates an occurrence on each capture" do
      exception = make_exception(ArgumentError, "bad arg")

      assert_difference -> { ExceptionOccurrence.count }, 1 do
        ExceptionCaptureService.capture(exception)
      end
    end

    test "stores request context on the occurrence" do
      exception = make_exception(RuntimeError, "oops")
      ExceptionCaptureService.capture(exception, request_url: "/posts/1", request_method: "GET")

      occurrence = ExceptionOccurrence.order(:created_at).last

      assert_equal "/posts/1", occurrence.request_url
      assert_equal "GET", occurrence.request_method
    end

    test "stores environment on the occurrence" do
      exception = make_exception(RuntimeError, "oops")
      ExceptionCaptureService.capture(exception, environment: "staging")

      occurrence = ExceptionOccurrence.order(:created_at).last

      assert_equal "staging", occurrence.environment
    end

    test "stores structured backtrace frames" do
      exception = make_exception(RuntimeError, "oops")
      ExceptionCaptureService.capture(exception)

      occurrence = ExceptionOccurrence.order(:created_at).last

      assert_kind_of Array, occurrence.backtrace
      # Should have at least one frame from this test file
      assert_operator occurrence.backtrace.length, :>, 0
      first_frame = occurrence.backtrace.first

      assert first_frame.key?("file")
      assert first_frame.key?("line")
      assert first_frame.key?("method")
    end

    # Edge cases

    test "is a no-op when skip_recording flag is set" do
      RequestStore.store[:skip_recording_rails_pulse_activity] = true
      exception = make_exception(RuntimeError, "oops")

      assert_no_difference -> { ExceptionGroup.count } do
        ExceptionCaptureService.capture(exception)
      end
    end

    test "handles nil backtrace gracefully" do
      exception = make_exception(RuntimeError, "no trace")
      exception.stubs(:backtrace).returns(nil)

      assert_nothing_raised do
        ExceptionCaptureService.capture(exception)
      end
    end

    test "truncates very long messages to 500 characters" do
      long_message = "x" * 600
      exception = make_exception(RuntimeError, long_message)
      ExceptionCaptureService.capture(exception)

      occurrence = ExceptionOccurrence.order(:created_at).last

      assert_operator occurrence.message.length, :<=, 500
    end

    test "groups exceptions with no app-code frames under unknown location" do
      exception = make_exception(RuntimeError, "gem error")
      fake_backtrace = [ "/usr/local/bundle/gems/activesupport-7.0.0/lib/foo.rb:1:in 'bar'" ]
      exception.stubs(:backtrace).returns(fake_backtrace)

      assert_difference -> { ExceptionGroup.count }, 1 do
        ExceptionCaptureService.capture(exception)
      end

      group = ExceptionGroup.order(:created_at).last

      assert_not_nil group.fingerprint
    end

    test "returns nil and logs on unexpected error without raising" do
      exception = make_exception(RuntimeError, "oops")
      ExceptionGroup.stubs(:find_or_initialize_by).raises(StandardError, "db exploded")

      assert_nothing_raised do
        result = ExceptionCaptureService.capture(exception)

        assert_nil result
      end
    end
  end
end
