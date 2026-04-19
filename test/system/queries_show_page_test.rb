require "test_helper"

class QueriesShowPageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_queries

  def setup
    super
    @query = rails_pulse_queries(:complex_query)
  end

  test "query show page displays data" do
    assert_page_loads "/queries/#{@query.id}"
    assert_selector ".card.metric-strip"
    assert_selector "table"
  end

  test "displays query SQL" do
    assert_page_loads "/queries/#{@query.id}"
    assert_text @query.normalized_sql
  end
end
