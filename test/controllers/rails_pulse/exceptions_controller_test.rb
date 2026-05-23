require "test_helper"

class RailsPulse::ExceptionsControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  fixtures :rails_pulse_exception_groups, :rails_pulse_exception_occurrences

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @group = rails_pulse_exception_groups(:record_not_found)
  end

  # Controller Structure Tests

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::ExceptionsController, :<, RailsPulse::ApplicationController
  end

  test "controller has index and show actions" do
    controller = RailsPulse::ExceptionsController.new

    assert_respond_to controller, :index
    assert_respond_to controller, :show
  end

  # Index Action Tests

  test "index responds successfully" do
    get rails_pulse.exceptions_path

    assert_response :success
  end

  test "index assigns table_data" do
    get rails_pulse.exceptions_path

    assert_not_nil assigns(:table_data)
  end

  test "index assigns pagination" do
    get rails_pulse.exceptions_path

    assert_not_nil assigns(:pagination)
  end

  test "index table_data includes fixture groups" do
    get rails_pulse.exceptions_path

    exception_classes = assigns(:table_data).map(&:exception_class)

    assert_includes exception_classes, "ActiveRecord::RecordNotFound"
    assert_includes exception_classes, "ZeroDivisionError"
  end

  test "index filters by exception_class via ransack" do
    get rails_pulse.exceptions_path, params: { q: { exception_class_cont: "ZeroDivision" } }

    assert_response :success
    exception_classes = assigns(:table_data).map(&:exception_class)

    assert_includes exception_classes, "ZeroDivisionError"
    refute_includes exception_classes, "ActiveRecord::RecordNotFound"
  end

  test "index respects pagination limit" do
    get rails_pulse.exceptions_path, params: { limit: 5 }

    assert_response :success
    assert_not_nil assigns(:pagination)
    assert_operator assigns(:table_data).to_a.size, :<=, 5
  end

  test "index defaults to ordering by last_seen_at desc" do
    get rails_pulse.exceptions_path

    results = assigns(:table_data).to_a
    if results.size > 1
      results.each_cons(2) do |a, b|
        assert_operator a.last_seen_at, :>=, b.last_seen_at
      end
    end
  end

  # Show Action Tests

  test "show responds successfully" do
    get rails_pulse.exception_path(@group)

    assert_response :success
  end

  test "show assigns exception_group" do
    get rails_pulse.exception_path(@group)

    assert_equal @group, assigns(:exception_group)
  end

  test "show assigns occurrences" do
    get rails_pulse.exception_path(@group)

    assert_not_nil assigns(:occurrences)
  end

  test "show assigns latest_occurrence" do
    get rails_pulse.exception_path(@group)

    assert_not_nil assigns(:latest_occurrence)
  end

  test "show occurrences belong to the requested group" do
    get rails_pulse.exception_path(@group)

    assigns(:occurrences).each do |occurrence|
      assert_equal @group.id, occurrence.exception_group_id
    end
  end

  test "show returns 404 for unknown id" do
    get rails_pulse.exception_path(id: 0)

    assert_response :not_found
  end

  test "show latest_occurrence is the most recently occurred one for the group" do
    get rails_pulse.exception_path(@group)

    latest = assigns(:latest_occurrence)
    # occurrence_one occurred_at 1.hour.ago, occurrence_two at 2.hours.ago
    # latest must be occurrence_one (more recent)
    assert_equal rails_pulse_exception_occurrences(:occurrence_one).id, latest.id
  end

  test "show latest_occurrence is nil when the group has no occurrences" do
    empty_group = RailsPulse::ExceptionGroup.create!(
      fingerprint: "empty_group_fp_#{SecureRandom.hex(4)}",
      exception_class: "EmptyError",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    get rails_pulse.exception_path(empty_group)

    assert_nil assigns(:latest_occurrence)
  end

  test "exceptions routes are accessible when track_exceptions is true (default)" do
    assert RailsPulse.configuration.track_exceptions,
      "track_exceptions must be true for this test to be meaningful"

    get rails_pulse.exceptions_path

    assert_response :success
  end

  test "exception_occurrences route is nested under exceptions" do
    occurrence = rails_pulse_exception_occurrences(:occurrence_one)

    get rails_pulse.exception_occurrence_path(@group, occurrence)

    assert_response :success
  end
end
