require "test_helper"

class JobsShowPageTest < ApplicationSystemTestCase
  def setup
    super
    @job = rails_pulse_jobs(:report_job)
  end

  test "job show page loads" do
    assert_page_loads "/jobs/#{@job.id}"
    assert_selector ".card.metric-strip"
  end
end
