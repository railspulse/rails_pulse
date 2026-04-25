require "test_helper"

class RailsPulseTest < ActiveSupport::TestCase
  test "it has a version number" do
    assert RailsPulse::VERSION
  end

  # Pro Detection

  test "pro? returns false when rails_pulse_pro is not loaded" do
    refute RailsPulse.pro?
  end
end
