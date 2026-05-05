require "test_helper"

class RailsPulseTest < ActiveSupport::TestCase
  test "it has a version number" do
    assert RailsPulse::VERSION
  end

  test "logger falls back to stdout when Rails.logger is nil" do
    original = Rails.logger
    Rails.logger = nil
    RailsPulse.instance_variable_set(:@logger, nil)

    logger = RailsPulse.logger
    assert_respond_to logger, :warn
    assert_respond_to logger, :info
  ensure
    Rails.logger = original
    RailsPulse.instance_variable_set(:@logger, nil)
  end

  test "logger is not memoized when falling back so real logger is picked up later" do
    original = Rails.logger
    Rails.logger = nil
    RailsPulse.instance_variable_set(:@logger, nil)

    # First call with nil Rails.logger returns a fallback logger
    fallback_logger = RailsPulse.logger

    # Simulate Rails finishing boot and providing a real logger
    Rails.logger = original

    # Next call should pick up the real logger, not the fallback
    real_logger = RailsPulse.logger
    assert_respond_to real_logger, :tagged
    assert_respond_to real_logger, :formatter
    assert_not_equal fallback_logger, real_logger
  ensure
    Rails.logger = original
    RailsPulse.instance_variable_set(:@logger, nil)
  end
end
