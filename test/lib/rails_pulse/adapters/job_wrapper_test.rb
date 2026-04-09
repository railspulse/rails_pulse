require "test_helper"
require "rails_pulse/adapters/job_wrapper"

module RailsPulse
  module Adapters
    class JobWrapperTest < ActiveSupport::TestCase
      def build_wrapper(overrides = {})
        defaults = {
          job_id: "abc-123",
          class_name: "MyJob",
          queue_name: "default",
          arguments: [ 1, "hello" ],
          enqueued_at: Time.current,
          executions: 0
        }
        JobWrapper.new(**defaults.merge(overrides))
      end

      # Structure Tests

      test "wrapper exposes all attributes" do
        enqueued_at = Time.current
        wrapper = build_wrapper(enqueued_at: enqueued_at)

        assert_equal "abc-123", wrapper.job_id
        assert_equal "MyJob", wrapper.class_name
        assert_equal "default", wrapper.queue_name
        assert_equal [ 1, "hello" ], wrapper.arguments
        assert_equal enqueued_at, wrapper.enqueued_at
        assert_equal 0, wrapper.executions
      end

      test "class_name returns the job class name string" do
        wrapper = build_wrapper(class_name: "BackgroundMailerJob")

        assert_equal "BackgroundMailerJob", wrapper.class_name
      end

      # Calculation Tests

      test "executions reflects retry count" do
        wrapper = build_wrapper(executions: 3)

        assert_equal 3, wrapper.executions
      end

      # Edge Cases

      test "accepts nil arguments" do
        wrapper = build_wrapper(arguments: nil)

        assert_nil wrapper.arguments
      end

      test "accepts nil enqueued_at" do
        wrapper = build_wrapper(enqueued_at: nil)

        assert_nil wrapper.enqueued_at
      end

      test "accepts empty class name" do
        wrapper = build_wrapper(class_name: "")

        assert_equal "", wrapper.class_name
      end

      test "accepts namespaced class name" do
        wrapper = build_wrapper(class_name: "MyApp::Billing::InvoiceJob")

        assert_equal "MyApp::Billing::InvoiceJob", wrapper.class_name
      end
    end
  end
end
