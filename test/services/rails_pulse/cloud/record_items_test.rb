require "test_helper"

module RailsPulse
  module Cloud
    class RecordItemsTest < ActiveSupport::TestCase
      fixtures :rails_pulse_exception_groups

      # Structure Tests

      test "an exception group is sent without its message" do
        group = rails_pulse_exception_groups(:record_not_found)
        item = RecordItems.exception_group(group)

        assert_equal "exception_group", item[:type]
        assert_equal group.fingerprint, item[:fingerprint]
        assert_equal group.exception_class, item[:exception_class]
        assert_equal group.location, item[:location]
        assert_equal group.occurrence_count, item[:occurrence_count]
        assert_equal group.last_seen_at.utc.iso8601, item[:last_seen_at]
        assert_not item.key?(:message)
        assert_not_includes item.values.map(&:to_s), group.message
      end

      test "a deployment is sent with its metadata as recorded" do
        deployment = Deployment.create!(revision: "a1b2c3d", started_at: 2.hours.ago, finished_at: 1.hour.ago,
                                        metadata: { "deployer" => "jane", "branch" => "main" }.to_json)
        item = RecordItems.deployment(deployment)

        assert_equal "a1b2c3d", item[:revision]
        assert_equal deployment.finished_at.utc.iso8601, item[:finished_at]
        assert_equal({ "deployer" => "jane", "branch" => "main" }, item[:metadata])
      end

      # Calculation Tests

      test "exception groups and deployments are selected by when their rows changed" do
        ExceptionGroup.update_all(updated_at: 3.hours.ago)
        changed = rails_pulse_exception_groups(:zero_division)
        changed.update!(status: "resolved")
        Deployment.delete_all
        Deployment.create!(revision: "old", started_at: 5.hours.ago).update_columns(updated_at: 5.hours.ago)
        Deployment.create!(revision: "new", started_at: 10.minutes.ago)
        window = 1.hour.ago...1.minute.from_now

        assert_equal [ changed.fingerprint ], RecordItems.exception_groups_updated(window).map { |item| item[:fingerprint] }
        assert_equal [ "new" ], RecordItems.deployments_updated(window).map { |item| item[:revision] }
      end

      # Edge Cases

      test "metadata over 4 KB is replaced with a truncation marker" do
        assert_equal({ "truncated" => true }, RecordItems.metadata({ "notes" => "x" * 5_000 }))
      end

      test "a deployment without metadata or a finish time sends an empty object and null" do
        item = RecordItems.deployment(Deployment.new(revision: "abc", started_at: Time.current))

        assert_empty(item[:metadata])
        assert_nil item[:finished_at]
      end
    end
  end
end
