require "test_helper"

module RailsPulse
  module Cloud
    class InstallationTest < ActiveSupport::TestCase
      setup do
        Installation.delete_all
      end

      # Structure Tests

      test "current creates the row with a new installation ID once, then returns it" do
        first = Installation.current

        assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, first.installation_id)
        assert_equal first, Installation.current
        assert_equal 1, Installation.count
      end

      test "existing never creates the row" do
        assert_nil Installation.existing
        assert_equal 0, Installation.count
      end

      # Calculation Tests

      test "a success clears the error and any pause" do
        installation = Installation.current
        installation.pause!(1.hour.from_now, "refused")

        installation.record_success!(deprecated_on: "2027-10-01")

        assert_not_predicate installation, :paused?
        assert_nil installation.last_error
        assert_equal "2027-10-01", installation.contract_deprecated_on
      end

      # Edge Cases

      test "a pause that has passed no longer pauses" do
        installation = Installation.current
        installation.pause!(1.minute.ago, "refused")

        assert_not_predicate installation, :paused?
      end
    end
  end
end
