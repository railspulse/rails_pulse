require "test_helper"

class RoutesShowPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_routes

  def setup
    super
    @route = rails_pulse_routes(:api_users)
  end

  test "route show page displays data" do
    assert_page_loads "/routes/#{@route.id}"
    assert_selector ".card.metric-strip"
    assert_selector "table"
  end

  test "displays route information" do
    assert_page_loads "/routes/#{@route.id}"
    assert_text @route.path
  end
end
