require "test_helper"

class RailsPulse::TagsControllerTest < ActionDispatch::IntegrationTest
  fixtures :rails_pulse_routes, :rails_pulse_requests, :rails_pulse_queries, :rails_pulse_jobs, :rails_pulse_job_runs

  def setup
    ENV["TEST_TYPE"] = "functional"
    super

    # Use fixture data and add tags
    @test_route = rails_pulse_routes(:api_test)
    @test_route.update!(tags: [ "production" ].to_json)

    @test_request = rails_pulse_requests(:users_request_1)
    @test_request.update!(tags: [].to_json)

    @test_query = rails_pulse_queries(:simple_query)
    @test_query.update!(tags: [ "slow" ].to_json)

    @test_job = rails_pulse_jobs(:report_job)
    @test_job.update!(tags: [ "report" ].to_json)

    @test_job_run = rails_pulse_job_runs(:report_run_success)
    @test_job_run.update!(tags: [].to_json)
  end

  test "controller has create action" do
    controller = RailsPulse::TagsController.new

    assert_respond_to controller, :create
  end

  test "controller has destroy action" do
    controller = RailsPulse::TagsController.new

    assert_respond_to controller, :destroy
  end

  test "controller has required private methods" do
    controller = RailsPulse::TagsController.new
    private_methods = controller.private_methods

    assert_includes private_methods, :set_taggable
  end

  test "controller inherits from ApplicationController" do
    assert_operator RailsPulse::TagsController, :<, RailsPulse::ApplicationController
  end

  test "create action adds tag to route" do
    assert_difference -> { @test_route.reload.tag_list.count }, 1 do
      post rails_pulse_engine.add_tag_path("route", @test_route.id, tag: "staging")
    end

    assert_includes @test_route.reload.tag_list, "staging"
    assert_response :success
  end

  test "create action adds tag to request" do
    assert_difference -> { @test_request.reload.tag_list.count }, 1 do
      post rails_pulse_engine.add_tag_path("request", @test_request.id, tag: "critical")
    end

    assert_includes @test_request.reload.tag_list, "critical"
    assert_response :success
  end

  test "create action adds tag to query" do
    assert_difference -> { @test_query.reload.tag_list.count }, 1 do
      post rails_pulse_engine.add_tag_path("query", @test_query.id, tag: "needs-optimization")
    end

    assert_includes @test_query.reload.tag_list, "needs-optimization"
    assert_response :success
  end

  test "create action adds tag to job" do
    assert_difference -> { @test_job.reload.tag_list.count }, 1 do
      post rails_pulse_engine.add_tag_path("job", @test_job.id, tag: "background")
    end

    assert_includes @test_job.reload.tag_list, "background"
    assert_response :success
  end

  test "create action adds tag to job_run" do
    assert_difference -> { @test_job_run.reload.tag_list.count }, 1 do
      post rails_pulse_engine.add_tag_path("job_run", @test_job_run.id, tag: "retry")
    end

    assert_includes @test_job_run.reload.tag_list, "retry"
    assert_response :success
  end

  test "create action does not add duplicate tags" do
    post rails_pulse_engine.add_tag_path("route", @test_route.id, tag: "production")

    assert_equal 1, @test_route.reload.tag_list.count
    assert_response :success
  end

  test "create action renders turbo stream response" do
    post rails_pulse_engine.add_tag_path("route", @test_route.id, tag: "staging")

    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  test "create action handles blank tag" do
    assert_no_difference -> { @test_route.reload.tag_list.count } do
      post rails_pulse_engine.add_tag_path("route", @test_route.id, tag: "")
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  test "create action handles nil tag" do
    assert_no_difference -> { @test_route.reload.tag_list.count } do
      post rails_pulse_engine.add_tag_path("route", @test_route.id, tag: nil)
    end

    assert_response :success
  end

  test "destroy action removes tag from route" do
    assert_difference -> { @test_route.reload.tag_list.count }, -1 do
      delete rails_pulse_engine.remove_tag_path("route", @test_route.id, tag: "production")
    end

    assert_not_includes @test_route.reload.tag_list, "production"
    assert_response :success
  end

  test "destroy action removes tag from request" do
    @test_request.add_tag("critical")

    assert_difference -> { @test_request.reload.tag_list.count }, -1 do
      delete rails_pulse_engine.remove_tag_path("request", @test_request.id, tag: "critical")
    end

    assert_not_includes @test_request.reload.tag_list, "critical"
    assert_response :success
  end

  test "destroy action removes tag from query" do
    assert_difference -> { @test_query.reload.tag_list.count }, -1 do
      delete rails_pulse_engine.remove_tag_path("query", @test_query.id, tag: "slow")
    end

    assert_not_includes @test_query.reload.tag_list, "slow"
    assert_response :success
  end

  test "destroy action removes tag from job" do
    assert_difference -> { @test_job.reload.tag_list.count }, -1 do
      delete rails_pulse_engine.remove_tag_path("job", @test_job.id, tag: "report")
    end

    assert_not_includes @test_job.reload.tag_list, "report"
    assert_response :success
  end

  test "destroy action removes tag from job_run" do
    @test_job_run.add_tag("failed")

    assert_difference -> { @test_job_run.reload.tag_list.count }, -1 do
      delete rails_pulse_engine.remove_tag_path("job_run", @test_job_run.id, tag: "failed")
    end

    assert_not_includes @test_job_run.reload.tag_list, "failed"
    assert_response :success
  end

  test "destroy action renders turbo stream response" do
    delete rails_pulse_engine.remove_tag_path("route", @test_route.id, tag: "production")

    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  test "destroy action handles non-existent tag gracefully" do
    assert_no_difference -> { @test_route.reload.tag_list.count } do
      delete rails_pulse_engine.remove_tag_path("route", @test_route.id, tag: "nonexistent")
    end

    assert_response :success
  end

  test "set_taggable handles invalid taggable type" do
    post rails_pulse_engine.add_tag_path("invalid_type", 1, tag: "test")

    assert_response :not_found
  end

  test "create action with multiple tags on same record" do
    post rails_pulse_engine.add_tag_path("route", @test_route.id, tag: "staging")
    post rails_pulse_engine.add_tag_path("route", @test_route.id, tag: "critical")

    @test_route.reload

    assert_equal 3, @test_route.tag_list.count
    assert_includes @test_route.tag_list, "production"
    assert_includes @test_route.tag_list, "staging"
    assert_includes @test_route.tag_list, "critical"
  end

  test "destroy action removes only specified tag" do
    @test_route.add_tag("staging")
    @test_route.add_tag("critical")

    delete rails_pulse_engine.remove_tag_path("route", @test_route.id, tag: "staging")

    @test_route.reload

    assert_equal 2, @test_route.tag_list.count
    assert_includes @test_route.tag_list, "production"
    assert_includes @test_route.tag_list, "critical"
    assert_not_includes @test_route.tag_list, "staging"
  end

  private

  def rails_pulse_engine
    RailsPulse::Engine.routes.url_helpers
  end
end
