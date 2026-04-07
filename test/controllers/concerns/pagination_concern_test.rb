require "test_helper"
require "ostruct"

class PaginationConcernTest < ActionController::TestCase
  class TestController < ActionController::Base
    include PaginationConcern

    attr_accessor :params, :session
    attr_writer :xhr, :patch, :turbo_frame_request_value, :action_name_value

    def initialize
      super
      @params = ActionController::Parameters.new({})
      @session = {}
      @xhr = false
      @patch = false
      @turbo_frame_request_value = false
      @action_name_value = "set_pagination_limit"
      @rendered = nil
    end

    def request
      @_request ||= OpenStruct.new(xhr?: @xhr, patch?: @patch)
    end

    def action_name
      @action_name_value
    end

    def turbo_frame_request?
      @turbo_frame_request_value
    end

    def render(options = {})
      @rendered = options
    end

    attr_reader :rendered
  end

  fixtures :rails_pulse_summaries

  def setup
    ENV["TEST_TYPE"] = "functional"
    super

    # Clean up summaries to avoid interference with pagination tests
    RailsPulse::Summary.delete_all

    @controller = TestController.new
  end

  # set_pagination_limit Tests

  test "set_pagination_limit sets session with validated limit" do
    @controller.params = ActionController::Parameters.new({ limit: 25 })

    @controller.send(:set_pagination_limit)

    assert_equal 25, @controller.session[:pagination_limit]
  end

  test "set_pagination_limit clamps limit to minimum of 5" do
    @controller.params = ActionController::Parameters.new({ limit: 1 })

    @controller.send(:set_pagination_limit)

    assert_equal 5, @controller.session[:pagination_limit]
  end

  test "set_pagination_limit clamps limit to maximum of 50" do
    @controller.params = ActionController::Parameters.new({ limit: 100 })

    @controller.send(:set_pagination_limit)

    assert_equal 50, @controller.session[:pagination_limit]
  end

  test "set_pagination_limit handles zero limit by clamping to 5" do
    @controller.params = ActionController::Parameters.new({ limit: 0 })

    @controller.send(:set_pagination_limit)

    assert_equal 5, @controller.session[:pagination_limit]
  end

  test "set_pagination_limit handles negative limit by clamping to 5" do
    @controller.params = ActionController::Parameters.new({ limit: -10 })

    @controller.send(:set_pagination_limit)

    assert_equal 5, @controller.session[:pagination_limit]
  end

  test "set_pagination_limit handles string limit by converting and clamping" do
    @controller.params = ActionController::Parameters.new({ limit: "invalid" })

    @controller.send(:set_pagination_limit)

    # "invalid".to_i returns 0, which gets clamped to 5
    assert_equal 5, @controller.session[:pagination_limit]
  end

  test "set_pagination_limit renders JSON for PATCH requests" do
    @controller.params = ActionController::Parameters.new({ limit: 25 })
    @controller.patch = true

    @controller.send(:set_pagination_limit)

    assert_equal({ json: { status: "ok" } }, @controller.rendered)
  end

  test "set_pagination_limit renders JSON for XHR requests" do
    @controller.params = ActionController::Parameters.new({ limit: 25 })
    @controller.xhr = true

    @controller.send(:set_pagination_limit)

    assert_equal({ json: { status: "ok" } }, @controller.rendered)
  end

  test "set_pagination_limit does not render JSON for turbo frame XHR requests" do
    @controller.params = ActionController::Parameters.new({ limit: 25 })
    @controller.xhr = true
    @controller.turbo_frame_request_value = true

    @controller.send(:set_pagination_limit)

    assert_nil @controller.rendered
  end

  test "set_pagination_limit accepts limit as parameter" do
    @controller.send(:set_pagination_limit, 30)

    assert_equal 30, @controller.session[:pagination_limit]
  end

  test "set_pagination_limit prioritizes parameter over params hash" do
    @controller.params = ActionController::Parameters.new({ limit: 10 })

    @controller.send(:set_pagination_limit, 20)

    assert_equal 20, @controller.session[:pagination_limit]
  end

  test "set_pagination_limit does not set session when limit not present" do
    @controller.params = ActionController::Parameters.new({})
    @controller.session[:pagination_limit] = 15

    @controller.send(:set_pagination_limit)

    # Session should remain unchanged
    assert_equal 15, @controller.session[:pagination_limit]
  end

  # session_pagination_limit Tests

  test "session_pagination_limit returns limit from URL params" do
    @controller.params = ActionController::Parameters.new({ limit: 25 })

    result = @controller.send(:session_pagination_limit)

    assert_equal 25, result
  end

  test "session_pagination_limit returns validated limit from URL params" do
    @controller.params = ActionController::Parameters.new({ limit: 100 })

    result = @controller.send(:session_pagination_limit)

    # Should be clamped to 50
    assert_equal 50, result
  end

  test "session_pagination_limit returns limit from session when no URL param" do
    @controller.params = ActionController::Parameters.new({})
    @controller.session[:pagination_limit] = 30

    result = @controller.send(:session_pagination_limit)

    assert_equal 30, result
  end

  test "session_pagination_limit returns default of 10 when nothing set" do
    @controller.params = ActionController::Parameters.new({})
    @controller.session[:pagination_limit] = nil

    result = @controller.send(:session_pagination_limit)

    # Default is 10, but it gets validated through clamp(5, 50)
    assert_equal 10, result
  end

  test "session_pagination_limit validates session value" do
    @controller.params = ActionController::Parameters.new({})
    @controller.session[:pagination_limit] = 200

    result = @controller.send(:session_pagination_limit)

    # Session value should be validated and clamped
    assert_equal 50, result
  end

  test "session_pagination_limit handles empty string param" do
    @controller.params = ActionController::Parameters.new({ limit: "" })

    result = @controller.send(:session_pagination_limit)

    # Empty string fails .presence check, falls back to session or default
    assert_equal 10, result
  end

  # paginate Tests

  test "paginate returns paginator and records for first page" do
    collection = RailsPulse::Summary.all
    @controller.params = ActionController::Parameters.new({ page: 1 })

    paginator, records = @controller.send(:paginate, collection, limit: 10)

    assert_kind_of RailsPulse::Paginator, paginator
    assert_operator records.count, :<=, 10
  end

  test "paginate handles page parameter correctly" do
    summaries = (1..25).map do |i|
      RailsPulse::Summary.create!(
        summarizable_type: "RailsPulse::Route",
        summarizable_id: 1,
        period_start: i.days.ago,
        period_end: i.days.ago + 1.hour,
        period_type: "hour",
        count: 10
      )
    end

    collection = RailsPulse::Summary.order(id: :desc)
    @controller.params = ActionController::Parameters.new({ page: 2 })

    paginator, records = @controller.send(:paginate, collection, limit: 10)

    assert_equal 2, paginator.page
    assert_equal 10, paginator.limit
    assert_equal 25, paginator.count
    assert_equal 10, records.count
    # Second page should have different records than first page
    first_page_ids = collection.limit(10).pluck(:id)

    refute_includes first_page_ids, records.first.id
  end

  test "paginate defaults to page 1 when page param is 0" do
    collection = RailsPulse::Summary.all
    @controller.params = ActionController::Parameters.new({ page: 0 })

    paginator, _records = @controller.send(:paginate, collection, limit: 10)

    assert_equal 1, paginator.page
  end

  test "paginate defaults to page 1 when page param is negative" do
    collection = RailsPulse::Summary.all
    @controller.params = ActionController::Parameters.new({ page: -5 })

    paginator, _records = @controller.send(:paginate, collection, limit: 10)

    assert_equal 1, paginator.page
  end

  test "paginate handles empty collection" do
    collection = RailsPulse::Summary.none
    @controller.params = ActionController::Parameters.new({ page: 1 })

    paginator, records = @controller.send(:paginate, collection, limit: 10)

    assert_equal 0, paginator.count
    assert_empty records
  end

  test "paginate handles grouped count results" do
    # Create some summaries
    3.times do |i|
      RailsPulse::Summary.create!(
        summarizable_type: "RailsPulse::Route",
        summarizable_id: i + 1,
        period_start: 1.day.ago,
        period_end: 1.day.ago + 1.hour,
        period_type: "hour",
        count: 10
      )
    end

    collection = RailsPulse::Summary.group(:summarizable_id)
    @controller.params = ActionController::Parameters.new({ page: 1 })

    paginator, records = @controller.send(:paginate, collection, limit: 10)

    # Grouped count returns a hash, paginator should handle it correctly
    assert_operator paginator.count, :>, 0
    assert_kind_of Integer, paginator.count
  end

  # validate_pagination_limit Tests

  test "validate_pagination_limit clamps to minimum of 5" do
    result = @controller.send(:validate_pagination_limit, 1)

    assert_equal 5, result
  end

  test "validate_pagination_limit clamps to maximum of 50" do
    result = @controller.send(:validate_pagination_limit, 100)

    assert_equal 50, result
  end

  test "validate_pagination_limit accepts valid values" do
    result = @controller.send(:validate_pagination_limit, 25)

    assert_equal 25, result
  end

  test "validate_pagination_limit handles boundary values" do
    assert_equal 5, @controller.send(:validate_pagination_limit, 5)
    assert_equal 50, @controller.send(:validate_pagination_limit, 50)
  end

  test "validate_pagination_limit converts strings to integers" do
    result = @controller.send(:validate_pagination_limit, "25")

    assert_equal 25, result
  end

  test "validate_pagination_limit handles invalid strings" do
    result = @controller.send(:validate_pagination_limit, "invalid")

    # "invalid".to_i returns 0, which gets clamped to 5
    assert_equal 5, result
  end

  test "validate_pagination_limit handles nil" do
    result = @controller.send(:validate_pagination_limit, nil)

    # nil.to_i returns 0, which gets clamped to 5
    assert_equal 5, result
  end

  test "validate_pagination_limit handles floats" do
    result = @controller.send(:validate_pagination_limit, 25.7)

    assert_equal 25, result
  end

  # Edge Cases

  test "set_pagination_limit with nil param does not change session" do
    @controller.session[:pagination_limit] = 20
    @controller.params = ActionController::Parameters.new({})

    @controller.send(:set_pagination_limit, nil)

    assert_equal 20, @controller.session[:pagination_limit]
  end

  test "session_pagination_limit always returns validated integer" do
    @controller.params = ActionController::Parameters.new({ limit: 25.5 })

    result = @controller.send(:session_pagination_limit)

    assert_kind_of Integer, result
    assert_equal 25, result
  end

  test "paginate with very large page number clamps to last page" do
    RailsPulse::Summary.create!(
      summarizable_type: "RailsPulse::Route",
      summarizable_id: 1,
      period_start: 1.day.ago,
      period_end: 1.day.ago + 1.hour,
      period_type: "hour",
      count: 10
    )

    collection = RailsPulse::Summary.all
    @controller.params = ActionController::Parameters.new({ page: 9999 })

    paginator, records = @controller.send(:paginate, collection, limit: 10)

    # Paginator clamps page to last valid page (1 in this case)
    assert_equal 1, paginator.page
    assert_equal 1, records.count
  end
end
