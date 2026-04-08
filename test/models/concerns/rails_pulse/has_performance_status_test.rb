require "test_helper"

module RailsPulse
  class HasPerformanceStatusTest < ActiveSupport::TestCase
    # Create a minimal test class to test the concern
    class TestModel < ApplicationRecord
      self.table_name = "rails_pulse_jobs"  # Reuse existing table
      include HasPerformanceStatus
      performance_status_attribute :avg_duration
    end

    class DefaultModel < ApplicationRecord
      self.table_name = "rails_pulse_job_runs"
      include HasPerformanceStatus
      # No attribute configured - should default to :duration
    end

    def setup
      @original_thresholds = RailsPulse.configuration.job_thresholds.dup
      RailsPulse.configuration.job_thresholds = {
        slow: 100,
        very_slow: 500,
        critical: 1000
      }
    end

    def teardown
      RailsPulse.configuration.job_thresholds = @original_thresholds
    end

    # Configuration Tests

    test "performance_status_attribute sets custom attribute" do
      assert_equal :avg_duration, TestModel.get_performance_status_attribute
    end

    test "performance_status_attribute defaults to duration when not configured" do
      assert_equal :duration, DefaultModel.get_performance_status_attribute
    end

    # Performance Status Tests

    test "performance_status returns fast for duration below slow threshold" do
      model = TestModel.new(avg_duration: 50)

      assert_equal :fast, model.performance_status
    end

    test "performance_status returns slow for duration above slow threshold" do
      model = TestModel.new(avg_duration: 200)

      assert_equal :slow, model.performance_status
    end

    test "performance_status returns very_slow for duration above very_slow threshold" do
      model = TestModel.new(avg_duration: 700)

      assert_equal :very_slow, model.performance_status
    end

    test "performance_status returns critical for duration above critical threshold" do
      model = TestModel.new(avg_duration: 1500)

      assert_equal :critical, model.performance_status
    end

    test "performance_status handles nil duration" do
      model = TestModel.new(avg_duration: nil)

      assert_equal :fast, model.performance_status
    end

    test "performance_status handles zero duration" do
      model = TestModel.new(avg_duration: 0)

      assert_equal :fast, model.performance_status
    end

    test "performance_status handles boundary at slow threshold" do
      model = TestModel.new(avg_duration: 100)

      assert_equal :slow, model.performance_status
    end

    test "performance_status handles boundary at very_slow threshold" do
      model = TestModel.new(avg_duration: 500)

      assert_equal :very_slow, model.performance_status
    end

    test "performance_status handles boundary at critical threshold" do
      model = TestModel.new(avg_duration: 1000)

      assert_equal :critical, model.performance_status
    end

    test "performance_status works with default attribute configuration" do
      model = DefaultModel.new(duration: 250)

      assert_equal :slow, model.performance_status
    end

    # Edge Cases

    test "performance_status handles very small durations" do
      model = TestModel.new(avg_duration: 0.001)

      assert_equal :fast, model.performance_status
    end

    test "performance_status handles very large durations" do
      model = TestModel.new(avg_duration: 999999)

      assert_equal :critical, model.performance_status
    end
  end
end
