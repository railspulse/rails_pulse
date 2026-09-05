require "test_helper"

class RailsPulse::SchemaCheckTest < ActiveSupport::TestCase
  def setup
    super
    RailsPulse::SchemaCheck.reset!
  end

  def teardown
    RailsPulse::SchemaCheck.reset!
    super
  end

  # Structure Tests

  test "expected_schema is read from the gem's own schema file" do
    expected = RailsPulse::SchemaCheck.expected_schema

    assert_includes expected.keys, "rails_pulse_routes"
    assert_includes expected["rails_pulse_routes"].keys, "http_methods"
    assert_includes expected["rails_pulse_requests"].keys, "method"
    assert_includes expected.keys, "rails_pulse_exception_groups"
  end

  test "current schema has nothing missing" do
    assert_predicate RailsPulse::SchemaCheck, :current?
    assert_empty RailsPulse::SchemaCheck.missing
  end

  # Drift Detection Tests

  test "missing lists columns the live table lacks" do
    stub_expected_schema("rails_pulse_routes" => { "http_methods" => {}, "not_a_real_column" => {} })

    assert_not_predicate RailsPulse::SchemaCheck, :current?
    assert_equal({ "rails_pulse_routes" => [ "not_a_real_column" ] }, RailsPulse::SchemaCheck.missing)
  end

  test "missing marks a table that does not exist" do
    stub_expected_schema("rails_pulse_not_a_table" => { "id" => {} })

    assert_equal({ "rails_pulse_not_a_table" => [ :table ] }, RailsPulse::SchemaCheck.missing)
  end

  test "the comparison is memoized after it completes" do
    RailsPulse::SchemaCheck.missing
    RailsPulse::SchemaCheck.stubs(:expected_schema).returns("rails_pulse_routes" => { "ghost" => {} })

    assert_predicate RailsPulse::SchemaCheck, :current?
  end

  test "reset! discards the memoized comparison" do
    RailsPulse::SchemaCheck.missing
    RailsPulse::SchemaCheck.reset!
    stub_expected_schema("rails_pulse_routes" => { "ghost" => {} })

    assert_not_predicate RailsPulse::SchemaCheck, :current?
  end

  # Tracking Gate Tests

  test "tracking_allowed? is true when the schema is current" do
    assert_predicate RailsPulse::SchemaCheck, :tracking_allowed?
  end

  test "tracking_allowed? refuses and logs the upgrade instructions exactly once when outdated" do
    stub_expected_schema("rails_pulse_routes" => { "ghost" => {} })
    output = StringIO.new
    RailsPulse.stubs(:logger).returns(Logger.new(output))

    assert_not RailsPulse::SchemaCheck.tracking_allowed?
    assert_not RailsPulse::SchemaCheck.tracking_allowed?

    assert_equal 1, output.string.scan("rails generate rails_pulse:upgrade").size
    assert_match(/rails_pulse_routes: ghost/, output.string)
  end

  # Edge Cases

  test "a database error is not treated as an outdated schema and is not memoized" do
    RailsPulse::ApplicationRecord.stubs(:connection).raises(ActiveRecord::ConnectionNotEstablished)

    assert_predicate RailsPulse::SchemaCheck, :current?

    RailsPulse::ApplicationRecord.unstub(:connection)
    stub_expected_schema("rails_pulse_routes" => { "ghost" => {} })

    assert_not_predicate RailsPulse::SchemaCheck, :current?
  end

  private

  def stub_expected_schema(schema)
    RailsPulse::SchemaCheck.reset!
    RailsPulse::SchemaCheck.stubs(:expected_schema).returns(schema)
  end
end
