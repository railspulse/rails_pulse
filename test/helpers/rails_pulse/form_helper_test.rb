require "test_helper"

class RailsPulse::FormHelperTest < ActionView::TestCase
  include RailsPulse::FormHelper
  include RailsPulse::ApplicationHelper

  # Create a simple object to use with form_with
  class TestFormObject
    include ActiveModel::Model
    attr_accessor :period_start_range, :custom_date_range
  end

  setup do
    @form_object = TestFormObject.new
    # Setup session and params that the helper expects
    @controller = Class.new do
      attr_accessor :session, :params
      def initialize
        @session = {}
        @params = {}
      end
    end.new

    # Make controller available to view context
    @controller.session = {}
    @controller.params = {}

    # Stub session_global_filters method
    define_singleton_method(:session_global_filters) do
      @controller.session[:global_filters] || {}
    end
  end

  # ============================================================================
  # time_range_selector Tests - Preset Mode
  # ============================================================================

  test "time_range_selector renders with preset mode" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ], [ "Last Week", :last_week ] ]

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: :last_24_hours,
        mode: :preset)

      assert_includes html, "time-range-selector"
      assert_includes html, "data-mode=\"preset\""
      assert_includes html, "period_start_range"
      return html # Exit form builder block
    end
  end

  test "time_range_selector renders select with options" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ], [ "Last Week", :last_week ] ]

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: :last_week,
        mode: :preset)

      assert_includes html, "Last 24 Hours"
      assert_includes html, "Last Week"
      assert_includes html, "selected"
      return html
    end
  end

  test "time_range_selector renders hidden custom picker by default" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ], [ "Custom", :custom ] ]

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: :last_24_hours,
        mode: :preset)

      assert_includes html, "display: none"
      assert_includes html, "custom_date_range"
      return html
    end
  end

  # ============================================================================
  # time_range_selector Tests - Custom Range
  # ============================================================================

  test "time_range_selector shows custom picker when custom selected" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ], [ "Custom", :custom ] ]
    @controller.params = { q: { custom_date_range: "2024-01-01 to 2024-01-31" } }

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: :custom,
        mode: :preset)

      assert_includes html, "custom_date_range"
      assert_includes html, "2024-01-01 to 2024-01-31"
      return html
    end
  end

  test "time_range_selector uses global date range when custom selected" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ], [ "Custom", :custom ] ]
    @controller.session[:global_filters] = {
      "start_time" => "2024-01-01 00:00:00",
      "end_time" => "2024-01-31 23:59:59"
    }

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: :custom,
        mode: :preset)

      assert_includes html, "2024-01-01 00:00:00 to 2024-01-31 23:59:59"
      return html
    end
  end

  # ============================================================================
  # time_range_selector Tests - Recent/Custom Mode
  # ============================================================================

  test "time_range_selector renders with recent_custom mode" do
    time_range_options = [ [ "Recent", :recent ], [ "Custom", :custom ] ]

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: :recent,
        mode: :recent_custom)

      assert_includes html, "data-mode=\"recent_custom\""
      return html
    end
  end

  # ============================================================================
  # time_range_selector Tests - Stimulus Integration
  # ============================================================================

  test "time_range_selector includes Stimulus controller attributes" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ] ]

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: :last_24_hours,
        mode: :preset)

      assert_includes html, "rails-pulse--custom-range"
      assert_includes html, "selectWrapper"
      assert_includes html, "pickerWrapper"
      return html
    end
  end

  test "time_range_selector includes datepicker controller" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ] ]

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: :last_24_hours,
        mode: :preset)

      assert_includes html, "rails-pulse--datepicker"
      assert_includes html, "data-rails-pulse--datepicker-mode-value=\"range\""
      assert_includes html, "data-rails-pulse--datepicker-show-months-value=\"2\""
      assert_includes html, "data-rails-pulse--datepicker-type-value=\"datetime\""
      return html
    end
  end

  test "time_range_selector includes close button" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ] ]

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: :last_24_hours,
        mode: :preset)

      assert_includes html, "Close custom range"
      assert_includes html, "rails-pulse--custom-range#showSelect"
      return html
    end
  end

  # ============================================================================
  # time_range_selector Tests - Edge Cases
  # ============================================================================

  test "time_range_selector handles empty custom date value" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ] ]

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: :last_24_hours,
        mode: :preset)

      assert_includes html, "placeholder=\"Pick date range\""
      return html
    end
  end

  test "time_range_selector handles empty string selected_time_range" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ] ]

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: "",
        mode: :preset)

      assert_includes html, "time-range-selector"
      return html
    end
  end

  test "time_range_selector handles string selected_time_range" do
    time_range_options = [ [ "Last 24 Hours", :last_24_hours ] ]

    form_for(@form_object, url: "/test") do |form|
      html = time_range_selector(form,
        time_range_options: time_range_options,
        selected_time_range: "last_24_hours",
        mode: :preset)

      assert_includes html, "time-range-selector"
      return html
    end
  end
end
