require "test_helper"

class StoragePageTest < ApplicationSystemTestCase
  fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_summaries,
           :rails_pulse_requests, :rails_pulse_operations

  test "dashboard storage panel links to the storage page" do
    visit_rails_pulse_path "/"

    assert_selector ".storage-panel-stats"
    assert_text "HIGHEST FILL"
    assert_text "PULSE RECORDS"
    assert_text "CLEANUP"

    find("a[href='/rails_pulse/storage']", match: :first).click

    assert_current_path "/rails_pulse/storage"
    assert_text "Operations"
    assert_text "Requests"
    assert_text "TABLES"
    assert_text "CLEANUP"
    assert_text "DATABASE"
  end
end
