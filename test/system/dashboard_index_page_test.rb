require "test_helper"

class DashboardIndexPageTest < ApplicationSystemTestCase
  def setup
    super
    create_summary_data_for_dashboard
  end

  def test_dashboard_index_page_loads_and_displays_key_panels
    visit_rails_pulse_path "/"

    assert_selector "body"
    assert_current_path "/rails_pulse/"

    # Health bar
    assert_text "System Health"
    assert_text "Routes"
    assert_text "Queries"

    # Metric strip
    assert_text "RESPONSE TIME PERCENTILES"
    assert_text "REQUEST COUNT TOTAL"
    assert_text "ERROR RATE"

    # Charts
    assert_selector "#response_time_percentiles_chart"
    assert_selector "#throughput_and_errors_chart"

    # Needs Attention panel
    assert_text "Needs Attention"
  end

  def test_response_time_percentiles_chart_is_present
    visit_rails_pulse_path "/"

    assert_text "RESPONSE TIME PERCENTILES", wait: 5
    assert_selector "#response_time_percentiles_chart", wait: 5
  end

  def test_throughput_and_errors_chart_is_present
    visit_rails_pulse_path "/"

    assert_text "Throughput", wait: 5
    assert_selector "#throughput_and_errors_chart", wait: 5
  end

  def test_needs_attention_panel_is_present
    visit_rails_pulse_path "/"

    assert_text "Needs Attention", wait: 5
  end

  private

  def create_summary_data_for_dashboard
    service = RailsPulse::SummaryService.new("hour", Time.current.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("hour", 1.hour.ago.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("hour", 2.hours.ago.beginning_of_hour)
    service.perform

    service = RailsPulse::SummaryService.new("day", Time.current.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("day", 1.day.ago.beginning_of_day)
    service.perform

    service = RailsPulse::SummaryService.new("day", 2.days.ago.beginning_of_day)
    service.perform
  end
end
