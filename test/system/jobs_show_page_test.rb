require "test_helper"

class JobsShowPageTest < ApplicationSystemTestCase
  def setup
    super
    @job = rails_pulse_jobs(:report_job)
    @failed_run = rails_pulse_job_runs(:report_run_failed)
    @original_tags = RailsPulse.configuration.tags.dup
    RailsPulse.configuration.tags = (@original_tags | [ "report", "critical", "maintenance" ])
  end

  def teardown
    RailsPulse.configuration.tags = @original_tags
    super
  end

  test "job show displays metrics and allows navigation to job run" do
    visit_job_show

    assert_selector "#jobs_total_runs", wait: 5
    assert_selector "#jobs_failure_rate"
    assert_selector "#jobs_average_duration"
    assert_selector "table tbody tr", minimum: 1

    latest_run = @job.runs.order(occurred_at: :desc).first
    # HTML collapses multiple spaces, so we normalize the timestamp
    timestamp = latest_run.occurred_at.in_time_zone.strftime("%b %d, %Y %l:%M %p").gsub(/\s+/, " ").strip

    click_link timestamp

    assert_current_path "/rails_pulse/jobs/#{@job.id}/runs/#{latest_run.id}"
    assert_selector "h2", text: /job run details/i
  end

  test "job show filters by status and duration" do
    visit_job_show

    select "Retried", from: "q[status_eq]"
    click_button "Search"

    within("table tbody") do
      assert_text "Retried"
      assert_no_text "Failed"
    end

    select "Slow (≥ 5000ms)", from: "q[duration_gteq]"
    click_button "Search"

    assert_text "No runs found"

    click_link "Reset"

    within("table tbody") do
      assert_text "Failed"
      assert_text "Retried"
    end
  end

  test "job tag manager allows removing and re-adding tags" do
    visit_job_show

    tag_manager_selector = "#tag_manager_job_#{@job.id}"

    within(tag_manager_selector) do
      assert_text "Report"
      find("button.tag-remove", match: :first).click
    end

    assert_selector tag_manager_selector

    within(tag_manager_selector) do
      assert_no_text "Report"
    end

    within(tag_manager_selector) do
      find("button.tag-add-button").click
    end

    menu_id = "#tag_menu_job_#{@job.id}"

    assert_selector menu_id

    within(menu_id) do
      click_button "Report"
    end

    assert_selector "#{tag_manager_selector} .badge", text: "Report", wait: 5
  end

  private

  def visit_job_show
    visit_rails_pulse_path "/jobs/#{@job.id}"
  end
end
