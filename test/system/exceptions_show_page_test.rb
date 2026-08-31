require "test_helper"

class ExceptionsShowPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_exception_groups, :rails_pulse_exception_occurrences

  def setup
    super
    @group = rails_pulse_exception_groups(:record_not_found)
    @occurrence = rails_pulse_exception_occurrences(:occurrence_one)
  end

  test "exception show page loads with details panel" do
    assert_page_loads "/exceptions/#{@group.id}"

    assert_text /exception details/i
    assert_text @group.exception_class
    assert_text @group.message
    assert_text @group.location
    assert_text /total seen/i
  end

  test "occurrences table lists occurrences" do
    assert_page_loads "/exceptions/#{@group.id}"

    assert_text /occurrences/i
    assert_table_has_data
  end

  test "clicking an occurrence navigates to the occurrence show page" do
    assert_page_loads "/exceptions/#{@group.id}"

    within "tbody" do
      first("tr td a").click
    end

    assert_current_path %r{/rails_pulse/exceptions/\d+/occurrences/\d+}
    assert_text /occurrence details/i
  end

  test "backtrace panel is shown for the most recent occurrence" do
    assert_page_loads "/exceptions/#{@group.id}"

    assert_text /most recent backtrace/i
    assert_selector ".backtrace"
    assert_selector ".backtrace__frame", minimum: 1
  end

  test "occurrence show page displays occurrence details" do
    visit_rails_pulse_path "/exceptions/#{@group.id}/occurrences/#{@occurrence.id}"

    assert_text /occurrence details/i
    assert_text @occurrence.exception_class
    assert_text @occurrence.request_url
    assert_text @occurrence.request_method
    assert_text @occurrence.environment
  end

  test "occurrence show page displays request params" do
    visit_rails_pulse_path "/exceptions/#{@group.id}/occurrences/#{@occurrence.id}"

    assert_text /request params/i
    assert_selector ".exception-params"
    assert_text "controller"
    assert_text "action"
  end

  test "occurrence show page displays backtrace" do
    visit_rails_pulse_path "/exceptions/#{@group.id}/occurrences/#{@occurrence.id}"

    assert_text /backtrace/i
    assert_selector ".backtrace"
    assert_selector ".backtrace__frame", minimum: 1
  end

  test "occurrence without params does not show params panel" do
    occurrence_without_params = rails_pulse_exception_occurrences(:occurrence_two)
    visit_rails_pulse_path "/exceptions/#{@group.id}/occurrences/#{occurrence_without_params.id}"

    assert_no_text /request params/i
    assert_no_selector ".exception-params"
  end

  test "raw data panel renders a copyable llm context block" do
    assert_page_loads "/exceptions/#{@group.id}"

    assert_text /raw data/i
    assert_selector "[data-controller~='rails-pulse--clipboard']"
    assert_selector "[data-rails-pulse--clipboard-target='source']"
    assert_selector "button[data-action~='click->rails-pulse--clipboard#copy']"
  end
end
