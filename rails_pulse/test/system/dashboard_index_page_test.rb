class DashboardIndexPageTest < ApplicationSystemTestCase
  test 'metric cards display data correctly' do
    visit dashboard_index_url

    assert_selector 'h1', text: 'Dashboard'
    assert_selector '.metric-card', count: 3
    assert_selector '.metric-card', text: 'Expected Metric Data'
  end
end
