require "test_helper"

class RequestsIndexPageTest < ApplicationSystemTestCase
  test "requests index page loads with data" do
    assert_page_loads "/requests"
    assert_table_has_data
  end
end
