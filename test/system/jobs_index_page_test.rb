require "test_helper"

class JobsIndexPageTest < ApplicationSystemTestCase
  test "jobs index page loads with data" do
    assert_page_loads "/jobs"
    assert_metric_cards_present(count: 3)
    assert_table_has_data
  end
end
