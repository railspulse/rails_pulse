require "test_helper"

class JobRunsShowPageTest < ApplicationSystemTestCase
  def setup
    super
    @success_run = rails_pulse_job_runs(:mailer_run_success)
    @failed_run = rails_pulse_job_runs(:report_run_failed)
    @operation_run = rails_pulse_job_runs(:report_run_retried)
    @operation = rails_pulse_operations(:job_sql_operation)
  end

  test "job run show displays arguments for successful run" do
    visit_job_run(@success_run)

    assert_selector "h2", text: /job run details/i
    assert_selector "pre", text: /user_id/
    assert_no_text "Error Details"
  end

  test "job run show displays error details for failed runs" do
    visit_job_run(@failed_run)

    assert_selector "h2", text: /job run details/i
    assert_selector "h2", text: /error details/i
    assert_text "StandardError"
    assert_text "Reporting failed due to timeout"
  end

  test "job run operations link to operation detail" do
    visit_job_run(@operation_run)

    assert_selector ".operations-table tbody tr", minimum: 1

    find("a[title='View details']", match: :first).click

    assert_current_path "/rails_pulse/operations/#{@operation.id}"
    assert_text "Job Run Impact"
  end

  private

  def visit_job_run(run)
    visit_rails_pulse_path "/jobs/#{run.job_id}/runs/#{run.id}"
  end
end
