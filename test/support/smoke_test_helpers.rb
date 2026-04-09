# Lightweight smoke test helpers for system tests
# These helpers check for presence of page elements without validating specific data
module SmokeTestHelpers
  # Verifies basic page structure loads
  def assert_page_loads(path)
    visit_rails_pulse_path path

    assert_selector "body"
    assert_current_path "/rails_pulse#{path}"
  end

  # Verifies metric cards section exists with data
  def assert_metric_cards_present(count: nil)
    assert_selector ".metric-strip"
    assert_selector ".metric-strip__section", count: count if count
  end

  # Verifies a specific metric card displays data
  def assert_metric_card_displays_data(selector)
    assert_selector selector
    within(selector) do
      # Just verify the card has some text content, not specific values
      assert_operator text.length, :>, 0
    end
  end

  # Verifies chart renders
  def assert_chart_renders(chart_id)
    assert_selector "##{chart_id}"
    assert_selector "##{chart_id}[data-chart-rendered='true']", wait: 10
  end

  # Verifies table has data rows
  def assert_table_has_data(minimum: 1)
    assert_selector "table tbody tr", minimum: minimum, wait: 5
  end

  # Verifies a basic Stimulus interaction works
  def assert_stimulus_interaction(trigger_selector:, result_selector:, action: :click)
    element = find(trigger_selector)
    element.send(action)

    assert_selector result_selector, wait: 5
  end
end
