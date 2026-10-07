require "test_helper"

module RailsPulse
  class CloudJobsTest < ActiveJob::TestCase
    setup do
      @cloud = RailsPulse.configuration.cloud
      @saved = @cloud.to_h
    end

    teardown do
      @saved.each { |key, value| @cloud.public_send(:"#{key}=", value) }
    end

    # Structure Tests

    test "CloudSyncJob runs the hourly sync" do
      Cloud::Sync.any_instance.expects(:hourly).once

      CloudSyncJob.perform_now
    end

    test "CloudHealthJob runs the minutely sync" do
      Cloud::Sync.any_instance.expects(:minutely).once

      CloudHealthJob.perform_now
    end

    # Calculation Tests

    test "SummaryJob enqueues the Cloud sync once its summaries are written, when Cloud is on" do
      @cloud.api_key = "rpc_4f9Kx2mQ8vTzL1nB7wYc3HdR6sJe5PaU"
      @cloud.application = "shop"

      assert_enqueued_with(job: CloudSyncJob) { SummaryJob.perform_now(2.hours.ago.beginning_of_hour) }
    end

    # Edge Cases

    test "SummaryJob enqueues nothing for Cloud when it is off" do
      assert_no_enqueued_jobs(only: CloudSyncJob) { SummaryJob.perform_now(2.hours.ago.beginning_of_hour) }
    end

    test "a queue that refuses the Cloud sync does not fail the summaries" do
      @cloud.api_key = "rpc_4f9Kx2mQ8vTzL1nB7wYc3HdR6sJe5PaU"
      @cloud.application = "shop"
      CloudSyncJob.stubs(:perform_later).raises(StandardError, "queue down")

      assert_nothing_raised { SummaryJob.perform_now(2.hours.ago.beginning_of_hour) }
    end
  end
end
