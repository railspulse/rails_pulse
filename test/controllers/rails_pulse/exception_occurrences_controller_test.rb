require "test_helper"

class RailsPulse::ExceptionOccurrencesControllerTest < ActionDispatch::IntegrationTest
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  fixtures :rails_pulse_exception_groups, :rails_pulse_exception_occurrences

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @group = rails_pulse_exception_groups(:record_not_found)
    @occurrence = rails_pulse_exception_occurrences(:occurrence_one)
  end

  # Controller Structure Tests

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::ExceptionOccurrencesController, :<, RailsPulse::ApplicationController
  end

  test "controller has show action" do
    controller = RailsPulse::ExceptionOccurrencesController.new

    assert_respond_to controller, :show
  end

  # Show Action Tests

  test "show responds successfully" do
    get rails_pulse.exception_occurrence_path(@group, @occurrence)

    assert_response :success
  end

  test "show assigns exception_group" do
    get rails_pulse.exception_occurrence_path(@group, @occurrence)

    assert_equal @group, assigns(:exception_group)
  end

  test "show assigns occurrence" do
    get rails_pulse.exception_occurrence_path(@group, @occurrence)

    assert_equal @occurrence, assigns(:occurrence)
  end

  test "show occurrence belongs to the requested group" do
    get rails_pulse.exception_occurrence_path(@group, @occurrence)

    assert_equal @group.id, assigns(:occurrence).exception_group_id
  end

  test "show works for occurrence without params" do
    occurrence = rails_pulse_exception_occurrences(:occurrence_two)

    get rails_pulse.exception_occurrence_path(@group, occurrence)

    assert_response :success
    assert_empty assigns(:occurrence).request_params
  end

  test "show works for job occurrence without request context" do
    group = rails_pulse_exception_groups(:zero_division)
    occurrence = rails_pulse_exception_occurrences(:occurrence_zero_division)

    get rails_pulse.exception_occurrence_path(group, occurrence)

    assert_response :success
    assert_nil assigns(:occurrence).request_url
  end

  # Edge Cases

  test "show returns 404 for unknown occurrence id" do
    get rails_pulse.exception_occurrence_path(@group, id: 0)

    assert_response :not_found
  end

  test "show returns 404 for unknown exception group id" do
    get rails_pulse.exception_occurrence_path(id: 0, exception_id: 0)

    assert_response :not_found
  end

  test "show returns 404 when occurrence belongs to a different group" do
    other_group = rails_pulse_exception_groups(:zero_division)

    get rails_pulse.exception_occurrence_path(other_group, @occurrence)

    assert_response :not_found
  end
end
