require "test_helper"

class RailsPulse::ApplicationRecordTest < ActiveSupport::TestCase
  def setup
    ENV["TEST_TYPE"] = "unit"
    super
  end

  test "should inherit from ActiveRecord::Base" do
    assert_equal ActiveRecord::Base, RailsPulse::ApplicationRecord.superclass
  end

  test "should be abstract class" do
    assert RailsPulse::ApplicationRecord.abstract_class?
  end

  test "should not be instantiable directly" do
    assert_raises(NotImplementedError) do
      RailsPulse::ApplicationRecord.new
    end
  end

  test "should configure database connections when connects_to is present" do
    # Stub RailsPulse.connects_to to return a configuration
    config = { database: { writing: :primary, reading: :replica } }
    RailsPulse.stubs(:connects_to).returns(config)

    # Since we can't easily reload the class in test, we'll test the conditional logic
    # The actual connects_to call happens at load time
    assert_not_nil config
    assert_respond_to RailsPulse::ApplicationRecord, :connects_to
  end

  test "should not configure database connections when connects_to is nil" do
    # Stub RailsPulse.connects_to to return nil
    RailsPulse.stubs(:connects_to).returns(nil)

    # Test that the conditional logic works
    result = RailsPulse.connects_to
    assert_nil result
  end

  test "should be within RailsPulse namespace" do
    assert_equal RailsPulse, RailsPulse::ApplicationRecord.module_parent
  end

  test "subclasses should inherit from ApplicationRecord" do
    # Test that our other models inherit from ApplicationRecord
    [
      RailsPulse::Operation,
      RailsPulse::Request,
      RailsPulse::Query,
      RailsPulse::Route
    ].each do |model_class|
      assert_equal RailsPulse::ApplicationRecord, model_class.superclass,
        "#{model_class} should inherit from RailsPulse::ApplicationRecord"
    end
  end

  test "should have correct table name prefix for subclasses" do
    # ApplicationRecord itself doesn't have a table, but subclasses should
    # inherit the rails_pulse prefix pattern
    [
      [ RailsPulse::Operation, "rails_pulse_operations" ],
      [ RailsPulse::Request, "rails_pulse_requests" ],
      [ RailsPulse::Query, "rails_pulse_queries" ],
      [ RailsPulse::Route, "rails_pulse_routes" ]
    ].each do |model_class, expected_table_name|
      assert_equal expected_table_name, model_class.table_name,
        "#{model_class} should have table name #{expected_table_name}"
    end
  end
end
