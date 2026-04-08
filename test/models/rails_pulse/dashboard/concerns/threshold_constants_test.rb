require "test_helper"

module RailsPulse
  module Dashboard
    module Concerns
      class ThresholdConstantsTest < ActiveSupport::TestCase
        # Test class that includes the concern
        class TestClass
          include ThresholdConstants
        end

        def setup
          @test_instance = TestClass.new
        end

        # Constant Value Tests

        test "defines CRITICAL_ERROR_RATE constant" do
          assert_equal 10.0, TestClass::CRITICAL_ERROR_RATE
        end

        test "defines WARNING_ERROR_RATE constant" do
          assert_equal 5.0, TestClass::WARNING_ERROR_RATE
        end

        test "defines CRITICAL_JOB_FAILURE_RATE constant" do
          assert_equal 10.0, TestClass::CRITICAL_JOB_FAILURE_RATE
        end

        test "defines WARNING_JOB_FAILURE_RATE constant" do
          assert_equal 5.0, TestClass::WARNING_JOB_FAILURE_RATE
        end

        # Type Tests

        test "all constants are Float values" do
          assert_kind_of Float, TestClass::CRITICAL_ERROR_RATE
          assert_kind_of Float, TestClass::WARNING_ERROR_RATE
          assert_kind_of Float, TestClass::CRITICAL_JOB_FAILURE_RATE
          assert_kind_of Float, TestClass::WARNING_JOB_FAILURE_RATE
        end

        # Relationship Tests

        test "CRITICAL_ERROR_RATE is greater than WARNING_ERROR_RATE" do
          assert_operator TestClass::CRITICAL_ERROR_RATE, :>, TestClass::WARNING_ERROR_RATE
        end

        test "CRITICAL_JOB_FAILURE_RATE is greater than WARNING_JOB_FAILURE_RATE" do
          assert_operator TestClass::CRITICAL_JOB_FAILURE_RATE, :>, TestClass::WARNING_JOB_FAILURE_RATE
        end

        # Integration Tests

        test "constants are accessible from including class instance" do
          assert_equal 10.0, @test_instance.class::CRITICAL_ERROR_RATE
          assert_equal 5.0, @test_instance.class::WARNING_ERROR_RATE
          assert_equal 10.0, @test_instance.class::CRITICAL_JOB_FAILURE_RATE
          assert_equal 5.0, @test_instance.class::WARNING_JOB_FAILURE_RATE
        end

        # Edge Cases

        test "constants remain unchanged after module inclusion" do
          another_class = Class.new do
            include ThresholdConstants
          end

          assert_equal TestClass::CRITICAL_ERROR_RATE, another_class::CRITICAL_ERROR_RATE
          assert_equal TestClass::WARNING_ERROR_RATE, another_class::WARNING_ERROR_RATE
        end
      end
    end
  end
end
