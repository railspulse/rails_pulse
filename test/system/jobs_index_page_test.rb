require "test_helper"

class JobsIndexPageTest < ApplicationSystemTestCase
  def setup
    super
    @report_job = rails_pulse_jobs(:report_job)
    @mailer_job = rails_pulse_jobs(:mailer_job)
  end

  test "index page displays job metrics and table data" do
    visit_rails_pulse_path "/jobs"

    assert_current_path "/rails_pulse/jobs"
    assert_selector "#jobs_total_runs", wait: 5
    assert_selector "#jobs_failure_rate"
    assert_selector "#jobs_average_duration"

    within("table tbody") do
      assert_text @report_job.name
      assert_text @mailer_job.name
    end
  end

  test "jobs index filters by name" do
    visit_rails_pulse_path "/jobs"

    fill_in "q[name_cont]", with: "Mailer"
    click_button "Search"

    within("table tbody") do
      assert_text @mailer_job.name
      assert_no_text @report_job.name
    end

    click_link "Reset"

    within("table tbody") do
      assert_text @report_job.name
    end
  end

  test "jobs index filters by queue" do
    visit_rails_pulse_path "/jobs"

    select "mailers", from: "q[queue_name_eq]"
    click_button "Search"

    within("table tbody") do
      assert_text @mailer_job.name
      assert_no_text @report_job.name
    end
  end

  test "jobs index shows empty state when no jobs exist" do
    RailsPulse::Job.destroy_all

    visit_rails_pulse_path "/jobs"

    assert_text "No jobs found"
    assert_text "No background jobs have been executed yet."
  end
end
