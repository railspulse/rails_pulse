require "test_helper"

class ExceptionsIndexPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_exception_groups, :rails_pulse_exception_occurrences

  test "exceptions index page loads with table" do
    assert_page_loads "/exceptions"
    assert_table_has_data
  end

  test "displays exception class names in table" do
    assert_page_loads "/exceptions"

    assert_text "ActiveRecord::RecordNotFound"
    assert_text "ZeroDivisionError"
  end

  test "status filter shows resolved groups" do
    assert_page_loads "/exceptions"

    select "Resolved", from: "q_status_eq"
    click_button "Search"

    assert_text "ArgumentError"
    assert_no_text "ActiveRecord::RecordNotFound"
  end

  test "filter by exception class shows matching results" do
    assert_page_loads "/exceptions"

    fill_in "Filter by exception class", with: "ZeroDivision"
    click_button "Search"

    assert_text "ZeroDivisionError"
    assert_no_text "ActiveRecord::RecordNotFound"
  end

  test "reset link clears the filter" do
    visit_rails_pulse_path "/exceptions?q[exception_class_cont]=ZeroDivision"

    assert_text "Reset"
    click_link "Reset"

    assert_text "ActiveRecord::RecordNotFound"
    assert_text "ZeroDivisionError"
  end

  test "clicking an exception row navigates to the show page" do
    assert_page_loads "/exceptions"

    click_link "ActiveRecord::RecordNotFound"

    assert_current_path %r{/rails_pulse/exceptions/\d+}
    assert_text /exception details/i
  end

  test "empty state is shown when no exceptions match filter" do
    assert_page_loads "/exceptions"

    fill_in "Filter by exception class", with: "NonExistentError"
    click_button "Search"

    assert_text "No exceptions recorded."
  end
end
